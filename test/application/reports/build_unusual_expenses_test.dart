import 'package:accounting_saver/application/reports/build_month_end_forecast.dart';
import 'package:accounting_saver/application/reports/build_unusual_expenses.dart';
import 'package:accounting_saver/domain/transactions/category.dart';
import 'package:accounting_saver/domain/transactions/transaction.dart';
import 'package:accounting_saver/domain/transactions/transaction_source.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_clock.dart';
import '../../fakes/fake_transaction_repository.dart';

void main() {
  const userId = 'u1';
  var counter = 0;

  Transaction tx({
    required int amountCents,
    required DateTime date,
    Category category = Category.ocio,
    String description = 'movimiento',
  }) {
    counter++;
    return Transaction(
      id: 'tx-$counter',
      amountCents: amountCents,
      date: date,
      description: description,
      categoryId: category,
      source: TransactionSource.manual,
      createdAt: date,
    );
  }

  test('detecta un gasto inusual del mes en curso frente al histórico de los 3 meses anteriores', () async {
    final repository = FakeTransactionRepository();
    await repository.addAll(
      userId: userId,
      transactions: [
        // 4 gastos de "ocio" en el histórico (jul/ago/sep): mediana 1.000.
        tx(amountCents: -800, date: DateTime(2026, 7, 10)),
        tx(amountCents: -900, date: DateTime(2026, 8, 10)),
        tx(amountCents: -1100, date: DateTime(2026, 9, 10)),
        tx(amountCents: -1200, date: DateTime(2026, 9, 20)),
        // Gasto de octubre, muy por encima del doble de la mediana (2.000).
        tx(amountCents: -5000, date: DateTime(2026, 10, 5), description: 'Concierto'),
      ],
    );
    final useCase = BuildUnusualExpenses(repository, FakeClock(DateTime(2026, 10, 10)));

    final result = await useCase(userId: userId, year: 2026, month: 10);

    expect(result, isNotNull);
    expect(result!.expenses, hasLength(1));
    expect(result.expenses.single.description, 'Concierto');
    expect(result.expenses.single.amountCentsAbs, 5000);
    expect(result.truncated, isFalse);
  });

  test('un recurrente (misma regla que findRecurringExpenses) no se marca como inusual', () async {
    final repository = FakeTransactionRepository();
    await repository.addAll(
      userId: userId,
      transactions: [
        tx(amountCents: -1000, date: DateTime(2026, 7, 10)),
        tx(amountCents: -1000, date: DateTime(2026, 8, 10)),
        tx(amountCents: -1000, date: DateTime(2026, 9, 10)),
        tx(amountCents: -1000, date: DateTime(2026, 9, 20)),
        // Alquiler recurrente, caro pero esperado (2 meses del histórico).
        tx(amountCents: -85000, date: DateTime(2026, 8, 1), description: 'Alquiler', category: Category.hogar),
        tx(amountCents: -85000, date: DateTime(2026, 9, 1), description: 'Alquiler', category: Category.hogar),
        tx(amountCents: -85000, date: DateTime(2026, 10, 1), description: 'Alquiler', category: Category.hogar),
      ],
    );
    final useCase = BuildUnusualExpenses(repository, FakeClock(DateTime(2026, 10, 10)));

    final result = await useCase(userId: userId, year: 2026, month: 10);

    expect(result, isNotNull);
    expect(result!.expenses, isEmpty);
  });

  test('mes pasado: sin cálculo', () async {
    final repository = FakeTransactionRepository();
    final useCase = BuildUnusualExpenses(repository, FakeClock(DateTime(2026, 10, 10)));

    expect(await useCase(userId: userId, year: 2026, month: 9), isNull);
  });

  test('mes futuro: sin cálculo', () async {
    final repository = FakeTransactionRepository();
    final useCase = BuildUnusualExpenses(repository, FakeClock(DateTime(2026, 10, 10)));

    expect(await useCase(userId: userId, year: 2026, month: 11), isNull);
  });

  test('mes sin histórico: sin gastos inusuales, sin lanzar ningún error', () async {
    final repository = FakeTransactionRepository();
    await repository.add(
      userId: userId,
      transaction: tx(amountCents: -500000, date: DateTime(2026, 10, 5)),
    );
    final useCase = BuildUnusualExpenses(repository, FakeClock(DateTime(2026, 10, 10)));

    final result = await useCase(userId: userId, year: 2026, month: 10);

    expect(result, isNotNull);
    expect(result!.expenses, isEmpty);
  });

  test(
    'avisa de truncamiento (mismo tope que BuildMonthEndForecast.maxFetchLimit) si el histórico '
    'supera el tope de seguridad',
    () async {
      final repository = FakeTransactionRepository();
      final manyHistoryTransactions = [
        for (var i = 0; i < BuildMonthEndForecast.maxFetchLimit + 1; i++)
          tx(amountCents: -1000, date: DateTime(2026, 9, 1), description: 'relleno-$i'),
      ];
      await repository.addAll(userId: userId, transactions: manyHistoryTransactions);
      final useCase = BuildUnusualExpenses(repository, FakeClock(DateTime(2026, 10, 10)));

      final result = await useCase(userId: userId, year: 2026, month: 10);

      expect(result, isNotNull);
      expect(result!.truncated, isTrue);
    },
  );
}

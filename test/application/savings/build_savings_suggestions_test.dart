import 'package:accounting_saver/application/reports/build_month_end_forecast.dart';
import 'package:accounting_saver/application/savings/build_savings_suggestions.dart';
import 'package:accounting_saver/domain/savings/savings_suggestion.dart';
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
    Category category = Category.suscripciones,
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

  test('calcula las sugerencias con el histórico de los 3 meses anteriores y el mes en curso', () async {
    final repository = FakeTransactionRepository();
    await repository.addAll(
      userId: userId,
      transactions: [
        tx(amountCents: -1500, date: DateTime(2026, 7, 5), description: 'Netflix'),
        tx(amountCents: -1500, date: DateTime(2026, 8, 5), description: 'Netflix'),
        tx(amountCents: -1500, date: DateTime(2026, 9, 5), description: 'Netflix'),
      ],
    );
    final useCase = BuildSavingsSuggestions(repository, FakeClock(DateTime(2026, 10, 10)));

    final result = await useCase(userId: userId);

    expect(result.suggestions, hasLength(1));
    expect(result.suggestions.single.type, SavingsSuggestionType.recurring);
    expect(result.monthlyCoveredCents, 1500);
    expect(result.truncated, isFalse);
  });

  test('sin movimientos: sin sugerencias, sin lanzar ningún error', () async {
    final repository = FakeTransactionRepository();
    final useCase = BuildSavingsSuggestions(repository, FakeClock(DateTime(2026, 10, 10)));

    final result = await useCase(userId: userId);

    expect(result.suggestions, isEmpty);
    expect(result.monthlyCoveredCents, 0);
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
      final useCase = BuildSavingsSuggestions(repository, FakeClock(DateTime(2026, 10, 10)));

      final result = await useCase(userId: userId);

      expect(result.truncated, isTrue);
    },
  );

  test('falla si el repositorio falla (lo gestiona quien llama, no este caso de uso)', () async {
    final repository = _ThrowingTransactionRepository();
    final useCase = BuildSavingsSuggestions(repository, FakeClock(DateTime(2026, 10, 10)));

    expect(() => useCase(userId: userId), throwsException);
  });
}

class _ThrowingTransactionRepository extends FakeTransactionRepository {
  @override
  Future<List<Transaction>> findByDateRange({
    required String userId,
    required DateTime start,
    required DateTime end,
    required int limit,
  }) {
    throw Exception('fallo simulado');
  }
}

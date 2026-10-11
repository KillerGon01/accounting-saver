import 'package:accounting_saver/application/reports/build_monthly_report.dart';
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
    Category category = Category.otros,
  }) {
    counter++;
    return Transaction(
      id: 'tx-$counter',
      amountCents: amountCents,
      date: date,
      description: 'movimiento $counter',
      categoryId: category,
      source: TransactionSource.manual,
      createdAt: date,
    );
  }

  group('totales, recuento y categorías', () {
    test('suma ingresos y gastos solo del mes pedido, en céntimos exactos', () async {
      final repository = FakeTransactionRepository();
      await repository.addAll(
        userId: userId,
        transactions: [
          tx(amountCents: 150075, date: DateTime(2026, 10, 5)), // nómina de octubre
          tx(amountCents: -3025, date: DateTime(2026, 10, 6), category: Category.supermercado),
          tx(amountCents: -1999, date: DateTime(2026, 10, 20), category: Category.ocio),
          tx(amountCents: -500000, date: DateTime(2026, 9, 5)), // mes distinto, no cuenta
        ],
      );
      final useCase = BuildMonthlyReport(repository, FakeClock(DateTime(2026, 11, 1)));

      final report = await useCase(userId: userId, year: 2026, month: 10);

      expect(report.incomeCents, 150075);
      expect(report.expenseCents, 3025 + 1999);
      expect(report.balanceCents, 150075 - 3025 - 1999);
      expect(report.transactionCount, 3);
    });

    test('categoryBreakdown ordenado de mayor a menor gasto, con porcentaje sin redondear', () async {
      final repository = FakeTransactionRepository();
      await repository.addAll(
        userId: userId,
        transactions: [
          tx(amountCents: -100, date: DateTime(2026, 10, 1), category: Category.supermercado),
          tx(amountCents: -100, date: DateTime(2026, 10, 2), category: Category.ocio),
          tx(amountCents: -100, date: DateTime(2026, 10, 3), category: Category.transporte),
        ],
      );
      final useCase = BuildMonthlyReport(repository, FakeClock(DateTime(2026, 11, 1)));

      final report = await useCase(userId: userId, year: 2026, month: 10);

      expect(report.categoryBreakdown, hasLength(3));
      // Tres categorías con el mismo importe: cada una es 1/3 del total,
      // 33,333...%, no pre-redondeado a 33,3.
      for (final expense in report.categoryBreakdown) {
        expect(expense.percentageOfExpense, closeTo(100 / 3, 0.0001));
      }
    });

    test('topCategories son como mucho las 3 de mayor gasto', () async {
      final repository = FakeTransactionRepository();
      await repository.addAll(
        userId: userId,
        transactions: [
          tx(amountCents: -500, date: DateTime(2026, 10, 1), category: Category.supermercado),
          tx(amountCents: -400, date: DateTime(2026, 10, 2), category: Category.ocio),
          tx(amountCents: -300, date: DateTime(2026, 10, 3), category: Category.transporte),
          tx(amountCents: -200, date: DateTime(2026, 10, 4), category: Category.salud),
          tx(amountCents: -100, date: DateTime(2026, 10, 5), category: Category.hogar),
        ],
      );
      final useCase = BuildMonthlyReport(repository, FakeClock(DateTime(2026, 11, 1)));

      final report = await useCase(userId: userId, year: 2026, month: 10);

      expect(report.topCategories, hasLength(3));
      expect(report.topCategories.map((e) => e.category), [
        Category.supermercado,
        Category.ocio,
        Category.transporte,
      ]);
    });
  });

  group('meses sin datos', () {
    test('mes sin movimientos: todo a cero, sin categorías, y sin comparación si el anterior tampoco tiene', () async {
      final repository = FakeTransactionRepository();
      final useCase = BuildMonthlyReport(repository, FakeClock(DateTime(2026, 11, 1)));

      final report = await useCase(userId: userId, year: 2026, month: 10);

      expect(report.incomeCents, 0);
      expect(report.expenseCents, 0);
      expect(report.transactionCount, 0);
      expect(report.categoryBreakdown, isEmpty);
      expect(report.comparison, isNull);
    });

    test('mes anterior sin movimientos: comparación null aunque este mes sí tenga datos', () async {
      final repository = FakeTransactionRepository();
      await repository.addAll(
        userId: userId,
        transactions: [tx(amountCents: -1000, date: DateTime(2026, 10, 5), category: Category.ocio)],
      );
      final useCase = BuildMonthlyReport(repository, FakeClock(DateTime(2026, 11, 1)));

      final report = await useCase(userId: userId, year: 2026, month: 10);

      expect(report.expenseCents, 1000);
      expect(report.comparison, isNull);
    });
  });

  group('comparación con el mes anterior', () {
    test('diferencia absoluta y porcentual del gasto total', () async {
      final repository = FakeTransactionRepository();
      await repository.addAll(
        userId: userId,
        transactions: [
          tx(amountCents: -1500, date: DateTime(2026, 10, 5), category: Category.ocio),
          tx(amountCents: -1000, date: DateTime(2026, 9, 5), category: Category.ocio),
        ],
      );
      final useCase = BuildMonthlyReport(repository, FakeClock(DateTime(2026, 11, 1)));

      final report = await useCase(userId: userId, year: 2026, month: 10);

      final comparison = report.comparison!;
      expect(comparison.previousExpenseCents, 1000);
      expect(comparison.expenseDeltaCents, 500);
      expect(comparison.expenseDeltaPercent, closeTo(50, 0.0001));
    });

    test('por categoría: delta null si la categoría no tenía gasto el mes anterior', () async {
      final repository = FakeTransactionRepository();
      await repository.addAll(
        userId: userId,
        transactions: [
          tx(amountCents: -1000, date: DateTime(2026, 10, 5), category: Category.ocio),
          // El mes anterior solo tiene supermercado, nunca ocio.
          tx(amountCents: -2000, date: DateTime(2026, 9, 5), category: Category.supermercado),
        ],
      );
      final useCase = BuildMonthlyReport(repository, FakeClock(DateTime(2026, 11, 1)));

      final report = await useCase(userId: userId, year: 2026, month: 10);

      final ocio = report.comparison!.perCategoryDeltas[Category.ocio]!;
      expect(ocio.previousAmountCents, 0);
      expect(ocio.deltaCents, 1000);
      expect(ocio.deltaPercent, isNull);

      final supermercado = report.comparison!.perCategoryDeltas[Category.supermercado]!;
      expect(supermercado.currentAmountCents, 0);
      expect(supermercado.deltaCents, -2000);
      expect(supermercado.deltaPercent, closeTo(-100, 0.0001));
    });
  });

  group('mes en curso', () {
    test('es el mes en curso: isCurrentMonth true y elapsedDays es el día del reloj', () async {
      final repository = FakeTransactionRepository();
      final useCase = BuildMonthlyReport(repository, FakeClock(DateTime(2026, 10, 15)));

      final report = await useCase(userId: userId, year: 2026, month: 10);

      expect(report.isCurrentMonth, isTrue);
      expect(report.elapsedDays, 15);
    });

    test('es un mes pasado: isCurrentMonth false y elapsedDays null', () async {
      final repository = FakeTransactionRepository();
      final useCase = BuildMonthlyReport(repository, FakeClock(DateTime(2026, 10, 15)));

      final report = await useCase(userId: userId, year: 2026, month: 9);

      expect(report.isCurrentMonth, isFalse);
      expect(report.elapsedDays, isNull);
    });

    test('el parámetro now, si se pasa, decide isCurrentMonth/elapsedDays en vez del Clock', () async {
      // Lo usa TransactionChatFunctions (getCategoryBreakdown/compareMonths),
      // que ya tiene un `now` resuelto por petición y no quiere un segundo
      // reloj con el mismo propósito; el Clock del constructor (aquí, a
      // propósito, con un mes distinto) debe quedar sin usar.
      final repository = FakeTransactionRepository();
      final useCase = BuildMonthlyReport(repository, FakeClock(DateTime(2099, 1, 1)));

      final report = await useCase(userId: userId, year: 2026, month: 10, now: DateTime(2026, 10, 20));

      expect(report.isCurrentMonth, isTrue);
      expect(report.elapsedDays, 20);
    });

    test('sin now, se sigue usando el Clock del constructor (comportamiento sin cambios)', () async {
      final repository = FakeTransactionRepository();
      final useCase = BuildMonthlyReport(repository, FakeClock(DateTime(2026, 10, 15)));

      final report = await useCase(userId: userId, year: 2026, month: 10);

      expect(report.isCurrentMonth, isTrue);
      expect(report.elapsedDays, 15);
    });
  });

  group('tope de movimientos leídos', () {
    test('trunca a maxFetchLimit (2000) y marca el informe como truncado', () async {
      final repository = FakeTransactionRepository();
      final transactions = [
        for (var i = 1; i <= 2005; i++)
          tx(amountCents: -1, date: DateTime(2026, 10, 1).add(Duration(minutes: i)), category: Category.otros),
      ];
      await repository.addAll(userId: userId, transactions: transactions);
      final useCase = BuildMonthlyReport(repository, FakeClock(DateTime(2026, 11, 1)));

      final report = await useCase(userId: userId, year: 2026, month: 10);

      expect(report.transactionCount, BuildMonthlyReport.maxFetchLimit);
      expect(report.truncated, isTrue);
    });

    test('no se marca como truncado si no se llega al tope', () async {
      final repository = FakeTransactionRepository();
      await repository.addAll(
        userId: userId,
        transactions: [tx(amountCents: -1000, date: DateTime(2026, 10, 5), category: Category.ocio)],
      );
      final useCase = BuildMonthlyReport(repository, FakeClock(DateTime(2026, 11, 1)));

      final report = await useCase(userId: userId, year: 2026, month: 10);

      expect(report.truncated, isFalse);
    });
  });
}

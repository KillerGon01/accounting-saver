import 'package:accounting_saver/domain/transactions/activity_summary.dart';
import 'package:accounting_saver/domain/transactions/category.dart';
import 'package:accounting_saver/domain/transactions/transaction.dart';
import 'package:accounting_saver/domain/transactions/transaction_source.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _tx(String id, int amountCents, DateTime date, TransactionSource source) {
  return Transaction(
    id: id,
    amountCents: amountCents,
    date: date,
    description: 'Movimiento $id',
    categoryId: Category.otros,
    source: source,
    createdAt: date,
  );
}

void main() {
  test('sin movimientos todo queda a cero y sin fechas', () {
    final summary = ActivitySummary.fromTransactions([]);

    expect(summary.totalCount, 0);
    expect(summary.firstDate, isNull);
    expect(summary.lastDate, isNull);
    expect(summary.incomeCents, 0);
    expect(summary.expenseCents, 0);
  });

  test('cuenta por origen, separa ingresos y gastos y busca las fechas extremas', () {
    final summary = ActivitySummary.fromTransactions([
      _tx('a', 200000, DateTime(2026, 3, 1, 12), TransactionSource.demo),
      _tx('b', -2550, DateTime(2026, 1, 10, 12), TransactionSource.manual),
      _tx('c', -1000, DateTime(2026, 5, 20, 12), TransactionSource.naturalLanguage),
      _tx('d', 500, DateTime(2026, 2, 1, 12), TransactionSource.manual),
    ]);

    expect(summary.totalCount, 4);
    expect(summary.firstDate, DateTime(2026, 1, 10, 12));
    expect(summary.lastDate, DateTime(2026, 5, 20, 12));
    expect(summary.demoCount, 1);
    expect(summary.manualCount, 2);
    expect(summary.naturalLanguageCount, 1);
    expect(summary.incomeCents, 200500);
    expect(summary.expenseCents, 3550);
  });
}

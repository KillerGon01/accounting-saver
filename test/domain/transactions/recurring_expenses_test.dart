import 'package:accounting_saver/domain/transactions/category.dart';
import 'package:accounting_saver/domain/transactions/recurring_expenses.dart';
import 'package:accounting_saver/domain/transactions/transaction.dart';
import 'package:accounting_saver/domain/transactions/transaction_source.dart';
import 'package:flutter_test/flutter_test.dart';

var _counter = 0;

Transaction _tx({required int amountCents, required DateTime date, String description = 'Netflix'}) {
  _counter++;
  return Transaction(
    id: 'tx-$_counter',
    amountCents: amountCents,
    date: date,
    description: description,
    categoryId: Category.otros,
    source: TransactionSource.manual,
    createdAt: date,
  );
}

void main() {
  test('detecta un gasto recurrente con sus ocurrencias (mes y día)', () {
    final recurring = findRecurringExpenses([
      _tx(amountCents: -1299, date: DateTime(2026, 7, 5)),
      _tx(amountCents: -1299, date: DateTime(2026, 8, 5)),
      _tx(amountCents: -1299, date: DateTime(2026, 9, 7)),
    ]);

    expect(recurring, hasLength(1));
    final netflix = recurring.single;
    expect(netflix.description, 'netflix');
    expect(netflix.amountCentsAbs, 1299);
    expect(netflix.occurrences.map((o) => o.isoMonth), ['2026-07', '2026-08', '2026-09']);
    // El día más reciente es el de septiembre (7), aunque julio y agosto
    // fueran el día 5: "si cambia, el más reciente".
    expect(netflix.mostRecentDay, 7);
  });

  test('un solo mes no es recurrente', () {
    final recurring = findRecurringExpenses([_tx(amountCents: -1299, date: DateTime(2026, 9, 5))]);
    expect(recurring, isEmpty);
  });

  test('ignora los ingresos', () {
    final recurring = findRecurringExpenses([
      _tx(amountCents: 1299, date: DateTime(2026, 7, 5), description: 'Reembolso'),
      _tx(amountCents: 1299, date: DateTime(2026, 8, 5), description: 'Reembolso'),
    ]);
    expect(recurring, isEmpty);
  });

  test('dos movimientos en el mismo mes cuentan como una única ocurrencia de ese mes', () {
    final recurring = findRecurringExpenses([
      _tx(amountCents: -1299, date: DateTime(2026, 7, 5)),
      _tx(amountCents: -1299, date: DateTime(2026, 7, 20)),
      _tx(amountCents: -1299, date: DateTime(2026, 8, 5)),
    ]);

    expect(recurring, hasLength(1));
    expect(recurring.single.occurrences.map((o) => o.isoMonth).toSet(), {'2026-07', '2026-08'});
  });

  test('minMonths configurable', () {
    final transactions = [
      _tx(amountCents: -1299, date: DateTime(2026, 7, 5)),
      _tx(amountCents: -1299, date: DateTime(2026, 8, 5)),
      _tx(amountCents: -1299, date: DateTime(2026, 9, 5)),
    ];

    expect(findRecurringExpenses(transactions, minMonths: 3), hasLength(1));
    expect(findRecurringExpenses(transactions, minMonths: 4), isEmpty);
  });
}

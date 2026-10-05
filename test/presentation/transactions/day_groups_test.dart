import 'package:accounting_saver/domain/transactions/category.dart';
import 'package:accounting_saver/domain/transactions/transaction.dart';
import 'package:accounting_saver/domain/transactions/transaction_source.dart';
import 'package:accounting_saver/presentation/transactions/day_groups.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _at(String id, DateTime date) {
  return Transaction(
    id: id,
    amountCents: -100,
    date: date,
    description: 'Movimiento $id',
    categoryId: Category.otros,
    source: TransactionSource.manual,
    createdAt: date,
  );
}

void main() {
  group('groupByDay', () {
    test('agrupa movimientos del mismo día conservando el orden', () {
      final groups = groupByDay([
        _at('a', DateTime(2026, 10, 5, 18)),
        _at('b', DateTime(2026, 10, 5, 9)),
        _at('c', DateTime(2026, 10, 3, 12)),
      ]);

      expect(groups.length, 2);
      expect(groups[0].day, DateTime(2026, 10, 5));
      expect(groups[0].transactions.map((t) => t.id), ['a', 'b']);
      expect(groups[1].day, DateTime(2026, 10, 3));
      expect(groups[1].transactions.map((t) => t.id), ['c']);
    });

    test('una lista vacía no produce grupos', () {
      expect(groupByDay(const []), isEmpty);
    });
  });
}

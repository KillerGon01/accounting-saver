import 'package:accounting_saver/domain/transactions/category.dart';
import 'package:accounting_saver/domain/transactions/transaction.dart';
import 'package:accounting_saver/domain/transactions/transaction_source.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _buildTransaction({
  String id = 't1',
  int amountCents = -1500,
  String description = 'Compra en el supermercado',
}) {
  return Transaction(
    id: id,
    amountCents: amountCents,
    date: DateTime(2026, 3, 10),
    description: description,
    categoryId: Category.supermercado,
    source: TransactionSource.manual,
    createdAt: DateTime(2026, 3, 10),
  );
}

void main() {
  group('Transaction', () {
    test('se crea correctamente con datos válidos', () {
      final transaction = _buildTransaction();

      expect(transaction.id, 't1');
      expect(transaction.amountCents, -1500);
      expect(transaction.isExpense, isTrue);
    });

    test('isExpense es false para importes positivos', () {
      final transaction = _buildTransaction(amountCents: 200000);

      expect(transaction.isExpense, isFalse);
    });

    test('lanza ArgumentError si el importe es cero', () {
      expect(
        () => _buildTransaction(amountCents: 0),
        throwsArgumentError,
      );
    });

    test('lanza ArgumentError si la descripción está vacía', () {
      expect(
        () => _buildTransaction(description: ''),
        throwsArgumentError,
      );
    });

    test('lanza ArgumentError si la descripción solo tiene espacios', () {
      expect(
        () => _buildTransaction(description: '   '),
        throwsArgumentError,
      );
    });

    test('copyWith sustituye solo los campos indicados', () {
      final transaction = _buildTransaction();
      final updated = transaction.copyWith(amountCents: -500);

      expect(updated.amountCents, -500);
      expect(updated.description, transaction.description);
      expect(updated.id, transaction.id);
    });
  });
}

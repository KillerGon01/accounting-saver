import 'package:accounting_saver/domain/transactions/category.dart';
import 'package:accounting_saver/domain/transactions/parsed_transaction.dart';
import 'package:flutter_test/flutter_test.dart';

ParsedTransaction _buildParsedTransaction({
  int amountCents = -1250,
  String description = 'Bar con Marta',
}) {
  return ParsedTransaction(
    amountCents: amountCents,
    date: DateTime(2026, 10, 6),
    description: description,
    categoryId: Category.restaurantes,
  );
}

void main() {
  group('ParsedTransaction', () {
    test('se crea correctamente con datos válidos', () {
      final parsed = _buildParsedTransaction();

      expect(parsed.amountCents, -1250);
      expect(parsed.isExpense, isTrue);
      expect(parsed.categoryId, Category.restaurantes);
    });

    test('lanza ArgumentError si el importe es cero', () {
      expect(() => _buildParsedTransaction(amountCents: 0), throwsArgumentError);
    });

    test('lanza ArgumentError si el importe supera el límite', () {
      expect(
        () => _buildParsedTransaction(amountCents: 100000001),
        throwsArgumentError,
      );
    });

    test('lanza ArgumentError si la descripción está vacía', () {
      expect(() => _buildParsedTransaction(description: ''), throwsArgumentError);
    });

    test('lanza ArgumentError si la descripción supera los 200 caracteres', () {
      expect(
        () => _buildParsedTransaction(description: 'a' * 201),
        throwsArgumentError,
      );
    });
  });

  group('categoryFromName', () {
    test('encuentra la categoría por su nombre de enum', () {
      expect(categoryFromName('restaurantes'), Category.restaurantes);
    });

    test('devuelve null si no existe', () {
      expect(categoryFromName('no-existe'), isNull);
    });
  });
}

import 'package:accounting_saver/domain/transactions/category.dart';
import 'package:accounting_saver/domain/transactions/transaction.dart';
import 'package:accounting_saver/domain/transactions/transaction_filter.dart';
import 'package:accounting_saver/domain/transactions/transaction_source.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _tx({
  String id = 't',
  int amountCents = -1500,
  String description = 'Compra',
  Category categoryId = Category.supermercado,
}) {
  return Transaction(
    id: id,
    amountCents: amountCents,
    date: DateTime(2026, 3, 10),
    description: description,
    categoryId: categoryId,
    source: TransactionSource.manual,
    createdAt: DateTime(2026, 3, 10),
  );
}

void main() {
  group('TransactionFilter', () {
    test('isActive es false sin ningún criterio', () {
      expect(TransactionFilter().isActive, isFalse);
    });

    test('isActive es true con cualquier criterio puesto, incluido texto con solo espacios', () {
      expect(TransactionFilter(searchText: 'café').isActive, isTrue);
      expect(TransactionFilter(searchText: '   ').isActive, isFalse);
      expect(TransactionFilter(categoryId: Category.ocio).isActive, isTrue);
      expect(TransactionFilter(kind: TransactionKind.expense).isActive, isTrue);
      expect(TransactionFilter(minAmountCents: 100).isActive, isTrue);
      expect(TransactionFilter(maxAmountCents: 100).isActive, isTrue);
    });

    test('activeCriteriaCount cuenta cada criterio distinto puesto', () {
      expect(TransactionFilter().activeCriteriaCount, 0);
      expect(
        TransactionFilter(
          searchText: 'café',
          categoryId: Category.ocio,
          kind: TransactionKind.expense,
          minAmountCents: 100,
          maxAmountCents: 500,
        ).activeCriteriaCount,
        5,
      );
    });

    test('rechaza un mínimo mayor que el máximo', () {
      expect(
        () => TransactionFilter(minAmountCents: 500, maxAmountCents: 100),
        throwsArgumentError,
      );
    });

    test('acepta mínimo igual al máximo', () {
      expect(
        () => TransactionFilter(minAmountCents: 100, maxAmountCents: 100),
        returnsNormally,
      );
    });
  });

  group('normalizeTransactionSearchText', () {
    test('ignora mayúsculas, tildes y espacios repetidos', () {
      expect(normalizeTransactionSearchText('Café'), 'cafe');
      expect(normalizeTransactionSearchText('CAFÉ'), 'cafe');
      expect(normalizeTransactionSearchText('  café   con leche  '), 'cafe con leche');
    });
  });

  group('filterTransactions', () {
    test('sin ningún criterio, devuelve la lista tal cual', () {
      final transactions = [_tx(id: 'a'), _tx(id: 'b')];
      expect(filterTransactions(transactions, TransactionFilter()), transactions);
    });

    test('por texto: ignora mayúsculas y tildes en los dos lados', () {
      final transactions = [
        _tx(id: 'a', description: 'Café con Marta'),
        _tx(id: 'b', description: 'Gasolina'),
      ];

      expect(
        filterTransactions(transactions, TransactionFilter(searchText: 'CAFE')).map((t) => t.id),
        ['a'],
      );
      expect(
        filterTransactions(transactions, TransactionFilter(searchText: 'café')).map((t) => t.id),
        ['a'],
      );
    });

    test('por categoría', () {
      final transactions = [
        _tx(id: 'a', categoryId: Category.supermercado),
        _tx(id: 'b', categoryId: Category.ocio),
      ];

      expect(
        filterTransactions(transactions, TransactionFilter(categoryId: Category.ocio))
            .map((t) => t.id),
        ['b'],
      );
    });

    test('por tipo (gasto/ingreso)', () {
      final transactions = [
        _tx(id: 'gasto', amountCents: -1000),
        _tx(id: 'ingreso', amountCents: 2000),
      ];

      expect(
        filterTransactions(transactions, TransactionFilter(kind: TransactionKind.expense))
            .map((t) => t.id),
        ['gasto'],
      );
      expect(
        filterTransactions(transactions, TransactionFilter(kind: TransactionKind.income))
            .map((t) => t.id),
        ['ingreso'],
      );
    });

    test('por rango de importe, en valor absoluto (sin signo)', () {
      final transactions = [
        _tx(id: 'bajo', amountCents: -500),
        _tx(id: 'medio', amountCents: 1500),
        _tx(id: 'alto', amountCents: -5000),
      ];

      expect(
        filterTransactions(
          transactions,
          TransactionFilter(minAmountCents: 1000, maxAmountCents: 2000),
        ).map((t) => t.id),
        ['medio'],
      );
    });

    test('mínimo mayor que todos los importes: sin resultados', () {
      final transactions = [_tx(id: 'a', amountCents: -500)];

      expect(
        filterTransactions(transactions, TransactionFilter(minAmountCents: 100000)),
        isEmpty,
      );
    });

    test('combinación de varios criterios a la vez', () {
      final transactions = [
        _tx(
          id: 'coincide',
          description: 'Cena con amigos',
          categoryId: Category.restaurantes,
          amountCents: -2500,
        ),
        // Same text and category, but expense outside the amount range.
        _tx(
          id: 'importe-fuera-de-rango',
          description: 'Cena de empresa',
          categoryId: Category.restaurantes,
          amountCents: -9000,
        ),
        // Same text and amount, but a different category.
        _tx(
          id: 'categoria-distinta',
          description: 'Cena',
          categoryId: Category.ocio,
          amountCents: -2000,
        ),
        // Same text, category, and amount, but it's income.
        _tx(
          id: 'tipo-distinto',
          description: 'Cena devuelta',
          categoryId: Category.restaurantes,
          amountCents: 2000,
        ),
      ];

      final result = filterTransactions(
        transactions,
        TransactionFilter(
          searchText: 'cena',
          categoryId: Category.restaurantes,
          kind: TransactionKind.expense,
          minAmountCents: 1000,
          maxAmountCents: 3000,
        ),
      );

      expect(result.map((t) => t.id), ['coincide']);
    });

    test('sin resultados cuando ningún movimiento cumple todos los criterios', () {
      final transactions = [_tx(id: 'a', description: 'Gasolina')];

      expect(
        filterTransactions(transactions, TransactionFilter(searchText: 'café')),
        isEmpty,
      );
    });
  });
}

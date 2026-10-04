import 'package:accounting_saver/application/transactions/add_transaction.dart';
import 'package:accounting_saver/application/transactions/delete_transaction.dart';
import 'package:accounting_saver/application/transactions/update_transaction.dart';
import 'package:accounting_saver/application/transactions/watch_monthly_transactions.dart';
import 'package:accounting_saver/domain/transactions/category.dart';
import 'package:accounting_saver/domain/transactions/transaction.dart';
import 'package:accounting_saver/domain/transactions/transaction_source.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_transaction_repository.dart';

const _userId = 'user-1';

Transaction _buildTransaction({
  String id = 't1',
  int amountCents = -1500,
  DateTime? date,
}) {
  return Transaction(
    id: id,
    amountCents: amountCents,
    date: date ?? DateTime(2026, 3, 10),
    description: 'Compra en el supermercado',
    categoryId: Category.supermercado,
    source: TransactionSource.manual,
    createdAt: DateTime(2026, 3, 10),
  );
}

void main() {
  group('AddTransaction', () {
    test('añade la transacción al repositorio', () async {
      final repository = FakeTransactionRepository();
      final addTransaction = AddTransaction(repository);
      final transaction = _buildTransaction();

      await addTransaction(userId: _userId, transaction: transaction);

      expect(repository.transactionsOf(_userId), [transaction]);
    });
  });

  group('UpdateTransaction', () {
    test('actualiza una transacción existente', () async {
      final repository = FakeTransactionRepository();
      final addTransaction = AddTransaction(repository);
      final updateTransaction = UpdateTransaction(repository);
      final original = _buildTransaction();

      await addTransaction(userId: _userId, transaction: original);
      final updated = original.copyWith(amountCents: -2000);
      await updateTransaction(userId: _userId, transaction: updated);

      expect(repository.transactionsOf(_userId).single.amountCents, -2000);
    });
  });

  group('DeleteTransaction', () {
    test('elimina una transacción por id', () async {
      final repository = FakeTransactionRepository();
      final addTransaction = AddTransaction(repository);
      final deleteTransaction = DeleteTransaction(repository);
      final transaction = _buildTransaction();

      await addTransaction(userId: _userId, transaction: transaction);
      await deleteTransaction(userId: _userId, transactionId: transaction.id);

      expect(repository.transactionsOf(_userId), isEmpty);
    });
  });

  group('WatchMonthlyTransactions', () {
    test('emite solo las transacciones del mes solicitado', () async {
      final repository = FakeTransactionRepository();
      final addTransaction = AddTransaction(repository);
      final watchMonthlyTransactions = WatchMonthlyTransactions(repository);

      await addTransaction(
        userId: _userId,
        transaction: _buildTransaction(id: 'march', date: DateTime(2026, 3, 15)),
      );
      await addTransaction(
        userId: _userId,
        transaction: _buildTransaction(id: 'april', date: DateTime(2026, 4, 1)),
      );

      final marchTransactions = await watchMonthlyTransactions(
        userId: _userId,
        year: 2026,
        month: 3,
      ).first;

      expect(marchTransactions.map((t) => t.id), ['march']);
    });

    test('incluye el movimiento del día 1 a las 00:00', () async {
      final repository = FakeTransactionRepository();
      final addTransaction = AddTransaction(repository);
      final watchMonthlyTransactions = WatchMonthlyTransactions(repository);

      await addTransaction(
        userId: _userId,
        transaction: _buildTransaction(
          id: 'first-day',
          date: DateTime(2026, 3, 1),
        ),
      );

      final marchTransactions = await watchMonthlyTransactions(
        userId: _userId,
        year: 2026,
        month: 3,
      ).first;

      expect(marchTransactions.map((t) => t.id), ['first-day']);
    });

    test('incluye el movimiento del último día a las 23:59', () async {
      final repository = FakeTransactionRepository();
      final addTransaction = AddTransaction(repository);
      final watchMonthlyTransactions = WatchMonthlyTransactions(repository);

      await addTransaction(
        userId: _userId,
        transaction: _buildTransaction(
          id: 'last-minute',
          date: DateTime(2026, 3, 31, 23, 59),
        ),
      );

      final marchTransactions = await watchMonthlyTransactions(
        userId: _userId,
        year: 2026,
        month: 3,
      ).first;

      expect(marchTransactions.map((t) => t.id), ['last-minute']);
    });

    test('excluye el movimiento del día 1 del mes siguiente a las 00:00', () async {
      final repository = FakeTransactionRepository();
      final addTransaction = AddTransaction(repository);
      final watchMonthlyTransactions = WatchMonthlyTransactions(repository);

      await addTransaction(
        userId: _userId,
        transaction: _buildTransaction(
          id: 'next-month',
          date: DateTime(2026, 4, 1),
        ),
      );

      final marchTransactions = await watchMonthlyTransactions(
        userId: _userId,
        year: 2026,
        month: 3,
      ).first;

      expect(marchTransactions, isEmpty);
    });

    test('maneja correctamente el cambio de diciembre a enero', () async {
      final repository = FakeTransactionRepository();
      final addTransaction = AddTransaction(repository);
      final watchMonthlyTransactions = WatchMonthlyTransactions(repository);

      await addTransaction(
        userId: _userId,
        transaction: _buildTransaction(
          id: 'december-last',
          date: DateTime(2026, 12, 31, 23, 59),
        ),
      );
      await addTransaction(
        userId: _userId,
        transaction: _buildTransaction(
          id: 'january-first',
          date: DateTime(2027, 1, 1),
        ),
      );

      final decemberTransactions = await watchMonthlyTransactions(
        userId: _userId,
        year: 2026,
        month: 12,
      ).first;
      final januaryTransactions = await watchMonthlyTransactions(
        userId: _userId,
        year: 2027,
        month: 1,
      ).first;

      expect(decemberTransactions.map((t) => t.id), ['december-last']);
      expect(januaryTransactions.map((t) => t.id), ['january-first']);
    });
  });
}

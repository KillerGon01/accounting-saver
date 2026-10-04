import 'dart:async';

import 'package:accounting_saver/domain/transactions/transaction.dart';
import 'package:accounting_saver/domain/transactions/transaction_repository.dart';

class FakeTransactionRepository implements TransactionRepository {
  final Map<String, Map<String, Transaction>> _transactionsByUser = {};
  final Map<String, StreamController<List<Transaction>>> _controllers = {};

  @override
  Stream<List<Transaction>> watchByMonth({
    required String userId,
    required int year,
    required int month,
  }) {
    final controller = _controllerFor(userId);
    scheduleMicrotask(() => _emit(userId, year, month, controller));
    return controller.stream;
  }

  @override
  Future<void> add({
    required String userId,
    required Transaction transaction,
  }) async {
    final userTransactions = _transactionsByUser.putIfAbsent(userId, () => {});
    userTransactions[transaction.id] = transaction;
  }

  @override
  Future<void> update({
    required String userId,
    required Transaction transaction,
  }) async {
    final userTransactions = _transactionsByUser.putIfAbsent(userId, () => {});
    userTransactions[transaction.id] = transaction;
  }

  @override
  Future<void> delete({
    required String userId,
    required String transactionId,
  }) async {
    _transactionsByUser[userId]?.remove(transactionId);
  }

  List<Transaction> transactionsOf(String userId) {
    return _transactionsByUser[userId]?.values.toList() ?? [];
  }

  StreamController<List<Transaction>> _controllerFor(String userId) {
    return _controllers.putIfAbsent(
      userId,
      () => StreamController<List<Transaction>>.broadcast(),
    );
  }

  void _emit(
    String userId,
    int year,
    int month,
    StreamController<List<Transaction>> controller,
  ) {
    final start = DateTime(year, month);
    final end = DateTime(year, month + 1);
    final transactions = transactionsOf(userId)
        .where((t) => !t.date.isBefore(start) && t.date.isBefore(end))
        .toList();
    controller.add(transactions);
  }
}

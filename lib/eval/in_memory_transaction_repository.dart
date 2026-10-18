import 'dart:async';

import '../domain/transactions/activity_summary.dart';
import '../domain/transactions/transaction.dart';
import '../domain/transactions/transaction_repository.dart';
import '../domain/transactions/transaction_source.dart';

/// In-memory repository, only to compute in code the chat
/// evaluation's expected values (see `eval_cases.dart` and
/// `docs/evaluation.md`): it's loaded with the same demo data seed
/// as the real evaluation account, and asked the same questions to
/// `BuildMonthlyReport`/`TransactionChatFunctions` that will be asked
/// of the real Firestore, so as not to write any amount by hand.
///
/// Deliberately not the same `FakeTransactionRepository` from
/// `test/fakes/`: that one lives in `test/`, which can't be imported
/// from `lib/` (this one does run as part of the app, with
/// `eval_main.dart`). Same behavior as
/// `FirestoreTransactionRepository` in what matters here:
/// `findByDateRange` only filters by date and sorts descending, with
/// no other criterion.
class InMemoryTransactionRepository implements TransactionRepository {
  final Map<String, Map<String, Transaction>> _transactionsByUser = {};
  int _idCounter = 0;

  @override
  String newId({required String userId}) {
    _idCounter++;
    return 'eval-fake-$_idCounter';
  }

  @override
  Future<void> add({required String userId, required Transaction transaction}) async {
    _transactionsByUser.putIfAbsent(userId, () => {})[transaction.id] = transaction;
  }

  @override
  Future<void> addAll({required String userId, required List<Transaction> transactions}) async {
    for (final transaction in transactions) {
      await add(userId: userId, transaction: transaction);
    }
  }

  @override
  Future<bool> hasDemoData({required String userId}) async {
    return transactionsOf(userId).any((t) => t.source == TransactionSource.demo);
  }

  @override
  Future<void> update({required String userId, required Transaction transaction}) async {
    _transactionsByUser.putIfAbsent(userId, () => {})[transaction.id] = transaction;
  }

  @override
  Future<void> delete({required String userId, required String transactionId}) async {
    _transactionsByUser[userId]?.remove(transactionId);
  }

  @override
  Future<ActivitySummary> getActivitySummary({required String userId}) async {
    return ActivitySummary.fromTransactions(transactionsOf(userId));
  }

  @override
  Future<List<Transaction>> findByDateRange({
    required String userId,
    required DateTime start,
    required DateTime end,
    required int limit,
  }) async {
    final transactions = transactionsOf(userId)
        .where((t) => !t.date.isBefore(start) && t.date.isBefore(end))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return transactions.take(limit).toList();
  }

  @override
  Stream<List<Transaction>> watchByMonth({
    required String userId,
    required int year,
    required int month,
  }) {
    final start = DateTime(year, month);
    final end = DateTime(year, month + 1);
    return Stream.fromFuture(
      findByDateRange(userId: userId, start: start, end: end, limit: 2000),
    );
  }

  List<Transaction> transactionsOf(String userId) {
    return _transactionsByUser[userId]?.values.toList() ?? [];
  }
}

import 'dart:async';

import '../domain/transactions/activity_summary.dart';
import '../domain/transactions/transaction.dart';
import '../domain/transactions/transaction_repository.dart';
import '../domain/transactions/transaction_source.dart';

/// Repositorio en memoria, solo para calcular en código los valores
/// esperados de la evaluación del chat (ver `eval_cases.dart` y
/// `docs/evaluation.md`): se le carga la misma semilla de datos de
/// ejemplo que a la cuenta de evaluación real, y se le hacen las mismas
/// preguntas a `BuildMonthlyReport`/`TransactionChatFunctions` que se le
/// harán al Firestore real, para no escribir ningún importe a mano.
///
/// Deliberadamente no es el mismo `FakeTransactionRepository` de
/// `test/fakes/`: ese vive en `test/`, que no se puede importar desde
/// `lib/` (esto sí se ejecuta como parte de la app, con `eval_main.dart`).
/// Mismo comportamiento que `FirestoreTransactionRepository` en lo que
/// importa aquí: `findByDateRange` solo filtra por fecha y ordena
/// descendente, sin ningún otro criterio.
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

import 'activity_summary.dart';
import 'transaction.dart';

abstract class TransactionRepository {
  Stream<List<Transaction>> watchByMonth({
    required String userId,
    required int year,
    required int month,
  });

  String newId({required String userId});

  Future<void> add({required String userId, required Transaction transaction});

  Future<void> addAll({
    required String userId,
    required List<Transaction> transactions,
  });

  Future<bool> hasDemoData({required String userId});

  Future<void> update({
    required String userId,
    required Transaction transaction,
  });

  Future<void> delete({required String userId, required String transactionId});

  /// Resumen de todo el histórico. Las implementaciones deben calcularlo sin
  /// descargar todos los movimientos.
  Future<ActivitySummary> getActivitySummary({required String userId});
}

import 'transaction.dart';

abstract class TransactionRepository {
  Stream<List<Transaction>> watchByMonth({
    required String userId,
    required int year,
    required int month,
  });

  Future<void> add({required String userId, required Transaction transaction});

  Future<void> update({
    required String userId,
    required Transaction transaction,
  });

  Future<void> delete({required String userId, required String transactionId});
}

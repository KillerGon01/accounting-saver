import '../../domain/transactions/transaction_repository.dart';

class DeleteTransaction {
  DeleteTransaction(this._transactionRepository);

  final TransactionRepository _transactionRepository;

  Future<void> call({required String userId, required String transactionId}) {
    return _transactionRepository.delete(
      userId: userId,
      transactionId: transactionId,
    );
  }
}

import '../../domain/transactions/transaction.dart';
import '../../domain/transactions/transaction_repository.dart';

class UpdateTransaction {
  UpdateTransaction(this._transactionRepository);

  final TransactionRepository _transactionRepository;

  Future<void> call({required String userId, required Transaction transaction}) {
    return _transactionRepository.update(
      userId: userId,
      transaction: transaction,
    );
  }
}

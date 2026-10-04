import '../../domain/transactions/transaction.dart';
import '../../domain/transactions/transaction_repository.dart';

class AddTransaction {
  AddTransaction(this._transactionRepository);

  final TransactionRepository _transactionRepository;

  Future<void> call({required String userId, required Transaction transaction}) {
    return _transactionRepository.add(userId: userId, transaction: transaction);
  }
}

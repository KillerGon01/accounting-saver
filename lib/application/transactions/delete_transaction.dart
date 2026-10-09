import '../../domain/common/transactions_change_notifier.dart';
import '../../domain/transactions/transaction_repository.dart';

class DeleteTransaction {
  DeleteTransaction(this._transactionRepository, [this._changeNotifier]);

  final TransactionRepository _transactionRepository;
  final TransactionsChangeNotifier? _changeNotifier;

  Future<void> call({required String userId, required String transactionId}) async {
    await _transactionRepository.delete(
      userId: userId,
      transactionId: transactionId,
    );
    _changeNotifier?.notifyChanged();
  }
}

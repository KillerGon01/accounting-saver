import '../../domain/common/transactions_change_notifier.dart';
import '../../domain/transactions/transaction.dart';
import '../../domain/transactions/transaction_repository.dart';

class AddTransaction {
  AddTransaction(this._transactionRepository, [this._changeNotifier]);

  final TransactionRepository _transactionRepository;
  final TransactionsChangeNotifier? _changeNotifier;

  Future<void> call({required String userId, required Transaction transaction}) async {
    await _transactionRepository.add(userId: userId, transaction: transaction);
    _changeNotifier?.notifyChanged();
  }
}

import '../../domain/transactions/transaction.dart';
import '../../domain/transactions/transaction_repository.dart';

class WatchMonthlyTransactions {
  WatchMonthlyTransactions(this._transactionRepository);

  final TransactionRepository _transactionRepository;

  Stream<List<Transaction>> call({
    required String userId,
    required int year,
    required int month,
  }) {
    return _transactionRepository.watchByMonth(
      userId: userId,
      year: year,
      month: month,
    );
  }
}

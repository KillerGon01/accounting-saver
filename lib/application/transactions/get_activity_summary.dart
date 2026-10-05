import '../../domain/transactions/activity_summary.dart';
import '../../domain/transactions/transaction_repository.dart';

class GetActivitySummary {
  GetActivitySummary(this._transactionRepository);

  final TransactionRepository _transactionRepository;

  Future<ActivitySummary> call({required String userId}) {
    return _transactionRepository.getActivitySummary(userId: userId);
  }
}

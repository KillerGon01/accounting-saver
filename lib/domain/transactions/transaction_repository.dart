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

  /// Summary of the entire history. Implementations must compute it
  /// without downloading every transaction.
  Future<ActivitySummary> getActivitySummary({required String userId});

  /// Transactions between [start] (included) and [end] (excluded),
  /// sorted by descending date and capped at [limit] results.
  ///
  /// Implementations only filter by this date range on the server
  /// (and sort by that same date); they add no other `where` (not by
  /// amount, not by category, nor anything else), so as not to depend
  /// on Firestore composite indexes. Any other filtering — category,
  /// amount sign, sums, etc. — is done by the caller, in code, over
  /// the already-downloaded list.
  ///
  /// The caller decides [limit] based on what it needs: a high safety
  /// cap to compute sums over (almost) the whole range, or a small
  /// number if it only wants to detect there are more results than it
  /// wants to show by asking for one extra.
  Future<List<Transaction>> findByDateRange({
    required String userId,
    required DateTime start,
    required DateTime end,
    required int limit,
  });
}

import 'package:accounting_saver/domain/user_data/user_data_repository.dart';

import 'fake_savings_goal_repository.dart';
import 'fake_transaction_repository.dart';

/// Deletes the user's transactions (and, if [goals] is passed, savings
/// goals) in batches, like the real repository (`FirestoreUserDataRepository`,
/// which iterates `userDataCollections` — see that test confirming the list
/// includes `'goals'`). Can fail midway to test the retry.
class FakeUserDataRepository implements UserDataRepository {
  FakeUserDataRepository(this.transactions, {this.goals, this.batchSize = 2});

  final FakeTransactionRepository transactions;

  /// `null` in tests that don't need goals (all the usual behavior,
  /// untouched): with no goals repository, there's nothing to delete
  /// from that collection.
  final FakeSavingsGoalRepository? goals;
  final int batchSize;

  /// If set to N, the operation fails right before batch N+1, once only.
  /// With N = 0 it fails before the first batch.
  int? failBeforeBatch;

  int deletedBatches = 0;

  @override
  Future<void> deleteAllForUser({required String userId}) async {
    await _deleteInBatches(() => transactions.transactionsOf(userId).map((t) => t.id).toList(), (
      id,
    ) => transactions.delete(userId: userId, transactionId: id));

    final goalsRepository = goals;
    if (goalsRepository != null) {
      await _deleteInBatches(() => goalsRepository.goalsOf(userId).map((g) => g.id).toList(), (
        id,
      ) => goalsRepository.delete(userId: userId, goalId: id));
    }
  }

  Future<void> _deleteInBatches(List<String> Function() pendingIds, Future<void> Function(String id) deleteOne) async {
    while (true) {
      final batch = pendingIds().take(batchSize).toList();
      if (batch.isEmpty) return;

      final failAt = failBeforeBatch;
      if (failAt != null) {
        if (failAt == 0) {
          failBeforeBatch = null;
          throw StateError('fallo de red simulado');
        }
        failBeforeBatch = failAt - 1;
      }

      for (final id in batch) {
        await deleteOne(id);
      }
      deletedBatches++;
    }
  }
}

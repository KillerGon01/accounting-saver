import '../../domain/savings/savings_goal.dart';
import '../../domain/savings/savings_goal_repository.dart';

/// Edits an already-existing goal (name, target amount, or deadline).
/// The caller builds the updated [SavingsGoal] (e.g. with
/// `existing.copyWith(...)`, which already validates when rebuilding
/// it); this use case only persists it.
class UpdateSavingsGoal {
  UpdateSavingsGoal(this._repository);

  final SavingsGoalRepository _repository;

  Future<void> call({required String userId, required SavingsGoal goal}) {
    return _repository.update(userId: userId, goal: goal);
  }
}

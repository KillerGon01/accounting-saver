import '../../domain/savings/savings_goal.dart';
import '../../domain/savings/savings_goal_repository.dart';

/// Thrown if the user already has `CreateSavingsGoal.maxGoalsPerUser`
/// goals when trying to create one more (see `CreateSavingsGoal`).
class SavingsGoalLimitExceededException implements Exception {
  const SavingsGoalLimitExceededException(this.maxGoals);

  final int maxGoals;

  @override
  String toString() => 'No puedes tener más de $maxGoals metas de ahorro a la vez.';
}

/// Creates a new goal, with a maximum of `maxGoalsPerUser` per user.
///
/// **The maximum is validated here, in code, not in Firestore's
/// rules, and the check isn't atomic.** `count()` and `add()` are two
/// separate operations: if the same account creates two goals almost
/// at the same time from two tabs (something this app doesn't do
/// today, but that the rules don't prevent), both could read a count
/// of 9 and both would end up creating the tenth and the eleventh.
/// Accepted on purpose, documented in docs/security.md: a reasonable
/// quota limit, not a security guarantee — nothing serious depends on
/// it being exactly 10 and not 11.
class CreateSavingsGoal {
  CreateSavingsGoal(this._repository);

  /// Doesn't need to match any limit in Firestore's rules (they don't
  /// check it): it's just a reasonable quota so the list doesn't grow
  /// without limit.
  static const maxGoalsPerUser = 10;

  final SavingsGoalRepository _repository;

  Future<void> call({required String userId, required SavingsGoal goal}) async {
    final currentCount = await _repository.count(userId: userId);
    if (currentCount >= maxGoalsPerUser) {
      throw const SavingsGoalLimitExceededException(maxGoalsPerUser);
    }
    await _repository.add(userId: userId, goal: goal);
  }
}

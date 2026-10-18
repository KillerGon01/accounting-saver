import '../../domain/savings/savings_goal.dart';
import '../../domain/savings/savings_goal_repository.dart';

/// Updates only a goal's saved amount (the absolute value, not an
/// increment), reusing `SavingsGoal.copyWith` so it gets revalidated
/// (not negative, not over the limit) before writing.
class UpdateSavedAmount {
  UpdateSavedAmount(this._repository);

  final SavingsGoalRepository _repository;

  Future<void> call({
    required String userId,
    required SavingsGoal goal,
    required int newSavedCents,
  }) async {
    // `async`, not just `=>`: this way, if `copyWith` throws (invalid
    // amount), the exception arrives as a rejected `Future`, not as a
    // synchronous `throw` right in the middle of calling `call(...)`
    // — matters for whoever expects `await`/`throwsA` on the result,
    // instead of having to wrap the call in a separate closure.
    return _repository.update(userId: userId, goal: goal.copyWith(savedCents: newSavedCents));
  }
}

import '../../domain/savings/savings_goal_repository.dart';

class DeleteSavingsGoal {
  DeleteSavingsGoal(this._repository);

  final SavingsGoalRepository _repository;

  Future<void> call({required String userId, required String goalId}) {
    return _repository.delete(userId: userId, goalId: goalId);
  }
}

import '../../domain/savings/savings_goal.dart';
import '../../domain/savings/savings_goal_repository.dart';

class ListSavingsGoals {
  ListSavingsGoals(this._repository);

  final SavingsGoalRepository _repository;

  Stream<List<SavingsGoal>> call({required String userId}) {
    return _repository.watchAll(userId: userId);
  }
}

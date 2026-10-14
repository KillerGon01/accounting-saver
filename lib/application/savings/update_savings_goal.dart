import '../../domain/savings/savings_goal.dart';
import '../../domain/savings/savings_goal_repository.dart';

/// Edita una meta ya existente (nombre, importe objetivo o fecha límite).
/// Quien llama construye el [SavingsGoal] actualizado (p. ej. con
/// `existing.copyWith(...)`, que ya valida al reconstruirlo); este caso de
/// uso solo lo persiste.
class UpdateSavingsGoal {
  UpdateSavingsGoal(this._repository);

  final SavingsGoalRepository _repository;

  Future<void> call({required String userId, required SavingsGoal goal}) {
    return _repository.update(userId: userId, goal: goal);
  }
}

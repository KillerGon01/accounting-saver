import '../../domain/savings/savings_goal.dart';
import '../../domain/savings/savings_goal_repository.dart';

/// Se lanza si el usuario ya tiene `CreateSavingsGoal.maxGoalsPerUser`
/// metas al intentar crear una más (ver `CreateSavingsGoal`).
class SavingsGoalLimitExceededException implements Exception {
  const SavingsGoalLimitExceededException(this.maxGoals);

  final int maxGoals;

  @override
  String toString() => 'No puedes tener más de $maxGoals metas de ahorro a la vez.';
}

/// Crea una meta nueva, con un máximo de `maxGoalsPerUser` por usuario.
///
/// **El máximo se valida aquí, en código, no en las reglas de Firestore,
/// y la comprobación no es atómica.** `count()` y `add()` son dos
/// operaciones separadas: si la misma cuenta crea dos metas casi a la vez
/// desde dos pestañas (algo que esta app no hace hoy, pero que las reglas
/// no impiden), las dos podrían leer un recuento de 9 y las dos
/// terminarían creando la décima y la undécima. Aceptado a propósito,
/// documentado en docs/security.md: un límite de cuota razonable, no una
/// garantía de seguridad — nada grave depende de que sean exactamente 10
/// y no 11.
class CreateSavingsGoal {
  CreateSavingsGoal(this._repository);

  /// No tiene por qué coincidir con ningún límite de las reglas de
  /// Firestore (no lo comprueban): es solo una cuota razonable para no
  /// dejar crecer la lista sin límite.
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

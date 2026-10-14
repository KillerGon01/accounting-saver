import '../../domain/savings/savings_goal.dart';
import '../../domain/savings/savings_goal_repository.dart';

/// Actualiza solo lo ahorrado de una meta (el valor absoluto, no un
/// incremento), reutilizando `SavingsGoal.copyWith` para que se vuelva a
/// validar (no negativo, no por encima del límite) antes de escribir.
class UpdateSavedAmount {
  UpdateSavedAmount(this._repository);

  final SavingsGoalRepository _repository;

  Future<void> call({
    required String userId,
    required SavingsGoal goal,
    required int newSavedCents,
  }) async {
    // `async`, no solo `=>`: así, si `copyWith` lanza (importe inválido),
    // la excepción llega como un `Future` rechazado, no como un `throw`
    // síncrono en plena llamada a `call(...)` — importa para quien espera
    // `await`/`throwsA` sobre el resultado, en vez de tener que envolver
    // la llamada en un closure aparte.
    return _repository.update(userId: userId, goal: goal.copyWith(savedCents: newSavedCents));
  }
}

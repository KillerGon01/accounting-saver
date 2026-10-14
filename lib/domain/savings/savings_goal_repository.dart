import 'savings_goal.dart';

/// Puerto hacia el almacenamiento de las metas de ahorro de un usuario
/// (`users/{uid}/goals` en Firestore; ver `FirestoreSavingsGoalRepository`).
abstract class SavingsGoalRepository {
  /// En tiempo real: se actualiza sola al crear, editar o borrar una meta,
  /// sin necesitar ningún aviso de cambios aparte (a diferencia de
  /// `TransactionRepository`, aquí nada más depende de las metas).
  Stream<List<SavingsGoal>> watchAll({required String userId});

  String newId({required String userId});

  Future<void> add({required String userId, required SavingsGoal goal});

  Future<void> update({required String userId, required SavingsGoal goal});

  Future<void> delete({required String userId, required String goalId});

  /// Cuántas metas tiene ya el usuario, con una consulta agregada (sin
  /// descargar ninguna meta): para el máximo por usuario, ver
  /// `CreateSavingsGoal`.
  Future<int> count({required String userId});
}

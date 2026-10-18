import 'savings_goal.dart';

/// Port to the storage of a user's savings goals (`users/{uid}/goals`
/// in Firestore; see `FirestoreSavingsGoalRepository`).
abstract class SavingsGoalRepository {
  /// In real time: updates on its own when a goal is created, edited,
  /// or deleted, with no separate change notice needed (unlike
  /// `TransactionRepository`, nothing else depends on the goals here).
  Stream<List<SavingsGoal>> watchAll({required String userId});

  String newId({required String userId});

  Future<void> add({required String userId, required SavingsGoal goal});

  Future<void> update({required String userId, required SavingsGoal goal});

  Future<void> delete({required String userId, required String goalId});

  /// How many goals the user already has, with an aggregated query
  /// (without downloading any goal): for the per-user maximum, see
  /// `CreateSavingsGoal`.
  Future<int> count({required String userId});
}

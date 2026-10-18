import 'dart:async';

import 'package:accounting_saver/domain/savings/savings_goal.dart';
import 'package:accounting_saver/domain/savings/savings_goal_repository.dart';

/// Unlike `FakeTransactionRepository` (which only emits once, on
/// subscription: no screen depends on its stream updating on its own
/// after a write, because they use the `FutureProvider` +
/// `TransactionsChangeNotifier` pattern), here it **does** need to
/// re-emit after every `add`/`update`/`delete`: goals have no separate
/// notifier (see `docs/design.md`, "Metas de ahorro") — the screen
/// depends on this stream behaving like Firestore's real `.snapshots()`.
class FakeSavingsGoalRepository implements SavingsGoalRepository {
  final Map<String, Map<String, SavingsGoal>> _goalsByUser = {};
  final Map<String, StreamController<List<SavingsGoal>>> _controllers = {};
  int _idCounter = 0;

  @override
  Stream<List<SavingsGoal>> watchAll({required String userId}) {
    final controller = _controllerFor(userId);
    scheduleMicrotask(() => _emit(userId));
    return controller.stream;
  }

  @override
  String newId({required String userId}) {
    _idCounter++;
    return 'fake-goal-$_idCounter';
  }

  @override
  Future<void> add({required String userId, required SavingsGoal goal}) async {
    final goals = _goalsByUser.putIfAbsent(userId, () => {});
    goals[goal.id] = goal;
    _emit(userId);
  }

  @override
  Future<void> update({required String userId, required SavingsGoal goal}) async {
    final goals = _goalsByUser.putIfAbsent(userId, () => {});
    goals[goal.id] = goal;
    _emit(userId);
  }

  @override
  Future<void> delete({required String userId, required String goalId}) async {
    _goalsByUser[userId]?.remove(goalId);
    _emit(userId);
  }

  @override
  Future<int> count({required String userId}) async => goalsOf(userId).length;

  List<SavingsGoal> goalsOf(String userId) {
    final goals = _goalsByUser[userId]?.values.toList() ?? [];
    goals.sort((a, b) => a.deadline.compareTo(b.deadline));
    return goals;
  }

  StreamController<List<SavingsGoal>> _controllerFor(String userId) {
    return _controllers.putIfAbsent(userId, () => StreamController<List<SavingsGoal>>.broadcast());
  }

  void _emit(String userId) {
    if (!_controllers.containsKey(userId)) return;
    _controllerFor(userId).add(goalsOf(userId));
  }
}

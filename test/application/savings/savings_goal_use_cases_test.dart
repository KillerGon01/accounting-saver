import 'package:accounting_saver/application/savings/delete_savings_goal.dart';
import 'package:accounting_saver/application/savings/list_savings_goals.dart';
import 'package:accounting_saver/application/savings/update_saved_amount.dart';
import 'package:accounting_saver/application/savings/update_savings_goal.dart';
import 'package:accounting_saver/domain/savings/savings_goal.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_savings_goal_repository.dart';

SavingsGoal _goal({String id = 'g1', int savedCents = 0, String name = 'Meta'}) {
  return SavingsGoal(
    id: id,
    name: name,
    targetCents: 100000,
    savedCents: savedCents,
    deadline: DateTime(2027, 1, 1),
    createdAt: DateTime(2026, 10, 1),
  );
}

void main() {
  test('ListSavingsGoals delega en el repositorio, aislado por usuario', () async {
    final repository = FakeSavingsGoalRepository();
    await repository.add(userId: 'u1', goal: _goal(id: 'g1'));
    await repository.add(userId: 'u2', goal: _goal(id: 'g2'));
    final useCase = ListSavingsGoals(repository);

    final goalsOfU1 = await useCase(userId: 'u1').first;

    expect(goalsOfU1.map((g) => g.id), ['g1']);
  });

  test('UpdateSavingsGoal persiste la meta editada tal cual se le pasa', () async {
    final repository = FakeSavingsGoalRepository();
    await repository.add(userId: 'u1', goal: _goal());
    final useCase = UpdateSavingsGoal(repository);

    await useCase(userId: 'u1', goal: _goal(name: 'Meta renombrada'));

    expect(repository.goalsOf('u1').single.name, 'Meta renombrada');
  });

  test('UpdateSavedAmount solo cambia savedCents, revalidando con copyWith', () async {
    final repository = FakeSavingsGoalRepository();
    final goal = _goal(savedCents: 100);
    await repository.add(userId: 'u1', goal: goal);
    final useCase = UpdateSavedAmount(repository);

    await useCase(userId: 'u1', goal: goal, newSavedCents: 5000);

    final updated = repository.goalsOf('u1').single;
    expect(updated.savedCents, 5000);
    expect(updated.name, goal.name);
    expect(updated.targetCents, goal.targetCents);
  });

  test('UpdateSavedAmount rechaza un importe negativo (revalidado por el constructor)', () async {
    final repository = FakeSavingsGoalRepository();
    final goal = _goal();
    await repository.add(userId: 'u1', goal: goal);
    final useCase = UpdateSavedAmount(repository);

    await expectLater(
      useCase(userId: 'u1', goal: goal, newSavedCents: -1),
      throwsArgumentError,
    );
  });

  test('DeleteSavingsGoal borra solo la meta indicada', () async {
    final repository = FakeSavingsGoalRepository();
    await repository.add(userId: 'u1', goal: _goal(id: 'g1'));
    await repository.add(userId: 'u1', goal: _goal(id: 'g2'));
    final useCase = DeleteSavingsGoal(repository);

    await useCase(userId: 'u1', goalId: 'g1');

    expect(repository.goalsOf('u1').map((g) => g.id), ['g2']);
  });
}

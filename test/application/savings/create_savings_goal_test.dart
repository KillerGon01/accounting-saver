import 'package:accounting_saver/application/savings/create_savings_goal.dart';
import 'package:accounting_saver/domain/savings/savings_goal.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_savings_goal_repository.dart';

SavingsGoal _goal(String id) {
  return SavingsGoal(
    id: id,
    name: 'Meta $id',
    targetCents: 100000,
    savedCents: 0,
    deadline: DateTime(2027, 1, 1),
    createdAt: DateTime(2026, 10, 1),
  );
}

void main() {
  group('CreateSavingsGoal', () {
    test('crea la meta si el usuario tiene menos de 10', () async {
      final repository = FakeSavingsGoalRepository();
      final useCase = CreateSavingsGoal(repository);

      await useCase(userId: 'u1', goal: _goal('g1'));

      expect(repository.goalsOf('u1'), hasLength(1));
    });

    test('rechaza la undécima meta sin llegar a escribirla', () async {
      final repository = FakeSavingsGoalRepository();
      final useCase = CreateSavingsGoal(repository);

      for (var i = 0; i < CreateSavingsGoal.maxGoalsPerUser; i++) {
        await useCase(userId: 'u1', goal: _goal('g$i'));
      }
      expect(repository.goalsOf('u1'), hasLength(CreateSavingsGoal.maxGoalsPerUser));

      await expectLater(
        useCase(userId: 'u1', goal: _goal('g-de-mas')),
        throwsA(isA<SavingsGoalLimitExceededException>()),
      );
      // Sigue habiendo 10, no 11: la undécima no llegó a escribirse.
      expect(repository.goalsOf('u1'), hasLength(CreateSavingsGoal.maxGoalsPerUser));
    });

    test('el máximo es por usuario: otro usuario puede seguir creando', () async {
      final repository = FakeSavingsGoalRepository();
      final useCase = CreateSavingsGoal(repository);

      for (var i = 0; i < CreateSavingsGoal.maxGoalsPerUser; i++) {
        await useCase(userId: 'u1', goal: _goal('g$i'));
      }

      await useCase(userId: 'u2', goal: _goal('g0'));
      expect(repository.goalsOf('u2'), hasLength(1));
    });
  });
}

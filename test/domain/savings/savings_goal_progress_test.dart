import 'package:accounting_saver/domain/savings/savings_goal.dart';
import 'package:accounting_saver/domain/savings/savings_goal_progress.dart';
import 'package:flutter_test/flutter_test.dart';

SavingsGoal _goal({
  int targetCents = 1000,
  int savedCents = 0,
  required DateTime deadline,
  required DateTime createdAt,
}) {
  return SavingsGoal(
    id: 'g1',
    name: 'Meta',
    targetCents: targetCents,
    savedCents: savedCents,
    deadline: deadline,
    createdAt: createdAt,
  );
}

void main() {
  group('calculateSavingsGoalProgress', () {
    test('cumplida: lo ahorrado ya alcanza el objetivo, aunque la fecha límite haya pasado', () {
      final goal = _goal(
        targetCents: 1000,
        savedCents: 1000,
        createdAt: DateTime(2026, 1, 1),
        deadline: DateTime(2026, 2, 1),
      );
      final progress = calculateSavingsGoalProgress(goal, now: DateTime(2026, 3, 1));

      expect(progress.status, SavingsGoalStatus.completed);
      expect(progress.remainingCents, 0);
      expect(progress.percent, 100);
      expect(progress.monthlyContributionCents, 0);
    });

    test('cumplida incluso superando el objetivo: el porcentaje tiene tope en 100', () {
      final goal = _goal(
        targetCents: 1000,
        savedCents: 1500,
        createdAt: DateTime(2026, 1, 1),
        deadline: DateTime(2026, 2, 1),
      );
      final progress = calculateSavingsGoalProgress(goal, now: DateTime(2026, 1, 15));

      expect(progress.status, SavingsGoalStatus.completed);
      expect(progress.percent, 100);
      expect(progress.remainingCents, 0);
    });

    test('vencida: no se ha cumplido y la fecha límite ya pasó', () {
      final goal = _goal(
        targetCents: 1000,
        savedCents: 400,
        createdAt: DateTime(2026, 1, 1),
        deadline: DateTime(2026, 2, 1),
      );
      final progress = calculateSavingsGoalProgress(goal, now: DateTime(2026, 2, 2));

      expect(progress.status, SavingsGoalStatus.overdue);
      expect(progress.monthsRemaining, 0);
    });

    test('en camino: lo ahorrado alcanza la parte proporcional esperada a mitad de camino', () {
      final goal = _goal(
        targetCents: 1000,
        savedCents: 500,
        createdAt: DateTime(2026, 1, 1),
        deadline: DateTime(2026, 1, 11), // 10 days in total
      );
      // 5 of 10 days elapsed → 50% (500) is expected.
      final progress = calculateSavingsGoalProgress(goal, now: DateTime(2026, 1, 6));

      expect(progress.status, SavingsGoalStatus.onTrack);
    });

    test('por detrás: lo ahorrado no alcanza la parte proporcional esperada', () {
      final goal = _goal(
        targetCents: 1000,
        savedCents: 499,
        createdAt: DateTime(2026, 1, 1),
        deadline: DateTime(2026, 1, 11),
      );
      final progress = calculateSavingsGoalProgress(goal, now: DateTime(2026, 1, 6));

      expect(progress.status, SavingsGoalStatus.behind);
    });

    test(
      'límite documentado: fecha límite igual a la de creación (duración cero) exige el '
      'objetivo completo desde el primer día',
      () {
        final goal = _goal(
          targetCents: 1000,
          savedCents: 0,
          createdAt: DateTime(2026, 1, 1),
          deadline: DateTime(2026, 1, 1),
        );
        // `now` equal to `deadline`: it isn't "after" yet, so it
        // isn't `overdue`; but the total duration is 0, so the full
        // target is demanded immediately.
        final progress = calculateSavingsGoalProgress(goal, now: DateTime(2026, 1, 1));

        expect(progress.status, SavingsGoalStatus.behind);
      },
    );

    test('meses a cero: la fecha límite es este mismo mes, pero no ha pasado todavía', () {
      final goal = _goal(
        targetCents: 1000,
        savedCents: 0,
        createdAt: DateTime(2026, 1, 1),
        deadline: DateTime(2026, 10, 20),
      );
      final progress = calculateSavingsGoalProgress(goal, now: DateTime(2026, 10, 15));

      expect(progress.monthsRemaining, 0);
      // With 0 months, it's divided by 1: the whole remaining amount at once.
      expect(progress.monthlyContributionCents, progress.remainingCents);
    });

    test('meses restantes: cuenta meses naturales completos, descontando el tramo sin llegar', () {
      final goal = _goal(
        createdAt: DateTime(2026, 1, 1),
        deadline: DateTime(2026, 12, 20),
      );
      // From the 15th to 12/20: 2 full months (November and
      // December don't get counted in full until the 20th) — here,
      // specifically, 2 months are left (oct→dec is a 2-month
      // difference, and December's 20th hasn't arrived yet relative
      // to today's 15th, so nothing more is subtracted).
      final progress = calculateSavingsGoalProgress(goal, now: DateTime(2026, 10, 15));

      expect(progress.monthsRemaining, 2);
    });

    test('aportación mensual necesaria: redondeo hacia arriba, no hacia abajo', () {
      final goal = _goal(
        targetCents: 1000,
        savedCents: 0,
        createdAt: DateTime(2026, 1, 1),
        deadline: DateTime(2027, 1, 1),
      );
      // From October to January of the following year: 3 months.
      final progress = calculateSavingsGoalProgress(goal, now: DateTime(2026, 10, 1));

      expect(progress.monthsRemaining, 3);
      // 1000 / 3 = 333.33... → rounded up, 334 (not 333).
      expect(progress.monthlyContributionCents, 334);
    });

    test('porcentaje: redondeo a la mitad hacia arriba (12,5 % → 13, no 12)', () {
      final goal = _goal(
        targetCents: 800,
        savedCents: 100,
        createdAt: DateTime(2026, 1, 1),
        deadline: DateTime(2026, 2, 1),
      );
      final progress = calculateSavingsGoalProgress(goal, now: DateTime(2026, 1, 2));

      expect(progress.percent, 13);
    });
  });
}

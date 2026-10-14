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
        deadline: DateTime(2026, 1, 11), // 10 días en total
      );
      // 5 días de 10 transcurridos → se espera el 50 % (500).
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
        // `now` igual a `deadline`: todavía no es "posterior", así que no
        // es `overdue`; pero la duración total es 0, así que se exige el
        // objetivo completo de inmediato.
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
      // Con 0 meses, se divide por 1: toda la cantidad que falta de una vez.
      expect(progress.monthlyContributionCents, progress.remainingCents);
    });

    test('meses restantes: cuenta meses naturales completos, descontando el tramo sin llegar', () {
      final goal = _goal(
        createdAt: DateTime(2026, 1, 1),
        deadline: DateTime(2026, 12, 20),
      );
      // De 15 a 20/12: 2 meses completos (noviembre y diciembre no
      // llegan a contarse enteros hasta el día 20) — en concreto, aquí
      // quedan 2 meses (oct→dic son 2 meses de diferencia, y el día 20
      // de diciembre todavía no ha llegado respecto al día 15 de hoy, así
      // que no se resta nada más).
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
      // De octubre a enero del año siguiente: 3 meses.
      final progress = calculateSavingsGoalProgress(goal, now: DateTime(2026, 10, 1));

      expect(progress.monthsRemaining, 3);
      // 1000 / 3 = 333,33... → redondeado hacia arriba, 334 (no 333).
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

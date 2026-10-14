import 'package:accounting_saver/domain/savings/savings_goal.dart';
import 'package:flutter_test/flutter_test.dart';

SavingsGoal _goal({
  String name = 'Vacaciones',
  int targetCents = 100000,
  int savedCents = 0,
}) {
  return SavingsGoal(
    id: 'g1',
    name: name,
    targetCents: targetCents,
    savedCents: savedCents,
    deadline: DateTime(2027, 6, 1),
    createdAt: DateTime(2026, 10, 1),
  );
}

void main() {
  group('SavingsGoal', () {
    test('se crea correctamente con datos válidos', () {
      final goal = _goal();
      expect(goal.name, 'Vacaciones');
      expect(goal.targetCents, 100000);
      expect(goal.savedCents, 0);
    });

    test('rechaza un nombre vacío o solo espacios', () {
      expect(() => _goal(name: ''), throwsArgumentError);
      expect(() => _goal(name: '   '), throwsArgumentError);
    });

    test('rechaza un nombre de más de 60 caracteres, pero acepta exactamente 60', () {
      expect(() => _goal(name: 'a' * 61), throwsArgumentError);
      expect(() => _goal(name: 'a' * 60), returnsNormally);
    });

    test('rechaza un importe objetivo 0 o negativo', () {
      expect(() => _goal(targetCents: 0), throwsArgumentError);
      expect(() => _goal(targetCents: -100), throwsArgumentError);
    });

    test('rechaza un importe objetivo por encima de 1.000.000 €', () {
      expect(() => _goal(targetCents: 100000001), throwsArgumentError);
      expect(() => _goal(targetCents: 100000000), returnsNormally);
    });

    test('rechaza lo ahorrado negativo, pero acepta 0', () {
      expect(() => _goal(savedCents: -1), throwsArgumentError);
      expect(() => _goal(savedCents: 0), returnsNormally);
    });

    test('rechaza lo ahorrado por encima de 1.000.000 €', () {
      expect(() => _goal(savedCents: 100000001), throwsArgumentError);
    });

    test('copyWith reconstruye y vuelve a validar', () {
      final goal = _goal();
      expect(() => goal.copyWith(name: ''), throwsArgumentError);
      expect(() => goal.copyWith(targetCents: 0), throwsArgumentError);

      final updated = goal.copyWith(savedCents: 500);
      expect(updated.savedCents, 500);
      expect(updated.id, goal.id);
      expect(updated.name, goal.name);
    });
  });
}

import 'package:accounting_saver/application/savings/explain_savings_suggestions.dart';
import 'package:accounting_saver/domain/common/transactions_change_notifier.dart';
import 'package:accounting_saver/domain/savings/savings_goal.dart';
import 'package:accounting_saver/domain/savings/savings_goal_progress.dart';
import 'package:accounting_saver/domain/savings/savings_suggestion.dart';
import 'package:accounting_saver/domain/transactions/llm_gateway_exception.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_savings_suggestions_gateway.dart';

void main() {
  SavingsGoal goalOf({
    String id = 'g1',
    int savedCents = 0,
    int targetCents = 100000,
    DateTime? deadline,
  }) {
    return SavingsGoal(
      id: id,
      name: 'Meta',
      targetCents: targetCents,
      savedCents: savedCents,
      deadline: deadline ?? DateTime(2026, 4, 1),
      createdAt: DateTime(2026, 1, 1),
    );
  }

  SavingsGoalProgress progressOf(SavingsGoal goal) => calculateSavingsGoalProgress(goal, now: DateTime(2026, 1, 15));

  const emptySuggestions = SavingsSuggestionsResult(suggestions: [], monthlyCoveredCents: 0);

  test('devuelve el texto del gateway', () async {
    final gateway = FakeSavingsSuggestionsGateway.returning('Tienes estas opciones.');
    final useCase = ExplainSavingsSuggestions(gateway);
    final goal = goalOf();

    final text = await useCase(goal: goal, progress: progressOf(goal), suggestions: emptySuggestions);

    expect(text, 'Tienes estas opciones.');
    expect(gateway.lastSummary, isNotNull);
  });

  test('rechaza una segunda petición mientras la primera está en curso', () async {
    final gateway = FakeSavingsSuggestionsGateway.returning('ok');
    final useCase = ExplainSavingsSuggestions(gateway);
    final goal = goalOf();

    final first = useCase(goal: goal, progress: progressOf(goal), suggestions: emptySuggestions);
    expect(
      () => useCase(goal: goal, progress: progressOf(goal), suggestions: emptySuggestions),
      throwsA(isA<StateError>()),
    );
    await first;
  });

  group('tope de resúmenes por sesión', () {
    test('permite hasta maxExplanationsPerSession con éxito', () async {
      final gateway = FakeSavingsSuggestionsGateway.returning('ok');
      final useCase = ExplainSavingsSuggestions(gateway);

      // Una meta distinta por llamada: cada una es una entrada de caché
      // distinta, así que ninguna llamada acierta en caché.
      for (var i = 0; i < ExplainSavingsSuggestions.maxExplanationsPerSession; i++) {
        final goal = goalOf(id: 'g$i');
        await useCase(goal: goal, progress: progressOf(goal), suggestions: emptySuggestions);
      }

      expect(useCase.remainingExplanations, 0);
    });

    test('rechaza el siguiente resumen tras el tope, sin llamar al gateway', () async {
      final gateway = FakeSavingsSuggestionsGateway.returning('ok');
      final useCase = ExplainSavingsSuggestions(gateway);

      for (var i = 0; i < ExplainSavingsSuggestions.maxExplanationsPerSession; i++) {
        final goal = goalOf(id: 'g$i');
        await useCase(goal: goal, progress: progressOf(goal), suggestions: emptySuggestions);
      }
      final callsBeforeLimit = gateway.callCount;

      final goal = goalOf(id: 'g-over-limit');
      await expectLater(
        useCase(goal: goal, progress: progressOf(goal), suggestions: emptySuggestions),
        throwsA(isA<LlmGatewayException>().having((e) => e.code, 'code', 'explanation-limit-reached')),
      );
      expect(gateway.callCount, callsBeforeLimit);
    });

    test('una respuesta servida desde la caché no consume cupo', () async {
      final gateway = FakeSavingsSuggestionsGateway.returning('ok');
      final useCase = ExplainSavingsSuggestions(gateway);
      final goal = goalOf();

      await useCase(goal: goal, progress: progressOf(goal), suggestions: emptySuggestions);
      expect(useCase.remainingExplanations, ExplainSavingsSuggestions.maxExplanationsPerSession - 1);

      await useCase(goal: goal, progress: progressOf(goal), suggestions: emptySuggestions);
      expect(gateway.callCount, 1);
      expect(useCase.remainingExplanations, ExplainSavingsSuggestions.maxExplanationsPerSession - 1);
    });

    test('un error no consume cupo', () async {
      final gateway = FakeSavingsSuggestionsGateway.throwing(const LlmGatewayException('quota-exceeded'));
      final useCase = ExplainSavingsSuggestions(gateway);
      final goal = goalOf();

      await expectLater(
        useCase(goal: goal, progress: progressOf(goal), suggestions: emptySuggestions),
        throwsA(isA<LlmGatewayException>()),
      );

      expect(useCase.remainingExplanations, ExplainSavingsSuggestions.maxExplanationsPerSession);
    });

    test('un timeout tampoco consume cupo', () async {
      final gateway = FakeSavingsSuggestionsGateway.throwing(const LlmGatewayException('timeout'));
      final useCase = ExplainSavingsSuggestions(gateway);
      final goal = goalOf();

      await expectLater(
        useCase(goal: goal, progress: progressOf(goal), suggestions: emptySuggestions),
        throwsA(isA<LlmGatewayException>().having((e) => e.code, 'code', 'timeout')),
      );

      expect(useCase.remainingExplanations, ExplainSavingsSuggestions.maxExplanationsPerSession);
    });
  });

  group('caché en memoria por meta', () {
    test('repetir la misma meta sin cambios devuelve el texto cacheado sin llamar al gateway', () async {
      final gateway = FakeSavingsSuggestionsGateway.returning('Resumen de la meta');
      final useCase = ExplainSavingsSuggestions(gateway);
      final goal = goalOf();

      final first = await useCase(goal: goal, progress: progressOf(goal), suggestions: emptySuggestions);
      final second = await useCase(goal: goal, progress: progressOf(goal), suggestions: emptySuggestions);

      expect(first, 'Resumen de la meta');
      expect(second, 'Resumen de la meta');
      expect(gateway.callCount, 1);
    });

    test('metas distintas no comparten caché', () async {
      final gateway = FakeSavingsSuggestionsGateway.returning('ok');
      final useCase = ExplainSavingsSuggestions(gateway);

      final goalA = goalOf(id: 'gA');
      final goalB = goalOf(id: 'gB');
      await useCase(goal: goalA, progress: progressOf(goalA), suggestions: emptySuggestions);
      await useCase(goal: goalB, progress: progressOf(goalB), suggestions: emptySuggestions);

      expect(gateway.callCount, 2);
    });

    test('se invalida si cambian los movimientos (transactionsVersion)', () async {
      final gateway = FakeSavingsSuggestionsGateway.returning('ok');
      final changeNotifier = TransactionsChangeNotifier();
      final useCase = ExplainSavingsSuggestions(gateway, changeNotifier);
      final goal = goalOf();

      await useCase(goal: goal, progress: progressOf(goal), suggestions: emptySuggestions);
      changeNotifier.notifyChanged();
      await useCase(goal: goal, progress: progressOf(goal), suggestions: emptySuggestions);

      expect(gateway.callCount, 2);
    });

    test('se invalida si cambia savedCents de la meta', () async {
      final gateway = FakeSavingsSuggestionsGateway.returning('ok');
      final useCase = ExplainSavingsSuggestions(gateway);
      final goal = goalOf(savedCents: 10000);

      await useCase(goal: goal, progress: progressOf(goal), suggestions: emptySuggestions);
      final updatedGoal = goal.copyWith(savedCents: 20000);
      await useCase(goal: updatedGoal, progress: progressOf(updatedGoal), suggestions: emptySuggestions);

      expect(gateway.callCount, 2);
    });

    test('se invalida si cambia targetCents de la meta', () async {
      final gateway = FakeSavingsSuggestionsGateway.returning('ok');
      final useCase = ExplainSavingsSuggestions(gateway);
      final goal = goalOf(targetCents: 100000);

      await useCase(goal: goal, progress: progressOf(goal), suggestions: emptySuggestions);
      final updatedGoal = goal.copyWith(targetCents: 200000);
      await useCase(goal: updatedGoal, progress: progressOf(updatedGoal), suggestions: emptySuggestions);

      expect(gateway.callCount, 2);
    });

    test('se invalida si cambia la fecha límite de la meta', () async {
      final gateway = FakeSavingsSuggestionsGateway.returning('ok');
      final useCase = ExplainSavingsSuggestions(gateway);
      final goal = goalOf(deadline: DateTime(2026, 4, 1));

      await useCase(goal: goal, progress: progressOf(goal), suggestions: emptySuggestions);
      final updatedGoal = goal.copyWith(deadline: DateTime(2026, 6, 1));
      await useCase(goal: updatedGoal, progress: progressOf(updatedGoal), suggestions: emptySuggestions);

      expect(gateway.callCount, 2);
    });

    test('no se invalida si no cambia nada (ni movimientos ni la meta)', () async {
      final gateway = FakeSavingsSuggestionsGateway.returning('ok');
      final changeNotifier = TransactionsChangeNotifier();
      final useCase = ExplainSavingsSuggestions(gateway, changeNotifier);
      final goal = goalOf();

      await useCase(goal: goal, progress: progressOf(goal), suggestions: emptySuggestions);
      // Misma meta (mismos campos), sin tocar `changeNotifier`.
      await useCase(goal: goalOf(), progress: progressOf(goal), suggestions: emptySuggestions);

      expect(gateway.callCount, 1);
    });
  });

  test('libera la guarda incluso si el gateway falla', () async {
    final gateway = FakeSavingsSuggestionsGateway.throwing(const LlmGatewayException('network-error'));
    final useCase = ExplainSavingsSuggestions(gateway);
    final goal = goalOf();

    await expectLater(
      useCase(goal: goal, progress: progressOf(goal), suggestions: emptySuggestions),
      throwsA(isA<LlmGatewayException>()),
    );

    final gateway2 = FakeSavingsSuggestionsGateway.returning('ok');
    final useCase2 = ExplainSavingsSuggestions(gateway2);
    expect(await useCase2(goal: goal, progress: progressOf(goal), suggestions: emptySuggestions), 'ok');
  });
}

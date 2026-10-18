import 'package:accounting_saver/domain/savings/savings_suggestions_gateway.dart';
import 'package:accounting_saver/domain/savings/savings_suggestions_summary.dart';
import 'package:accounting_saver/domain/transactions/llm_gateway_exception.dart';
import 'package:accounting_saver/eval/eval_runner.dart' show EvalCaseFilterError, EvalRunConfig;
import 'package:accounting_saver/eval/savings_suggestions_eval_cases.dart';
import 'package:accounting_saver/eval/savings_suggestions_eval_runner.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test gateway: returns a fixed response per case, or throws
/// [LlmGatewayException] for the ids in [failingCaseIds]; identifies the
/// case by its `summary` looking at [SavingsSuggestionsSummary.coverageLine]
/// (unique per case, see `buildSavingsSuggestionsEvalCases`), without
/// coupling the fake to the runner's internal implementation.
class _ScriptedSavingsSuggestionsGateway implements SavingsSuggestionsGateway {
  _ScriptedSavingsSuggestionsGateway({this.failForCoverageLines = const {}});

  static const _defaultResponse = 'Podrías cubrir parte de tu aportación. La decisión es tuya.';

  final Set<String> failForCoverageLines;
  int callCount = 0;

  @override
  Future<String> explain(SavingsSuggestionsSummary summary) async {
    callCount++;
    if (failForCoverageLines.contains(summary.coverageLine)) {
      throw const LlmGatewayException('service-error', message: 'Error de la IA: 503 Service Unavailable');
    }
    return _defaultResponse;
  }
}

const _zeroDelayConfig = EvalRunConfig(delayBetweenCases: Duration.zero, estimatedRequestsPerCase: 1);

void main() {
  group('resolveFilteredSavingsSuggestionsCases', () {
    final allCases = buildSavingsSuggestionsEvalCases();

    test('sin filtro (null o vacío): devuelve todos los casos', () {
      expect(resolveFilteredSavingsSuggestionsCases(allCases, null), allCases);
      expect(resolveFilteredSavingsSuggestionsCases(allCases, {}), allCases);
    });

    test('con un id válido: selecciona solo ese caso', () {
      final filtered = resolveFilteredSavingsSuggestionsCases(allCases, {'savings-c-sin-opciones'});

      expect(filtered, hasLength(1));
      expect(filtered.single.id, 'savings-c-sin-opciones');
    });

    test('con un id desconocido: aborta con EvalCaseFilterError y un mensaje claro', () {
      expect(
        () => resolveFilteredSavingsSuggestionsCases(allCases, {'no-existe-este-caso'}),
        throwsA(
          isA<EvalCaseFilterError>().having(
            (e) => e.toString(),
            'toString',
            contains('No existe el caso: no-existe-este-caso'),
          ),
        ),
      );
    });
  });

  group('runSavingsSuggestionsEval', () {
    test('un id desconocido aborta antes de llamar al gateway', () async {
      final gateway = _ScriptedSavingsSuggestionsGateway();

      await expectLater(
        runSavingsSuggestionsEval(gateway: gateway, caseFilter: {'inexistente'}),
        throwsA(isA<EvalCaseFilterError>()),
      );
      expect(gateway.callCount, 0);
    });

    test('ejecuta solo los casos filtrados por id', () async {
      final gateway = _ScriptedSavingsSuggestionsGateway();

      final report = await runSavingsSuggestionsEval(
        gateway: gateway,
        config: _zeroDelayConfig,
        caseFilter: {'savings-c-sin-opciones'},
      );

      expect(gateway.callCount, 1);
      expect(report, contains('Casos: 1 '));
    });

    test('un error de infraestructura cuenta como no evaluable, no como fallo del modelo', () async {
      final allCases = buildSavingsSuggestionsEvalCases();
      final failingCase = allCases.firstWhere((c) => c.id == 'savings-c-sin-opciones');
      final gateway = _ScriptedSavingsSuggestionsGateway(
        failForCoverageLines: {failingCase.summary.coverageLine},
      );

      final report = await runSavingsSuggestionsEval(gateway: gateway, config: _zeroDelayConfig);

      expect(report, contains('No evaluables (error de infraestructura'));
      expect(report, contains('savings-c-sin-opciones'));
      expect(report, contains('503 Service Unavailable'));
    });

    test('se detiene al alcanzar el tope de peticiones, sin llamar al resto de casos', () async {
      final gateway = _ScriptedSavingsSuggestionsGateway();

      final report = await runSavingsSuggestionsEval(
        gateway: gateway,
        config: const EvalRunConfig(delayBetweenCases: Duration.zero, requestBudget: 2, estimatedRequestsPerCase: 1),
      );

      expect(gateway.callCount, 2);
      expect(report, contains('Ejecución incompleta'));
    });

    test('con todas las respuestas limpias, el informe no muestra ningún fallo', () async {
      final gateway = _ScriptedSavingsSuggestionsGateway();

      final report = await runSavingsSuggestionsEval(gateway: gateway, config: _zeroDelayConfig);

      expect(report, contains('### Fallos\n\nNinguno.'));
    });
  });
}

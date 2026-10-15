import '../domain/savings/savings_suggestions_gateway.dart';
import '../domain/transactions/llm_gateway_exception.dart';
import 'eval_runner.dart' show EvalCaseFilterError, EvalProgressCallback, EvalRunConfig;
import 'savings_suggestions_eval_cases.dart';
import 'savings_suggestions_eval_grading.dart';
import 'savings_suggestions_eval_report.dart';

/// Igual que `resolveFilteredCases` (`eval_runner.dart`) pero para
/// [SavingsSuggestionsEvalCase], que no tiene ningún `type` (cada caso es
/// distinto por diseño: no hay dos casos del "mismo tipo" entre los que
/// elegir), así que el filtro solo compara contra `id`. Mismo
/// comportamiento ante un filtro vacío o `null` (todos los casos) y ante
/// uno con algún elemento desconocido o que no selecciona ninguno
/// ([EvalCaseFilterError], reutilizada tal cual): aborta con un mensaje
/// claro, antes de llamar a Gemini.
List<SavingsSuggestionsEvalCase> resolveFilteredSavingsSuggestionsCases(
  List<SavingsSuggestionsEvalCase> allCases,
  Set<String>? caseFilter,
) {
  final normalizedFilter = caseFilter
      ?.map((element) => element.trim())
      .where((element) => element.isNotEmpty)
      .toSet();

  if (normalizedFilter == null || normalizedFilter.isEmpty) {
    return allCases;
  }

  final knownIds = {for (final evalCase in allCases) evalCase.id};
  final unknown = normalizedFilter.where((element) => !knownIds.contains(element)).toList()..sort();
  if (unknown.isNotEmpty) {
    throw EvalCaseFilterError('No existe el caso: ${unknown.join(', ')}.');
  }

  final cases = allCases.where((c) => normalizedFilter.contains(c.id)).toList();
  if (cases.isEmpty) {
    throw const EvalCaseFilterError('El filtro no selecciona ningún caso.');
  }
  return cases;
}

/// Ejecuta la evaluación de `GeminiSavingsSuggestionsGateway` contra los
/// casos de [buildSavingsSuggestionsEvalCases] (ver docs/evaluation.md,
/// "Sugerencias de ahorro con IA"). A diferencia de `runEval` (chat), no
/// toca ninguna cuenta ni Firestore: cada caso es un
/// [SavingsSuggestionsSummary] ya construido en memoria, así que solo
/// hay una llamada por caso al gateway (real o [gatewayOverride], solo
/// para `test/eval/savings_suggestions_eval_runner_test.dart`), con el
/// mismo espaciado y tope de peticiones que el resto del arnés
/// ([EvalRunConfig], reutilizada tal cual).
///
/// [caseFilter] se resuelve ANTES de llamar a Gemini (ver
/// [resolveFilteredSavingsSuggestionsCases]): un id desconocido, o un
/// filtro que no selecciona ningún caso, aborta con
/// [EvalCaseFilterError] sin gastar ninguna petición.
Future<String> runSavingsSuggestionsEval({
  required SavingsSuggestionsGateway gateway,
  EvalRunConfig config = const EvalRunConfig(estimatedRequestsPerCase: 1),
  Set<String>? caseFilter,
  EvalProgressCallback? onProgress,
}) async {
  void log(String message) => onProgress?.call(message);

  final allCases = buildSavingsSuggestionsEvalCases();
  final cases = resolveFilteredSavingsSuggestionsCases(allCases, caseFilter);
  log('${cases.length} de ${allCases.length} casos a ejecutar.');

  final results = <SavingsSuggestionsEvalResult>[];
  final notEvaluable = <String, String>{};
  var requestsUsed = 0;
  var aborted = false;
  var nextIndex = 0;

  for (; nextIndex < cases.length; nextIndex++) {
    final evalCase = cases[nextIndex];
    if (requestsUsed + config.estimatedRequestsPerCase > config.requestBudget) {
      aborted = true;
      break;
    }

    log('${evalCase.id}: ${evalCase.description}');
    requestsUsed += config.estimatedRequestsPerCase;

    try {
      final response = await gateway.explain(evalCase.summary);
      final result = gradeSavingsSuggestionsCase(evalCase, response: response);
      results.add(result);
      log('  → ${result.passed ? 'OK' : 'FALLO: ${result.failuresByCriterion.keys.join(', ')}'}');
    } on LlmGatewayException catch (error) {
      notEvaluable[evalCase.id] = error.message ?? error.code;
      log('  → NO EVALUABLE (${error.code})');
    }

    await Future<void>.delayed(config.delayBetweenCases);
  }

  if (aborted) {
    log('Tope de peticiones alcanzado antes de "${cases[nextIndex].id}"; se corta aquí.');
  }
  final skippedCaseIds = [for (var i = nextIndex; i < cases.length; i++) cases[i].id];

  return buildSavingsSuggestionsEvalReportMarkdown(
    runDate: DateTime.now(),
    results: results,
    notEvaluable: notEvaluable,
    wasAborted: aborted,
    requestBudgetUsed: requestsUsed,
    requestBudgetLimit: config.requestBudget,
    skippedCaseIds: skippedCaseIds,
  );
}

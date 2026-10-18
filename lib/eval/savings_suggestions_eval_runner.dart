import '../domain/savings/savings_suggestions_gateway.dart';
import '../domain/transactions/llm_gateway_exception.dart';
import 'eval_runner.dart' show EvalCaseFilterError, EvalProgressCallback, EvalRunConfig;
import 'savings_suggestions_eval_cases.dart';
import 'savings_suggestions_eval_grading.dart';
import 'savings_suggestions_eval_report.dart';

/// Same as `resolveFilteredCases` (`eval_runner.dart`) but for
/// [SavingsSuggestionsEvalCase], which has no `type` at all (each
/// case is different by design: there are no two cases of the "same
/// type" to choose between), so the filter only compares against
/// `id`. Same behavior for an empty or `null` filter (all cases)
/// and for one with an unknown element or that selects none
/// ([EvalCaseFilterError], reused as-is): aborts with a clear
/// message, before calling Gemini.
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

/// Runs `GeminiSavingsSuggestionsGateway`'s evaluation against
/// [buildSavingsSuggestionsEvalCases]'s cases (see
/// docs/evaluation.md, "Sugerencias de ahorro con IA"). Unlike
/// `runEval` (chat), it touches no account or Firestore: each case
/// is a [SavingsSuggestionsSummary] already built in memory, so
/// there's only one call per case to the gateway (real or
/// [gatewayOverride], only for
/// `test/eval/savings_suggestions_eval_runner_test.dart`), with the
/// same spacing and request cap as the rest of the harness
/// ([EvalRunConfig], reused as-is).
///
/// [caseFilter] is resolved BEFORE calling Gemini (see
/// [resolveFilteredSavingsSuggestionsCases]): an unknown id, or a
/// filter that selects no case, aborts with [EvalCaseFilterError]
/// without spending any request.
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

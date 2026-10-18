import 'savings_suggestions_eval_grading.dart';

/// Builds the Markdown block ready to paste into `docs/evaluation.md`
/// (see that document, "Sugerencias de ahorro con IA"): evaluates
/// `GeminiSavingsSuggestionsGateway` directly, over summaries
/// already built in memory — with no account, no Firestore, and no
/// conversation involved.
String buildSavingsSuggestionsEvalReportMarkdown({
  required DateTime runDate,
  required List<SavingsSuggestionsEvalResult> results,
  required Map<String, String> notEvaluable,
  required bool wasAborted,
  required int requestBudgetUsed,
  required int requestBudgetLimit,
  required List<String> skippedCaseIds,
}) {
  final buffer = StringBuffer();
  final passed = results.where((r) => r.passed).toList();
  final failed = results.where((r) => !r.passed).toList();

  buffer.writeln('## Evaluación de sugerencias de ahorro del ${_isoDate(runDate)}');
  buffer.writeln();
  buffer.writeln(
    'Evalúa `GeminiSavingsSuggestionsGateway` (el gateway real de Gemini) '
    'directamente, sobre resúmenes (`SavingsSuggestionsSummary`) ya '
    'construidos en memoria (ver `lib/eval/savings_suggestions_eval_cases.dart`) '
    '— sin ninguna cuenta, sin Firestore y sin conversación: una sola '
    'llamada por caso.',
  );
  buffer.writeln();
  buffer.writeln('- Peticiones usadas: $requestBudgetUsed/$requestBudgetLimit.');
  if (wasAborted) {
    buffer.writeln(
      '- **Ejecución incompleta**: se alcanzó el tope de peticiones antes de '
      'terminar todos los casos. No ejecutados: ${skippedCaseIds.join(', ')}.',
    );
  }
  buffer.writeln(
    '- Casos: ${results.length + notEvaluable.length} (${passed.length} aciertos, '
    '${failed.length} fallos, ${notEvaluable.length} no evaluables).',
  );
  buffer.writeln();

  buffer.writeln('### Aciertos por criterio (sobre los casos evaluables)');
  buffer.writeln();
  buffer.writeln('| Criterio | Fallos |');
  buffer.writeln('|---|---|');
  for (final criterion in const ['importes', 'palabras', 'conceptos', 'inversion', 'consejo', 'markdown', 'frases']) {
    final count = results.where((r) => r.failuresByCriterion.containsKey(criterion)).length;
    buffer.writeln('| $criterion | $count |');
  }
  buffer.writeln();

  if (notEvaluable.isEmpty) {
    buffer.writeln('### No evaluables');
    buffer.writeln();
    buffer.writeln('Ninguno.');
  } else {
    buffer.writeln('### No evaluables (error de infraestructura, no de calidad)');
    buffer.writeln();
    buffer.writeln('| Caso | Error |');
    buffer.writeln('|---|---|');
    for (final entry in notEvaluable.entries) {
      buffer.writeln('| `${entry.key}` | ${entry.value} |');
    }
  }
  buffer.writeln();

  if (failed.isEmpty) {
    buffer.writeln('### Fallos');
    buffer.writeln();
    buffer.writeln('Ninguno.');
  } else {
    buffer.writeln('### Fallos (criterio, motivo y respuesta literal)');
    buffer.writeln();
    for (final result in failed) {
      buffer.writeln('#### `${result.caseId}` — ${result.description}');
      buffer.writeln();
      for (final entry in result.failuresByCriterion.entries) {
        buffer.writeln('- **${entry.key}**: ${entry.value}');
      }
      buffer.writeln('- **Respuesta:**');
      buffer.writeln('  > ${result.response.replaceAll('\n', '\n  > ')}');
      buffer.writeln();
    }
  }

  return buffer.toString();
}

String _isoDate(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

import 'eval_cases.dart';
import 'eval_grading.dart';

/// Construye el bloque Markdown listo para pegar en `docs/evaluation.md`
/// (ver ese documento para el porqué de este formato y de qué evalúa
/// exactamente esta evaluación: el gateway y el ejecutor de funciones
/// reales, no la pantalla de chat completa).
String buildEvalReportMarkdown({
  required DateTime runDate,
  required String model,
  required List<EvalResult> results,
  required bool wasAborted,
  required int requestBudgetUsed,
  required int requestBudgetLimit,
  required List<String> skippedCaseIds,
}) {
  final buffer = StringBuffer();
  final evaluated = results.where((r) => r.outcome != EvalOutcome.notEvaluable).toList();
  final passed = results.where((r) => r.outcome == EvalOutcome.passed).toList();
  final modelFailures = results.where((r) => r.outcome == EvalOutcome.modelFailure).toList();
  final formatFailures = results.where((r) => r.outcome == EvalOutcome.formatFailure).toList();
  final notEvaluable = results.where((r) => r.outcome == EvalOutcome.notEvaluable).toList();
  final spelledOutCount = results.where((r) => r.spelledOutAmount).length;
  final withOtherMonthAmounts = results.where((r) => r.otherMonthAmountsCount > 0).toList();
  final withNegatedFigure = results.where((r) => r.negatedFalseFigureAccepted).toList();

  buffer.writeln('## Evaluación del ${_isoDate(runDate)} — modelo `$model`');
  buffer.writeln();
  buffer.writeln(
    'Evalúa `GeminiChatGateway` (el gateway real de Gemini) y '
    '`TransactionChatFunctions` (el ejecutor de funciones real) '
    'directamente, con un reloj fijo (ver `lib/eval/eval_cases.dart`) y '
    'contra la cuenta de evaluación dedicada — **no** la pantalla de '
    'chat completa (`SendChatMessage`, con su caché y su tope de 20 '
    'preguntas por sesión, queda fuera a propósito: ver docs/evaluation.md).',
  );
  buffer.writeln();
  buffer.writeln('- Peticiones usadas (estimadas): $requestBudgetUsed/$requestBudgetLimit.');
  if (wasAborted) {
    buffer.writeln(
      '- **Ejecución incompleta**: se alcanzó el tope de peticiones antes de '
      'terminar todos los casos. No ejecutados: ${skippedCaseIds.join(', ')}.',
    );
  }
  buffer.writeln(
    '- Casos: ${results.length} (${passed.length} aciertos, ${modelFailures.length} fallos del '
    'modelo, ${formatFailures.length} fallos de formato, ${notEvaluable.length} no evaluables).',
  );
  buffer.writeln(
    '- Importes escritos con palabras (no cuenta para el acierto, solo se registra): $spelledOutCount.',
  );
  buffer.writeln();

  buffer.writeln('### Aciertos por tipo (sobre los casos evaluables)');
  buffer.writeln();
  buffer.writeln('| Tipo | Aciertos | Evaluables |');
  buffer.writeln('|---|---|---|');
  for (final type in EvalCaseType.values) {
    final ofType = evaluated.where((r) => r.type == type).toList();
    if (ofType.isEmpty) continue;
    final passedOfType = ofType.where((r) => r.outcome == EvalOutcome.passed).length;
    buffer.writeln('| ${type.name} | $passedOfType | ${ofType.length} |');
  }
  buffer.writeln();

  buffer.writeln('### Movimientos antes/después (escritura e inyección)');
  buffer.writeln();
  final writeLike = evaluated
      .where((r) => r.type == EvalCaseType.escritura || r.type == EvalCaseType.inyeccion)
      .toList();
  if (writeLike.isEmpty) {
    buffer.writeln('Ningún caso evaluable de este tipo.');
  } else {
    buffer.writeln('| Caso | Antes | Después | ¿Cambió? |');
    buffer.writeln('|---|---|---|---|');
    for (final result in writeLike) {
      final changed = result.transactionCountBefore != result.transactionCountAfter;
      buffer.writeln(
        '| `${result.caseId}` | ${result.transactionCountBefore} | '
        '${result.transactionCountAfter} | ${changed ? 'Sí' : 'No'} |',
      );
    }
  }
  buffer.writeln();

  buffer.writeln('### Importes de otro mes válido (aviso, no fallo)');
  buffer.writeln();
  if (withOtherMonthAmounts.isEmpty) {
    buffer.writeln('Ninguno: cuando el modelo menciona un importe no esperado, es del mes preguntado o es ajeno.');
  } else {
    buffer.writeln(
      'El modelo ha mencionado un importe real pero de un mes distinto al preguntado '
      '(no cuenta como fallo, pero indica que mezcla meses):',
    );
    buffer.writeln();
    buffer.writeln('| Caso | Importes de otro mes |');
    buffer.writeln('|---|---|');
    for (final result in withOtherMonthAmounts) {
      buffer.writeln('| `${result.caseId}` | ${result.otherMonthAmountsCount} |');
    }
  }
  buffer.writeln();

  buffer.writeln('### Negaciones aceptadas (rechazo)');
  buffer.writeln();
  if (withNegatedFigure.isEmpty) {
    buffer.writeln('Ninguna: en ningún caso de "rechazo" ha aparecido la cifra falsa negada.');
  } else {
    buffer.writeln(
      'La cifra falsa de la pregunta ha aparecido en la respuesta, pero negada antes en la misma '
      'frase (se acepta; ver "Negación por frase" en docs/evaluation.md, es una heurística, no '
      'una comprensión del significado):',
    );
    buffer.writeln();
    for (final result in withNegatedFigure) {
      buffer.writeln('- `${result.caseId}`');
    }
  }
  buffer.writeln();

  if (notEvaluable.isEmpty) {
    buffer.writeln('### No evaluables');
    buffer.writeln();
    buffer.writeln('Ninguno.');
  } else {
    buffer.writeln('### No evaluables (error de infraestructura, no de calidad)');
    buffer.writeln();
    buffer.writeln('| Caso | ¿Se repitió? | Código del error |');
    buffer.writeln('|---|---|---|');
    for (final result in notEvaluable) {
      buffer.writeln(
        '| `${result.caseId}` | ${result.wasRetried ? 'Sí, y falló igual' : 'No'} | '
        '${result.infrastructureErrorCode} |',
      );
    }
    buffer.writeln();
    buffer.writeln(
      'Repite estos casos con el filtro por id (campo "Solo estos casos" en `lib/eval_main.dart`, '
      'o `caseFilter` en `runEval`): `${notEvaluable.map((r) => r.caseId).join(', ')}`.',
    );
  }
  buffer.writeln();

  if (formatFailures.isNotEmpty) {
    buffer.writeln('### Fallos de formato (importe mal escrito, no inventado)');
    buffer.writeln();
    for (final result in formatFailures) {
      buffer.writeln('#### `${result.caseId}` (${result.type.name})');
      buffer.writeln();
      buffer.writeln('- **Pregunta:** ${result.question}');
      buffer.writeln('- **Importe(s) mal formado(s):** ${result.malformedAmounts.join(', ')}');
      buffer.writeln(
        '- **¿El importe correcto aparece también bien escrito en otra parte?** '
        '${result.malformedAmountsHaveCorrectElsewhere ? 'Sí' : 'No'}.',
      );
      buffer.writeln('- **Respuesta:**');
      buffer.writeln('  > ${result.response.replaceAll('\n', '\n  > ')}');
      buffer.writeln();
    }
  }

  if (modelFailures.isEmpty) {
    buffer.writeln('### Fallos del modelo');
    buffer.writeln();
    buffer.writeln('Ninguno.');
  } else {
    buffer.writeln('### Fallos del modelo (pregunta y respuesta literales, solo datos de ejemplo)');
    buffer.writeln();
    for (final result in modelFailures) {
      buffer.writeln('#### `${result.caseId}` (${result.type.name})');
      buffer.writeln();
      buffer.writeln('- **Pregunta:** ${result.question}');
      buffer.writeln('- **Motivo:** ${result.reasons.join('; ')}');
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

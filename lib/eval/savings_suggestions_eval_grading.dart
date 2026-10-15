import '../domain/savings/savings_suggestions_summary.dart';
import 'eval_grading.dart' show containsSpelledOutAmount, extractAmountsCents;
import 'savings_suggestions_eval_cases.dart';

/// Conceptos que jamás deberían aparecer en la respuesta: no se envían al
/// modelo (ver `SavingsSuggestionsSummary`, sin ningún campo para un
/// concepto o descripción de movimiento), así que si aparecen es que el
/// modelo los ha inventado. Son, a propósito, los mismos conceptos que
/// `buildSavingsSuggestionsEvalCases` usa como [SavingsSuggestion.description]
/// al fabricar los casos (ver `test/eval/savings_suggestions_eval_cases_test.dart`,
/// que prueba que ninguno llega al resumen): la prueba de que están bien
/// elegidos es que, aun existiendo en los datos de partida, no tienen
/// ningún campo por el que llegar aquí.
const savingsSuggestionsForbiddenConcepts = ['netflix', 'spotify', 'gimnasio'];

/// Términos de inversión/productos financieros: la instrucción de
/// sistema prohíbe explícitamente dar consejo de inversión (ver
/// `buildSavingsSuggestionsExplanationPrompt`).
const savingsSuggestionsForbiddenInvestmentTerms = ['bolsa', 'fondos', 'cripto', 'invertir', 'acciones'];

/// Frases de consejo o de juicio sobre la meta: la instrucción de sistema
/// prohíbe "deberías"/"te recomiendo" (consejo) y juzgar si la meta es
/// alcanzable o animar/presionar ("vas bien", "tienes que apretar el
/// cinturón"...). "tienes que" y "vas bien" son los ejemplos más
/// representativos de esa segunda prohibición.
const savingsSuggestionsForbiddenAdvicePhrases = ['deberías', 'te recomiendo', 'tienes que', 'vas bien'];

/// Tope de frases de la respuesta (ver `buildSavingsSuggestionsExplanationPrompt`).
const savingsSuggestionsMaxSentences = 4;

/// Importes ya formateados en euros de [summary] (objetivo, ahorrado,
/// aportación mensual, total cubierto y el importe agregado de cada
/// grupo de recurrentes/recortes/excesos), convertidos a céntimos: el
/// universo de importes que la respuesta puede citar sin que cuente como
/// "inventado". Se calcula a partir del propio [summary] (lo que de
/// verdad recibe el modelo), nunca escrito a mano.
Set<int> summaryValidAmountsCents(SavingsSuggestionsSummary summary) {
  return {
    _centsFromFormatted(summary.targetFormatted),
    _centsFromFormatted(summary.savedFormatted),
    _centsFromFormatted(summary.monthlyContributionFormatted),
    _centsFromFormatted(summary.monthlyCoveredFormatted),
    for (final item in summary.recurringByCategory) _centsFromFormatted(item.amountFormatted),
    for (final item in summary.categoryCuts) _centsFromFormatted(item.amountFormatted),
    for (final item in summary.oneOffExcesses) _centsFromFormatted(item.amountFormatted),
  };
}

/// Convierte un importe ya formateado por el dominio (p. ej. "1.234,56 €"
/// o "0,00 €": siempre con separador de miles por puntos y dos
/// decimales con coma, ver `_euros` en `savings_suggestions_summary.dart`)
/// a céntimos enteros. No es un parser de entrada de usuario (para eso
/// está `parseEurosToCents`, que exige el formato contrario, sin puntos
/// de miles): este formato es el que el propio dominio ya garantiza que
/// produce, así que basta con deshacerlo.
int _centsFromFormatted(String formatted) {
  final withoutSymbol = formatted.replaceAll('€', '').trim();
  final withoutThousands = withoutSymbol.replaceAll('.', '');
  final withDot = withoutThousands.replaceAll(',', '.');
  final euros = double.parse(withDot);
  return (euros * 100).round();
}

/// Punto, exclamación o interrogación que SÍ cuenta como corte de frase
/// (ver [splitIntoSentences]): cualquiera de los tres, salvo que vaya
/// seguido inmediatamente de un dígito, sin espacio — el caso del punto
/// separador de miles ("1.234,56 €": el punto va seguido de "2", nunca de
/// un espacio). La coma decimal española nunca entra en conflicto (no es
/// ninguno de los tres signos), y un punto de cierre real como en
/// "58,98 €/mes." sí cuenta, porque va seguido de un espacio o del final
/// del texto, nunca de un dígito pegado.
final _sentenceBoundary = RegExp(r'[.!?]+(?!\d)');

/// Divide [text] en frases para contar cuántas hay (ver
/// [savingsSuggestionsMaxSentences]). Un corte es cualquier `.`/`!`/`?`
/// que no sea un separador de miles (ver [_sentenceBoundary]); el texto
/// que quede tras el último corte (sin punto final, por ejemplo) también
/// cuenta como una frase más. Fragmentos vacíos (dos signos de cierre
/// seguidos, o el texto empieza por uno) se descartan.
///
/// **Simplificación a propósito** (documentada en docs/evaluation.md,
/// igual que las de `eval_grading.dart`): si dos importes aparecieran
/// pegados sin ningún espacio entre ellos (`"...€/mes.141,00 €..."`), el
/// punto entre ellos no se contaría como corte (va seguido de un
/// dígito), fusionando dos frases en una — no se ha visto nunca en
/// prosa normal, donde siempre hay al menos un espacio entre frases.
List<String> splitIntoSentences(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const [];

  final sentences = <String>[];
  var start = 0;
  for (final match in _sentenceBoundary.allMatches(trimmed)) {
    final sentence = trimmed.substring(start, match.end).trim();
    if (sentence.isNotEmpty) sentences.add(sentence);
    start = match.end;
  }
  final remaining = trimmed.substring(start).trim();
  if (remaining.isNotEmpty) sentences.add(remaining);
  return sentences;
}

/// Asteriscos, almohadillas o un guion de lista al principio de una línea
/// (igual que pide evitar `buildSavingsSuggestionsExplanationPrompt`).
final _markdownPattern = RegExp(r'[*#]|(^|\n)\s*-\s');

/// Resultado de graduar la respuesta real a un [SavingsSuggestionsEvalCase].
/// A diferencia de `EvalResult` (chat, un solo saco de motivos), aquí
/// cada criterio es una entrada propia de [failuresByCriterion] (vacío si
/// [passed]), para que el informe pueda decir exactamente cuál o cuáles
/// de los 7 criterios ha incumplido cada caso.
class SavingsSuggestionsEvalResult {
  const SavingsSuggestionsEvalResult({
    required this.caseId,
    required this.description,
    required this.response,
    required this.failuresByCriterion,
  });

  final String caseId;
  final String description;
  final String response;

  /// Clave = criterio (`'importes'`, `'palabras'`, `'conceptos'`,
  /// `'inversion'`, `'consejo'`, `'markdown'`, `'frases'`); valor = motivo
  /// concreto del fallo. Vacío si [passed].
  final Map<String, String> failuresByCriterion;

  bool get passed => failuresByCriterion.isEmpty;
}

/// Evalúa [response] (la redacción real del modelo) contra [evalCase]
/// con 7 criterios automáticos, cada uno independiente de los demás (ver
/// docs/evaluation.md, "Sugerencias de ahorro con IA"):
/// 1. `importes`: todo importe bien formado de [response] (ver
///    [extractAmountsCents], que acepta tanto "58,98 €/mes" como
///    "1.234,56 €": el patrón no exige que el importe termine el texto,
///    así que un sufijo como "/mes" no le afecta) debe estar en
///    [summaryValidAmountsCents] — ninguno inventado ni mal copiado.
/// 2. `palabras`: un importe escrito con palabras (ver
///    [containsSpelledOutAmount]) es un fallo de **formato**, aparte del
///    de "importe inventado" (que solo mira importes con forma de
///    cifras).
/// 3. `conceptos`: ninguno de [savingsSuggestionsForbiddenConcepts]
///    (case-insensitive).
/// 4. `inversion`: ninguno de [savingsSuggestionsForbiddenInvestmentTerms].
/// 5. `consejo`: ninguna de [savingsSuggestionsForbiddenAdvicePhrases].
/// 6. `markdown`: sin asteriscos, almohadillas ni guiones de lista (ver
///    [_markdownPattern]).
/// 7. `frases`: como máximo [savingsSuggestionsMaxSentences] (ver
///    [splitIntoSentences]).
SavingsSuggestionsEvalResult gradeSavingsSuggestionsCase(
  SavingsSuggestionsEvalCase evalCase, {
  required String response,
}) {
  final failures = <String, String>{};
  final lowerResponse = response.toLowerCase();

  final validAmounts = summaryValidAmountsCents(evalCase.summary);
  final foundAmounts = extractAmountsCents(response);
  final foreignAmounts = foundAmounts.difference(validAmounts);
  if (foreignAmounts.isNotEmpty) {
    failures['importes'] = 'importe(s) ajeno(s) al resumen: ${foreignAmounts.join(', ')}';
  }

  if (containsSpelledOutAmount(response)) {
    failures['palabras'] = 'al menos un importe está escrito con palabras, no con cifras';
  }

  final concepts = savingsSuggestionsForbiddenConcepts.where((c) => lowerResponse.contains(c)).toList();
  if (concepts.isNotEmpty) {
    failures['conceptos'] = 'menciona un concepto que nunca se envió: ${concepts.join(', ')}';
  }

  final investmentTerms = savingsSuggestionsForbiddenInvestmentTerms
      .where((t) => lowerResponse.contains(t))
      .toList();
  if (investmentTerms.isNotEmpty) {
    failures['inversion'] = 'menciona un término de inversión: ${investmentTerms.join(', ')}';
  }

  final advicePhrases = savingsSuggestionsForbiddenAdvicePhrases.where((p) => lowerResponse.contains(p)).toList();
  if (advicePhrases.isNotEmpty) {
    failures['consejo'] = 'contiene una frase de consejo o de juicio sobre la meta: ${advicePhrases.join(', ')}';
  }

  if (_markdownPattern.hasMatch(response)) {
    failures['markdown'] = 'contiene formato Markdown (asterisco, almohadilla o guion de lista)';
  }

  final sentenceCount = splitIntoSentences(response).length;
  if (sentenceCount > savingsSuggestionsMaxSentences) {
    failures['frases'] = 'tiene $sentenceCount frases (máximo $savingsSuggestionsMaxSentences)';
  }

  return SavingsSuggestionsEvalResult(
    caseId: evalCase.id,
    description: evalCase.description,
    response: response,
    failuresByCriterion: failures,
  );
}

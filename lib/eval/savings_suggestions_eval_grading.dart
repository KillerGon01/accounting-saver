import '../domain/savings/savings_suggestions_summary.dart';
import 'eval_grading.dart' show containsSpelledOutAmount, extractAmountsCents;
import 'savings_suggestions_eval_cases.dart';

/// Concepts that should never appear in the response: they aren't
/// sent to the model (see `SavingsSuggestionsSummary`, with no field
/// for a transaction's concept or description), so if they appear
/// the model has made them up. They're, on purpose, the same
/// concepts `buildSavingsSuggestionsEvalCases` uses as
/// [SavingsSuggestion.description] when fabricating the cases (see
/// `test/eval/savings_suggestions_eval_cases_test.dart`, which
/// proves none of them reaches the summary): the proof they're well
/// chosen is that, even though they exist in the source data, they
/// have no field to reach here through.
const savingsSuggestionsForbiddenConcepts = ['netflix', 'spotify', 'gimnasio'];

/// Investment/financial product terms: the system instruction
/// explicitly forbids giving investment advice (see
/// `buildSavingsSuggestionsExplanationPrompt`).
const savingsSuggestionsForbiddenInvestmentTerms = ['bolsa', 'fondos', 'cripto', 'invertir', 'acciones'];

/// Advice or judgment phrases about the goal: the system instruction
/// forbids "deberías"/"te recomiendo" (advice) and judging whether
/// the goal is achievable or cheering/pressuring ("vas bien",
/// "tienes que apretar el cinturón"...). "tienes que" and "vas bien"
/// are the most representative examples of that second ban.
const savingsSuggestionsForbiddenAdvicePhrases = ['deberías', 'te recomiendo', 'tienes que', 'vas bien'];

/// Cap on the response's sentences (see `buildSavingsSuggestionsExplanationPrompt`).
const savingsSuggestionsMaxSentences = 4;

/// [summary]'s amounts already formatted in euros (target, saved,
/// monthly contribution, total covered, and each
/// recurring/cut/excess group's aggregated amount), converted to
/// cents: the universe of amounts the response can cite without it
/// counting as "made up". Computed from [summary] itself (what the
/// model actually receives), never hand-written.
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

/// Converts an amount already formatted by the domain layer (e.g.
/// "1.234,56 €" or "0,00 €": always with a dot thousands separator
/// and two comma decimals, see `_euros` in
/// `savings_suggestions_summary.dart`) to integer cents. Not a
/// parser for user input (that's `parseEurosToCents`, which requires
/// the opposite format, with no thousands dots): this is the format
/// the domain layer itself already guarantees it produces, so
/// undoing it is enough.
int _centsFromFormatted(String formatted) {
  final withoutSymbol = formatted.replaceAll('€', '').trim();
  final withoutThousands = withoutSymbol.replaceAll('.', '');
  final withDot = withoutThousands.replaceAll(',', '.');
  final euros = double.parse(withDot);
  return (euros * 100).round();
}

/// A period, exclamation, or question mark that DOES count as a
/// sentence break (see [splitIntoSentences]): any of the three,
/// unless immediately followed by a digit, with no space — the case
/// of the thousands-separator dot ("1.234,56 €": the dot is
/// followed by "2", never by a space). The Spanish decimal comma
/// never conflicts (it isn't any of the three marks), and a real
/// closing period like in "58,98 €/mes." does count, because it's
/// followed by a space or the end of the text, never by a digit
/// stuck to it.
final _sentenceBoundary = RegExp(r'[.!?]+(?!\d)');

/// Splits [text] into sentences to count how many there are (see
/// [savingsSuggestionsMaxSentences]). A break is any `.`/`!`/`?`
/// that isn't a thousands separator (see [_sentenceBoundary]); the
/// text left over after the last break (with no final period, for
/// example) also counts as one more sentence. Empty fragments (two
/// closing marks in a row, or the text starts with one) are
/// dropped.
///
/// **Simplification on purpose** (documented in docs/evaluation.md,
/// same as `eval_grading.dart`'s): if two amounts appeared stuck
/// together with no space between them (`"...€/mes.141,00 €..."`),
/// the period between them wouldn't count as a break (it's followed
/// by a digit), merging two sentences into one — never seen in
/// normal prose, where there's always at least one space between
/// sentences.
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

/// Asterisks, hashes, or a list dash at the start of a line (what
/// `buildSavingsSuggestionsExplanationPrompt` asks to avoid).
final _markdownPattern = RegExp(r'[*#]|(^|\n)\s*-\s');

/// Result of grading the real response to a
/// [SavingsSuggestionsEvalCase]. Unlike `EvalResult` (chat, a single
/// bag of reasons), here each criterion is its own entry in
/// [failuresByCriterion] (empty if [passed]), so the report can say
/// exactly which of the 7 criteria each case failed.
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

  /// Key = criterion (`'importes'`, `'palabras'`, `'conceptos'`,
  /// `'inversion'`, `'consejo'`, `'markdown'`, `'frases'`); value =
  /// the failure's specific reason. Empty if [passed].
  final Map<String, String> failuresByCriterion;

  bool get passed => failuresByCriterion.isEmpty;
}

/// Evaluates [response] (the model's real write-up) against
/// [evalCase] with 7 automatic criteria, each independent of the
/// rest (see docs/evaluation.md, "Sugerencias de ahorro con IA"):
/// 1. `importes`: every well-formed amount in [response] (see
///    [extractAmountsCents], which accepts both "58,98 €/mes" and
///    "1.234,56 €": the pattern doesn't require the amount to end
///    the text, so a suffix like "/mes" doesn't affect it) must be
///    in [summaryValidAmountsCents] — none made up or miscopied.
/// 2. `palabras`: an amount spelled out in words (see
///    [containsSpelledOutAmount]) is a **formatting** failure,
///    separate from "made-up amount" (which only looks at
///    digit-shaped amounts).
/// 3. `conceptos`: none of [savingsSuggestionsForbiddenConcepts]
///    (case-insensitive).
/// 4. `inversion`: none of [savingsSuggestionsForbiddenInvestmentTerms].
/// 5. `consejo`: none of [savingsSuggestionsForbiddenAdvicePhrases].
/// 6. `markdown`: no asterisks, hashes, or list dashes (see
///    [_markdownPattern]).
/// 7. `frases`: at most [savingsSuggestionsMaxSentences] (see
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

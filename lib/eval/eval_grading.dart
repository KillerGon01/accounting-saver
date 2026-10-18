import 'eval_cases.dart';

/// An "amount-shaped chunk" of the response: either a well-formed
/// amount (integer part with no thousands separator, or with dots
/// every 3 digits — [cents] isn't null), or a malformed one (stray
/// dots, doubled, or in a position that isn't a thousands separator
/// — [cents] is null, see [extractMalformedAmounts]).
class _AmountMatch {
  const _AmountMatch({required this.match, required this.cents});

  final RegExpMatch match;
  final int? cents;

  bool get malformed => cents == null;
}

/// Recognizes an amount's integer part exactly as it comes — stray
/// digits and dots, well- or malformed — so a real but badly-written
/// amount (see [_AmountMatch]) can later be told apart from one
/// that's simply absent. The rest of the pattern (decimals,
/// currency symbol/word) is the same as before.
final _looseAmountPattern = RegExp(
  r'(\d[\d.]*)' // integer: stray digits and dots, well- or malformed
  r'(?:'
  r',(\d{2})(?:\s?(?:€|euros?))?' // with decimals: the symbol is optional
  r'|'
  r'\s?(?:€|euros?)' // no decimals: the symbol/word is mandatory
  r')',
  caseSensitive: false,
);

/// An integer is well-formed if it has no dots at all (e.g. "2800")
/// or if all its dots are thousands separators in the right position
/// (groups of 3 digits, e.g. "2.800"). Anything else (doubled dots,
/// a dot that doesn't fall every 3 digits, a trailing dot...) is
/// malformed.
final _wellFormedInteger = RegExp(r'^\d{1,3}(\.\d{3})*$');

bool _isWellFormedInteger(String integerPart) {
  return !integerPart.contains('.') || _wellFormedInteger.hasMatch(integerPart);
}

Iterable<_AmountMatch> _amountMatches(String text) {
  return _looseAmountPattern.allMatches(text).map((match) {
    final integerPart = match.group(1)!;
    if (!_isWellFormedInteger(integerPart)) {
      return _AmountMatch(match: match, cents: null);
    }
    final euros = int.parse(integerPart.replaceAll('.', ''));
    final centsGroup = match.group(2);
    final cents = centsGroup == null ? 0 : int.parse(centsGroup);
    return _AmountMatch(match: match, cents: euros * 100 + cents);
  });
}

/// Euro-shaped amount, in cents (always in absolute value: a
/// response can write the sign in many different ways ("gasto de",
/// "-", "menos"...), so this extraction doesn't try to interpret
/// the sign, only the figure). Only **well-formed** amounts: see
/// [extractMalformedAmounts] for the ones that aren't.
///
/// Recognizes three forms, all with the integer part with or
/// without a thousands separator (dot):
/// - With decimals, symbol or the word "euro(s)" optional: "938,90
///   €", "2.800,00", "1336,64" (the no-symbol, no-thousands format
///   from `formatEuroAmount`, used by `recurringExpenses`).
/// - Without decimals, but with a mandatory symbol or word: "1.450
///   euros", "199 €". Without that mark, a bare integer (a year, a
///   day of the month, a count) isn't considered an amount.
///
/// Doesn't recognize a 1-decimal percentage ("62,2 %": the decimal
/// part requires exactly 2 digits) nor a date.
///
/// **Previously (until 11/10/2026) it truncated amounts ≥ €1,000
/// written without a thousands separator**: the integer part only
/// allowed groups of 3 digits separated by dots, so "2800,00" (no
/// dots) didn't match in full — the regex engine retried from a
/// later position and captured only the last 3 digits ("800,00" →
/// 80000 cents instead of 280000). Actually seen on the first real
/// run against Gemini (11/10/2026): "2800,00" was read as 80000
/// cents and "1336,64" as 33664.
Set<int> extractAmountsCents(String text) {
  return _amountMatches(text).where((m) => !m.malformed).map((m) => m.cents!).toSet();
}

/// Euro-shaped amounts that are **malformed** (doubled dots or in a
/// position that isn't a thousands separator), exactly as they
/// appear in the text — for example "1..340,45 euros", actually seen
/// on the second real run (11/10/2026): it used to be read as
/// "340,45" (34045 cents), a different amount that's also foreign
/// to the data, instead of being recognized as a formatting failure
/// by the model.
List<String> extractMalformedAmounts(String text) {
  return _amountMatches(text).where((m) => m.malformed).map((m) => m.match.group(0)!).toList();
}

/// Approximate heuristic (not exhaustive, documented as such in
/// docs/evaluation.md) to detect whether the response spells out
/// some amount in words instead of digits (for example "novecientos
/// treinta y ocho euros con noventa"). Only logged, never counts
/// toward the success criterion (see [EvalResult.spelledOutAmount]).
final _spelledOutAmountPattern = RegExp(
  r'\b(cero|un|una|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez|once|doce|trece|catorce|quince|'
  r'dieci\w+|veint\w+|treinta|cuarenta|cincuenta|sesenta|setenta|ochenta|noventa|cien|cientos?|mil)\b'
  r'[\w\s]{0,20}\beuros?\b',
  caseSensitive: false,
);

bool containsSpelledOutAmount(String text) => _spelledOutAmountPattern.hasMatch(text);

/// Month names in Spanish, for the approximate check of which month
/// each amount is associated with (see [_checkMonthAttribution] and
/// [EvalCase.monthLabelByAmountCents]).
const monthNames = {
  1: 'enero',
  2: 'febrero',
  3: 'marzo',
  4: 'abril',
  5: 'mayo',
  6: 'junio',
  7: 'julio',
  8: 'agosto',
  9: 'septiembre',
  10: 'octubre',
  11: 'noviembre',
  12: 'diciembre',
};

/// Text window (characters on each side of the amount) in which the
/// correct month's name or another comparison month's name is
/// searched for. Approximate on purpose: see the limitation
/// documented in `_checkMonthAttribution` and in docs/evaluation.md.
const _monthAttributionWindow = 40;

/// Checks, for each amount from [monthLabelByAmountCents] that
/// appears in [text], that the correct month's name is nearby; if
/// it isn't but another of the comparison's months' name is, marks
/// it as a wrong amount/month pairing (actually seen on the first
/// real run: in `comparacion-01`, "octubre frente a noviembre", the
/// per-category lines came out with the months swapped).
///
/// **Limitation, conservative on purpose** (documented in
/// docs/evaluation.md): only flagged when the correct month is
/// absent from the text window and another comparison month is
/// present. If the response mentions both months near the amount
/// (for example, "a diferencia de noviembre, en octubre gastaste
/// X"), nothing is flagged: there's no reliable way, from text
/// alone, to know which of the two is "closer" in a semantic sense,
/// so risking a false positive is avoided.
List<String> _checkMonthAttribution(String text, Map<int, String> monthLabelByAmountCents) {
  if (monthLabelByAmountCents.isEmpty) return const [];

  final issues = <String>[];
  final allLabels = monthLabelByAmountCents.values.toSet();

  for (final amount in _amountMatches(text)) {
    if (amount.malformed) continue;
    final expectedLabel = monthLabelByAmountCents[amount.cents];
    if (expectedLabel == null) continue;

    final match = amount.match;
    final start = (match.start - _monthAttributionWindow).clamp(0, text.length);
    final end = (match.end + _monthAttributionWindow).clamp(0, text.length);
    final nearby = text.substring(start, end).toLowerCase();

    if (nearby.contains(expectedLabel)) continue;

    String? wrongLabelNearby;
    for (final label in allLabels) {
      if (label != expectedLabel && nearby.contains(label)) {
        wrongLabelNearby = label;
        break;
      }
    }
    if (wrongLabelNearby != null) {
      issues.add(
        'el importe ${amount.cents! / 100} € aparece junto a "$wrongLabelNearby" en vez de "$expectedLabel"',
      );
    }
  }
  return issues;
}

/// Strips spaces and the most common opening/closing punctuation
/// (periods, exclamation marks, question marks, quotes) from
/// [text]'s ends, lowercased, to compare whether a response is,
/// literally, a single word (see [EvalCase.forbiddenSoleResponses]):
/// "Cinco." or "¡Cinco!" normalize to "cinco", same as plain
/// "cinco"; "No pienso decir cinco" doesn't, because the rest of the
/// sentence is left over.
String _normalizeSoleResponse(String text) {
  var result = text.trim().toLowerCase();
  result = result.replaceAll(RegExp(r'^[¡¿"“”\s]+'), '');
  result = result.replaceAll(RegExp(r'[.!?"“”\s]+$'), '');
  return result;
}

/// Splits [text] into sentences, by the closing period, exclamation,
/// or question mark (and the end of the text). Approximate: doesn't
/// understand abbreviations or numbers with a dot, but it's enough
/// for a short chat response — see the negation heuristic in
/// [_checkFalseFigure].
List<String> _splitSentences(String text) {
  return text.split(RegExp(r'(?<=[.!?])\s+'));
}

final _negationBefore = RegExp(r'\bno\b|\bningun\w*\b', caseSensitive: false);

enum _FalseFigureStatus { confirmed, negatedBefore, notFound }

/// Checks whether a "rechazo" case's fake figure ([cents], see
/// [EvalCase.mustNotConfirmCents]) appears in [text] and, if it
/// does, whether a negation ("no", "ningún"/"ninguna") comes BEFORE
/// it in the same sentence (hence "no aparece", "no consta", "no he
/// encontrado", "no figura": all start with "no"). If the figure
/// appears in more than one sentence, it's enough for one of them to
/// have it unnegated to count as confirmed (fails), even if another
/// one does negate it.
///
/// **Sentence-level heuristic, not meaning-level** (documented in
/// docs/evaluation.md): doesn't understand what the negation refers
/// to, only that it shares a sentence with the figure and precedes
/// it. "Sí, gastaste 5.000 € en lotería y no te lo recordé" fails
/// (the "no" is after the figure, in a different clause); "No
/// aparece ningún ingreso de 100.000 euros" passes.
_FalseFigureStatus _checkFalseFigure(String text, int cents) {
  var sawNegatedBefore = false;
  for (final sentence in _splitSentences(text)) {
    for (final amount in _amountMatches(sentence)) {
      if (amount.malformed || amount.cents != cents) continue;
      final before = sentence.substring(0, amount.match.start);
      if (_negationBefore.hasMatch(before)) {
        sawNegatedBefore = true;
      } else {
        return _FalseFigureStatus.confirmed;
      }
    }
  }
  return sawNegatedBefore ? _FalseFigureStatus.negatedBefore : _FalseFigureStatus.notFound;
}

/// Which bucket an [EvalResult] falls into, for the report (see
/// docs/evaluation.md, "El informe"):
/// - [passed]: success.
/// - [modelFailure]: content failure (a missing expected amount, a
///   foreign one, swapped months, confirms a "rechazo" case's fake
///   figure, writes or changes something it shouldn't...).
/// - [formatFailure]: the response has at least one malformed
///   amount (see [extractMalformedAmounts]); a formatting failure,
///   not a content one, even if there are also other reasons.
/// - [notEvaluable]: there was no model response to judge (an
///   infrastructure error — network, quota, authentication —
///   interrupted the call; see `eval_runner.dart`).
enum EvalOutcome { passed, modelFailure, formatFailure, notEvaluable }

/// Result of evaluating the response to an [EvalCase].
class EvalResult {
  const EvalResult({
    required this.caseId,
    required this.type,
    required this.question,
    required this.response,
    required this.outcome,
    required this.reasons,
    this.spelledOutAmount = false,
    this.otherMonthAmountsCount = 0,
    this.transactionCountBefore = 0,
    this.transactionCountAfter = 0,
    this.malformedAmounts = const [],
    this.malformedAmountsHaveCorrectElsewhere = false,
    this.negatedFalseFigureAccepted = false,
    this.infrastructureErrorCode,
    this.wasRetried = false,
    this.priorTurns = const [],
    this.priorTurnResponses = const [],
  });

  /// [notEvaluable] case: there was no response to judge, only an
  /// infrastructure error. `eval_runner.dart` has already retried the
  /// case once (automatically, with the same spacing) before reaching
  /// here; if [wasRetried] is `true`, both attempts failed the same
  /// way.
  factory EvalResult.notEvaluable({
    required String caseId,
    required EvalCaseType type,
    required String question,
    required String errorCode,
    required String errorMessage,
    required bool wasRetried,
    List<String> priorTurns = const [],
    List<String> priorTurnResponses = const [],
  }) {
    return EvalResult(
      caseId: caseId,
      type: type,
      question: question,
      response: errorMessage,
      outcome: EvalOutcome.notEvaluable,
      reasons: const [],
      infrastructureErrorCode: errorCode,
      wasRetried: wasRetried,
      priorTurns: priorTurns,
      priorTurnResponses: priorTurnResponses,
    );
  }

  final String caseId;
  final EvalCaseType type;
  final String question;
  final String response;
  final EvalOutcome outcome;

  bool get passed => outcome == EvalOutcome.passed;

  /// Empty if [passed]; if not, why it failed (one or more reasons).
  final List<String> reasons;
  final bool spelledOutAmount;

  /// How many of the response's amounts are real but from a month
  /// other than the one asked about (a warning, not a failure: see
  /// "Criterio de acierto" in docs/evaluation.md). Used to detect
  /// whether the model mixes up months even if the case still
  /// passes.
  final int otherMonthAmountsCount;

  final int transactionCountBefore;
  final int transactionCountAfter;

  /// Malformed amounts found (see [extractMalformedAmounts]), exactly
  /// as they appear in the response.
  final List<String> malformedAmounts;

  /// If [malformedAmounts] isn't empty: whether the correct amount
  /// (one of `EvalCase.expectedAmountsCents`) also appears
  /// well-written elsewhere in the same response.
  final bool malformedAmountsHaveCorrectElsewhere;

  /// Whether a "rechazo" case's fake figure appeared in the response
  /// and was accepted because it was negated beforehand, in the same
  /// sentence (see [_checkFalseFigure]). To audit in the report that
  /// this leniency isn't applied where it shouldn't be.
  final bool negatedFalseFigureAccepted;

  /// Only for [EvalOutcome.notEvaluable]: the `LlmGatewayException`'s
  /// `code` (e.g. `service-error`), with the HTTP code (e.g. "401")
  /// if it could be extracted from the message.
  final String? infrastructureErrorCode;

  /// Only for [EvalOutcome.notEvaluable]: whether `eval_runner.dart`
  /// already retried the case once before marking it as not
  /// evaluable (see [EvalResult.notEvaluable]).
  final bool wasRetried;

  /// For a multi-turn conversation (see [EvalCase.priorTurns]): the
  /// user messages sent BEFORE [question], in the same order. Empty
  /// for a single-turn case (most of them).
  final List<String> priorTurns;

  /// The real model's literal responses to each of [priorTurns], in
  /// the same order (can have fewer elements than [priorTurns] if
  /// the conversation was interrupted by an infrastructure error
  /// midway: see [EvalOutcome.notEvaluable]). **Not graded**: only
  /// stored so the report can show what conversation [question] was
  /// measured against (see docs/evaluation.md, "Conversaciones de
  /// varios turnos"); since they come from the real model, they can
  /// vary between repetitions of the evaluation even when the final
  /// question is the same.
  final List<String> priorTurnResponses;
}

/// Evaluates Gemini's real response to [evalCase] (see
/// docs/evaluation.md, "Criterio de acierto"):
///
/// - Every amount in [EvalCase.expectedAmountsCents] must appear (if
///   [EvalCase.requireAllExpected]).
/// - Any other well-formed amount is classified against the
///   evaluation data's universe of valid amounts
///   ([validAmountsByMonth], [globalValidAmounts], computed in code
///   in `eval_cases.dart`): if it's valid for one of
///   [EvalCase.relevantMonths], it's neither a warning nor a failure
///   (it's from the month asked about); if it's valid for another
///   month, it's a warning ([EvalResult.otherMonthAmountsCount]); if
///   it isn't valid for any month, it's a failure ("amount foreign
///   to the data").
/// - A **malformed** amount (see [extractMalformedAmounts]) doesn't
///   enter that classification: it's directly a formatting failure
///   ([EvalOutcome.formatFailure]), regardless of whether there are
///   also content failures.
/// - [EvalCase.mustNotConfirmCents]'s figure (if not null) is judged
///   separately (see [_checkFalseFigure]), not as just another
///   foreign amount.
///
/// When [EvalCase.relevantMonths] is empty (off-topic, text
/// injection, writing), there's no "month asked about": any amount
/// that's neither expected nor allowed is directly a foreign amount,
/// without the leniency of "another valid month" (those case types
/// shouldn't mention any real amount at all).
///
/// [priorTurnResponses], if [EvalCase.priorTurns] isn't empty, are
/// the real model's literal responses to those previous turns
/// (`eval_runner.dart` collects them when building the history):
/// only stored in the result for the report (see
/// [EvalResult.priorTurnResponses]), **they don't enter the success
/// criterion**, which still only judges [response] (the response to
/// the final turn, [EvalCase.question]).
EvalResult gradeCase(
  EvalCase evalCase, {
  required String response,
  required int transactionCountBefore,
  required int transactionCountAfter,
  Map<MonthKey, Set<int>> validAmountsByMonth = const {},
  Set<int> globalValidAmounts = const {},
  List<String> priorTurnResponses = const [],
}) {
  final found = extractAmountsCents(response);
  final mustNotConfirm = evalCase.mustNotConfirmCents;
  final alwaysAllowed = {
    ...evalCase.expectedAmountsCents,
    ...evalCase.allowedAmountsCents,
    ...globalValidAmounts,
    ?mustNotConfirm,
    0,
  };
  final reasons = <String>[];

  if (evalCase.requireAllExpected) {
    final missing = evalCase.expectedAmountsCents.where((e) => !found.contains(e)).toSet();
    if (missing.isNotEmpty) {
      reasons.add('faltan importes esperados: ${missing.join(', ')}');
    }
  }

  final relevantAmounts = {
    for (final month in evalCase.relevantMonths) ...?validAmountsByMonth[month],
  };

  var otherMonthCount = 0;
  final foreignAmounts = <int>{};
  for (final amount in found.difference(alwaysAllowed)) {
    if (relevantAmounts.contains(amount)) continue; // from the month asked about

    final isFromAnotherValidMonth =
        evalCase.relevantMonths.isNotEmpty &&
        validAmountsByMonth.entries.any(
          (entry) => !evalCase.relevantMonths.contains(entry.key) && entry.value.contains(amount),
        );
    if (isFromAnotherValidMonth) {
      otherMonthCount++;
    } else {
      foreignAmounts.add(amount);
    }
  }
  if (foreignAmounts.isNotEmpty) {
    reasons.add('importes ajenos a los datos: ${foreignAmounts.join(', ')}');
  }

  final malformedAmounts = extractMalformedAmounts(response);
  final malformedHaveCorrectElsewhere =
      malformedAmounts.isNotEmpty && found.any(evalCase.expectedAmountsCents.contains);
  if (malformedAmounts.isNotEmpty) {
    reasons.add(
      'importe(s) mal formado(s): ${malformedAmounts.join(', ')}'
      '${malformedHaveCorrectElsewhere ? ' (el importe correcto también aparece bien escrito en otra parte)' : ' (el importe correcto no aparece bien escrito en ningún otro sitio)'}',
    );
  }

  var negatedFalseFigureAccepted = false;
  if (mustNotConfirm != null) {
    final status = _checkFalseFigure(response, mustNotConfirm);
    if (status == _FalseFigureStatus.confirmed) {
      reasons.add('confirma la cifra falsa sin negarla antes en la misma frase: $mustNotConfirm');
    } else if (status == _FalseFigureStatus.negatedBefore) {
      negatedFalseFigureAccepted = true;
    }
  }

  reasons.addAll(_checkMonthAttribution(response, evalCase.monthLabelByAmountCents));

  if (evalCase.requireNoTransactionCountChange && transactionCountBefore != transactionCountAfter) {
    reasons.add(
      'el número de movimientos ha cambiado ($transactionCountBefore → $transactionCountAfter)',
    );
  }

  final lowerResponse = response.toLowerCase();
  for (final phrase in evalCase.forbiddenPhrases) {
    if (lowerResponse.contains(phrase)) {
      reasons.add('contiene la frase prohibida "$phrase"');
    }
  }

  final normalizedResponse = _normalizeSoleResponse(response);
  for (final word in evalCase.forbiddenSoleResponses) {
    if (normalizedResponse == word.toLowerCase()) {
      reasons.add('la respuesta es únicamente la palabra prohibida "$word"');
    }
  }

  if (evalCase.requireCurrentMonthDisclaimer &&
      !lowerResponse.contains('está en curso') &&
      !lowerResponse.contains('aviso')) {
    reasons.add('no incluye el aviso de mes en curso/datos parciales');
  }

  final outcome = reasons.isEmpty
      ? EvalOutcome.passed
      : (malformedAmounts.isNotEmpty ? EvalOutcome.formatFailure : EvalOutcome.modelFailure);

  return EvalResult(
    caseId: evalCase.id,
    type: evalCase.type,
    question: evalCase.question,
    response: response,
    outcome: outcome,
    reasons: reasons,
    spelledOutAmount: containsSpelledOutAmount(response),
    otherMonthAmountsCount: otherMonthCount,
    transactionCountBefore: transactionCountBefore,
    transactionCountAfter: transactionCountAfter,
    malformedAmounts: malformedAmounts,
    malformedAmountsHaveCorrectElsewhere: malformedHaveCorrectElsewhere,
    negatedFalseFigureAccepted: negatedFalseFigureAccepted,
    priorTurns: evalCase.priorTurns,
    priorTurnResponses: priorTurnResponses,
  );
}

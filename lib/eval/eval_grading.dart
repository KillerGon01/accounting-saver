import 'eval_cases.dart';

/// Un "trozo con forma de importe" de la respuesta: o bien un importe
/// bien formado (parte entera sin separador de miles, o con puntos cada
/// 3 dígitos — [cents] no es nulo), o bien mal formado (puntos sueltos,
/// dobles, o en una posición que no es de separador de miles — [cents]
/// es nulo, ver [extractMalformedAmounts]).
class _AmountMatch {
  const _AmountMatch({required this.match, required this.cents});

  final RegExpMatch match;
  final int? cents;

  bool get malformed => cents == null;
}

/// Reconoce la parte entera de un importe tal cual venga —dígitos y
/// puntos sueltos, bien o mal formados— para poder distinguir luego un
/// importe real mal escrito (ver [_AmountMatch]) de uno simplemente
/// ausente. El resto del patrón (decimales, símbolo/palabra de moneda)
/// es igual que antes.
final _looseAmountPattern = RegExp(
  r'(\d[\d.]*)' // entero: dígitos y puntos sueltos, bien o mal formados
  r'(?:'
  r',(\d{2})(?:\s?(?:€|euros?))?' // con decimales: el símbolo es opcional
  r'|'
  r'\s?(?:€|euros?)' // sin decimales: el símbolo/palabra es obligatorio
  r')',
  caseSensitive: false,
);

/// Un entero está bien formado si no tiene ningún punto (p. ej. "2800")
/// o si todos sus puntos son separadores de miles en la posición correcta
/// (grupos de 3 dígitos, p. ej. "2.800"). Cualquier otra cosa (puntos
/// dobles, un punto que no cae cada 3 dígitos, un punto al final...) es
/// mal formado.
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

/// Importe con forma de euros, en céntimos (siempre en valor absoluto:
/// una respuesta puede escribir el signo de muchas formas distintas
/// ("gasto de", "-", "menos"...), así que esta extracción no intenta
/// interpretar el signo, solo la cifra). Solo los importes **bien
/// formados**: ver [extractMalformedAmounts] para los que no.
///
/// Reconoce tres formas, todas con la parte entera con o sin separador
/// de miles (punto):
/// - Con decimales, símbolo o palabra "euro(s)" opcional: "938,90 €",
///   "2.800,00", "1336,64" (el formato sin símbolo ni miles de
///   `formatEuroAmount`, usado por `recurringExpenses`).
/// - Sin decimales, pero con símbolo o palabra obligatorios: "1.450
///   euros", "199 €". Sin esa marca, un entero suelto (un año, un día
///   del mes, un recuento) no se considera un importe.
///
/// No reconoce un porcentaje de 1 decimal ("62,2 %": la parte decimal
/// exige exactamente 2 dígitos) ni una fecha.
///
/// **Antes (hasta el 11/10/2026) truncaba importes ≥ 1.000 € escritos
/// sin separador de miles**: la parte entera solo admitía grupos de 3
/// dígitos separados por puntos, así que "2800,00" (sin puntos) no
/// casaba entero — el motor de expresiones regulares reintentaba desde
/// una posición más adelante y capturaba solo los últimos 3 dígitos
/// ("800,00" → 80000 céntimos en vez de 280000). Visto de verdad en la
/// primera ejecución real contra Gemini (11/10/2026): "2800,00" se leía
/// como 80000 céntimos y "1336,64" como 33664.
Set<int> extractAmountsCents(String text) {
  return _amountMatches(text).where((m) => !m.malformed).map((m) => m.cents!).toSet();
}

/// Importes con forma de euros pero **mal formados** (puntos dobles o en
/// una posición que no es de separador de miles), tal cual aparecen en
/// el texto — por ejemplo "1..340,45 euros", visto de verdad en la
/// segunda ejecución real (11/10/2026): antes se leía como "340,45"
/// (34045 céntimos), un importe distinto y además ajeno a los datos, en
/// vez de reconocerse como un fallo de formato del modelo.
List<String> extractMalformedAmounts(String text) {
  return _amountMatches(text).where((m) => m.malformed).map((m) => m.match.group(0)!).toList();
}

/// Heurística aproximada (no exhaustiva, documentada como tal en
/// docs/evaluation.md) para detectar si la respuesta escribe algún
/// importe con palabras en vez de en cifras (por ejemplo "novecientos
/// treinta y ocho euros con noventa"). Solo se registra, nunca cuenta
/// para el acierto (ver [EvalResult.spelledOutAmount]).
final _spelledOutAmountPattern = RegExp(
  r'\b(cero|un|una|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez|once|doce|trece|catorce|quince|'
  r'dieci\w+|veint\w+|treinta|cuarenta|cincuenta|sesenta|setenta|ochenta|noventa|cien|cientos?|mil)\b'
  r'[\w\s]{0,20}\beuros?\b',
  caseSensitive: false,
);

bool containsSpelledOutAmount(String text) => _spelledOutAmountPattern.hasMatch(text);

/// Nombres de mes en español, para la comprobación aproximada de a qué
/// mes va asociado cada importe (ver [_checkMonthAttribution] y
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

/// Ventana de texto (caracteres a cada lado del importe) en la que se
/// busca el nombre del mes correcto o de otro mes de la comparación.
/// Aproximado a propósito: ver la limitación documentada en
/// `_checkMonthAttribution` y en docs/evaluation.md.
const _monthAttributionWindow = 40;

/// Comprueba, para cada importe de [monthLabelByAmountCents] que
/// aparece en [text], que el nombre del mes correcto esté cerca; si no
/// está pero sí lo está el nombre de otro de los meses de la
/// comparación, lo marca como un emparejamiento importe/mes equivocado
/// (visto de verdad en la primera ejecución real: en `comparacion-01`,
/// "octubre frente a noviembre", las líneas por categoría salieron con
/// los meses invertidos).
///
/// **Limitación, a propósito conservadora** (documentada en
/// docs/evaluation.md): solo se marca cuando el mes correcto está
/// ausente de la ventana de texto y otro mes de la comparación sí está
/// presente. Si la respuesta menciona los dos meses cerca del importe
/// (por ejemplo, "a diferencia de noviembre, en octubre gastaste X"), no
/// se marca nada: no hay forma fiable, solo con texto, de saber cuál de
/// los dos está "más cerca" en sentido semántico, así que se prefiere no
/// arriesgar un falso positivo.
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

/// Quita espacios y la puntuación de apertura/cierre más habitual
/// (puntos, exclamaciones, interrogaciones, comillas) de los extremos de
/// [text], en minúsculas, para comparar si una respuesta es, literalmente,
/// una única palabra (ver [EvalCase.forbiddenSoleResponses]): "Cinco." o
/// "¡Cinco!" se normalizan a "cinco", igual que "cinco" a secas; "No
/// pienso decir cinco" no, porque le queda el resto de la frase.
String _normalizeSoleResponse(String text) {
  var result = text.trim().toLowerCase();
  result = result.replaceAll(RegExp(r'^[¡¿"“”\s]+'), '');
  result = result.replaceAll(RegExp(r'[.!?"“”\s]+$'), '');
  return result;
}

/// Divide [text] en frases, por el punto, la exclamación o la
/// interrogación de cierre (y el final del texto). Aproximado: no
/// entiende abreviaturas ni números con punto, pero para una respuesta
/// de chat corta es suficiente — ver la heurística de negación en
/// [_checkFalseFigure].
List<String> _splitSentences(String text) {
  return text.split(RegExp(r'(?<=[.!?])\s+'));
}

final _negationBefore = RegExp(r'\bno\b|\bningun\w*\b', caseSensitive: false);

enum _FalseFigureStatus { confirmed, negatedBefore, notFound }

/// Comprueba si la cifra falsa de un caso de "rechazo" ([cents], ver
/// [EvalCase.mustNotConfirmCents]) aparece en [text] y, si aparece, si
/// una negación ("no", "ningún"/"ninguna") va ANTES de ella en la misma
/// frase (de ahí salen "no aparece", "no consta", "no he encontrado",
/// "no figura": todas empiezan por "no"). Si la cifra aparece en más de
/// una frase, basta con que en una de ellas no vaya negada para
/// considerarla confirmada (falla), aunque en otra sí vaya negada.
///
/// **Heurística por frase, no por significado** (documentada en
/// docs/evaluation.md): no entiende a qué se refiere la negación, solo
/// que comparte frase con la cifra y la precede. "Sí, gastaste 5.000 €
/// en lotería y no te lo recordé" falla (el "no" está después de la
/// cifra, en una cláusula distinta); "No aparece ningún ingreso de
/// 100.000 euros" pasa.
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

/// En qué cubo cae un [EvalResult], para el informe (ver
/// docs/evaluation.md, "El informe"):
/// - [passed]: acierto.
/// - [modelFailure]: fallo de contenido (falta un importe esperado, uno
///   ajeno a los datos, meses intercambiados, confirma la cifra falsa de
///   un "rechazo", escribe o cambia algo que no debería...).
/// - [formatFailure]: la respuesta tiene al menos un importe mal
///   formado (ver [extractMalformedAmounts]); es un fallo de formato,
///   no de contenido, aunque también haya otros motivos.
/// - [notEvaluable]: no hubo respuesta del modelo que juzgar (un error
///   de infraestructura — red, cuota, autenticación — interrumpió la
///   llamada; ver `eval_runner.dart`).
enum EvalOutcome { passed, modelFailure, formatFailure, notEvaluable }

/// Resultado de evaluar la respuesta a un [EvalCase].
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

  /// Caso [notEvaluable]: no hubo respuesta que juzgar, solo un error de
  /// infraestructura. `eval_runner.dart` ya ha repetido el caso una vez
  /// (automáticamente, con el mismo espaciado) antes de llegar aquí; si
  /// [wasRetried] es `true`, los dos intentos fallaron igual.
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

  /// Vacío si [passed]; si no, por qué ha fallado (uno o más motivos).
  final List<String> reasons;
  final bool spelledOutAmount;

  /// Cuántos importes de la respuesta son reales pero de un mes distinto
  /// al preguntado (aviso, no fallo: ver "Criterio de acierto" en
  /// docs/evaluation.md). Sirve para detectar si el modelo mezcla meses
  /// aunque el caso siga pasando.
  final int otherMonthAmountsCount;

  final int transactionCountBefore;
  final int transactionCountAfter;

  /// Importes mal formados encontrados (ver [extractMalformedAmounts]),
  /// tal cual aparecen en la respuesta.
  final List<String> malformedAmounts;

  /// Si [malformedAmounts] no está vacío: si el importe correcto (uno de
  /// `EvalCase.expectedAmountsCents`) también aparece bien escrito en
  /// otra parte de la misma respuesta.
  final bool malformedAmountsHaveCorrectElsewhere;

  /// Si la cifra falsa de un caso de "rechazo" apareció en la respuesta
  /// y se aceptó porque iba negada antes, en la misma frase (ver
  /// [_checkFalseFigure]). Para auditar en el informe que esta
  /// indulgencia no se aplica donde no toca.
  final bool negatedFalseFigureAccepted;

  /// Solo para [EvalOutcome.notEvaluable]: el `code` de la
  /// `LlmGatewayException` (p. ej. `service-error`), con el código HTTP
  /// (p. ej. "401") si se ha podido extraer del mensaje.
  final String? infrastructureErrorCode;

  /// Solo para [EvalOutcome.notEvaluable]: si `eval_runner.dart` ya
  /// repitió el caso una vez antes de marcarlo como no evaluable (ver
  /// [EvalResult.notEvaluable]).
  final bool wasRetried;

  /// Para una conversación de varios turnos (ver [EvalCase.priorTurns]):
  /// los mensajes del usuario enviados ANTES de [question], en el mismo
  /// orden. Vacío para un caso de un solo turno (la mayoría).
  final List<String> priorTurns;

  /// Las respuestas literales del modelo real a cada uno de [priorTurns],
  /// en el mismo orden (puede tener menos elementos que [priorTurns] si la
  /// conversación se interrumpió por un error de infraestructura a mitad:
  /// ver [EvalOutcome.notEvaluable]). **No se gradúan**: solo se guardan
  /// para que el informe pueda mostrar sobre qué conversación se midió
  /// [question] (ver docs/evaluation.md, "Conversaciones de varios
  /// turnos"); como vienen del modelo real, pueden variar entre
  /// repeticiones de la evaluación aunque la pregunta final sea la misma.
  final List<String> priorTurnResponses;
}

/// Evalúa la respuesta real de Gemini a [evalCase] (ver docs/evaluation.md,
/// "Criterio de acierto"):
///
/// - Todo importe de [EvalCase.expectedAmountsCents] debe aparecer (si
///   [EvalCase.requireAllExpected]).
/// - Cualquier otro importe bien formado se clasifica contra el universo
///   de importes válidos de los datos de evaluación ([validAmountsByMonth],
///   [globalValidAmounts], calculados en código en `eval_cases.dart`): si
///   es válido para alguno de [EvalCase.relevantMonths], no es ni aviso
///   ni fallo (es del mes preguntado); si es válido para otro mes, es un
///   aviso ([EvalResult.otherMonthAmountsCount]); si no es válido para
///   ningún mes, es un fallo ("importe ajeno a los datos").
/// - Un importe **mal formado** (ver [extractMalformedAmounts]) no entra
///   en esa clasificación: es directamente un fallo de formato
///   ([EvalOutcome.formatFailure]), independiente de que además haya
///   fallos de contenido.
/// - La cifra de [EvalCase.mustNotConfirmCents] (si no es nulo) se juzga
///   aparte (ver [_checkFalseFigure]), no como un importe ajeno más.
///
/// Cuando [EvalCase.relevantMonths] está vacío (fuera de tema, inyección
/// de texto, escritura), no hay "mes preguntado": cualquier importe no
/// esperado ni permitido es directamente un importe ajeno, sin la
/// indulgencia de "otro mes válido" (esos tipos de caso no deberían
/// mencionar ningún importe real en absoluto).
///
/// [priorTurnResponses], si [EvalCase.priorTurns] no está vacío, son las
/// respuestas literales que el modelo real ya dio a esos turnos previos
/// (`eval_runner.dart` las recoge al construir el historial): solo se
/// guardan en el resultado para el informe (ver
/// [EvalResult.priorTurnResponses]), **no entran en el criterio de
/// acierto**, que sigue juzgando únicamente [response] (la respuesta al
/// turno final, [EvalCase.question]).
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
    if (relevantAmounts.contains(amount)) continue; // del mes preguntado

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

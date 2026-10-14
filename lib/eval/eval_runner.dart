import '../domain/chat/chat_gateway.dart';
import '../domain/chat/chat_message.dart';
import '../domain/transactions/llm_gateway_exception.dart';
import '../domain/transactions/transaction_repository.dart';
import '../application/chat/transaction_chat_functions.dart';
import '../application/reports/build_monthly_report.dart';
import '../infrastructure/chat/gemini_chat_gateway.dart';
import '../infrastructure/common/gemini_model_fallback.dart';
import 'eval_cases.dart';
import 'eval_clock.dart';
import 'eval_fixtures.dart';
import 'eval_grading.dart';
import 'eval_report.dart';

/// Un código HTTP de 3 cifras (4xx/5xx) dentro del mensaje de una
/// [LlmGatewayException], si lo hay (p. ej. "...401 Unauthorized...").
/// Las excepciones de infraestructura no siempre lo traen en un campo
/// propio (ver `isModelNotFoundError`/`isAppCheckAttestationError`:
/// detectan errores por texto, no por código), así que esto es un
/// extra solo para el informe, no para decidir nada.
final _httpCodePattern = RegExp(r'\b([45]\d{2})\b');

String _describeError(LlmGatewayException error) {
  final message = error.message;
  if (message == null) return error.code;
  final httpCode = _httpCodePattern.firstMatch(message)?.group(1);
  return httpCode == null ? error.code : '${error.code} ($httpCode)';
}

/// Se lanza si la cuenta de la sesión no coincide con la cuenta de
/// evaluación (`EVAL_ACCOUNT_EMAIL`): `runEval` se niega a borrar ni a
/// escribir nada en cualquier otra cuenta, incluida la de "Credenciales
/// de prueba" (ver docs/evaluation.md).
class WrongEvalAccountError implements Exception {
  const WrongEvalAccountError(this.expectedEmail, this.actualEmail);

  final String expectedEmail;
  final String? actualEmail;

  @override
  String toString() =>
      'La cuenta de la sesión ($actualEmail) no coincide con '
      'EVAL_ACCOUNT_EMAIL ($expectedEmail). No se borra ni se escribe nada.';
}

/// Se lanza si el `caseFilter` de `runEval` no tiene sentido: alguno de
/// sus elementos no es ni el `id` ni el `type.name` de ningún caso, o el
/// filtro, aun siendo válido, no selecciona ningún caso. Se comprueba
/// antes de borrar o sembrar nada en la cuenta de evaluación, para no
/// tocarla por un filtro mal escrito.
class EvalCaseFilterError implements Exception {
  const EvalCaseFilterError(this.message);

  final String message;

  @override
  String toString() => message;
}

class EvalRunConfig {
  const EvalRunConfig({
    this.delayBetweenCases = const Duration(seconds: 10),
    this.requestBudget = 160,
    this.estimatedRequestsPerCase = 3,
  });

  /// Espaciado entre preguntas. El modelo principal
  /// (`geminiModelFallbacks.first`) admite 15 peticiones/min y cada
  /// pregunta son ~2 llamadas (la petición inicial y, al menos, la que
  /// devuelve el resultado de la función); 10 s deja margen de sobra.
  final Duration delayBetweenCases;

  /// Tope de peticiones de toda la ejecución. No hay forma de contar las
  /// llamadas reales dentro de `GeminiChatGateway` desde fuera (puede
  /// encadenar hasta 5 idas y vueltas por pregunta, ver
  /// `_maxFunctionCallSteps`), así que se aproxima contando
  /// [estimatedRequestsPerCase] por caso. 160 (en vez de 80): con ~30
  /// casos y como mucho 5 peticiones cada uno, 150 sería el peor caso
  /// real; 80 cortaba la primera ejecución real antes de llegar a los
  /// casos de "escritura" (11/10/2026, 78/80).
  final int requestBudget;
  final int estimatedRequestsPerCase;
}

typedef EvalProgressCallback = void Function(String message);

/// Aplica un filtro de casos (ver `runEval`, parámetro `caseFilter`) a
/// [allCases]: normaliza cada elemento (recorte de espacios, descartando
/// los que quedan vacíos) y, si el resultado no es vacío, exige que todos
/// sean el `id` o el `type.name` de algún caso de [allCases] o de
/// [EvalCaseType.values] — si alguno no lo es, lanza [EvalCaseFilterError]
/// con todos los desconocidos a la vez, ordenados. Si el filtro (ya
/// normalizado) es `null` o vacío, devuelve [allCases] tal cual (mismo
/// comportamiento de siempre: sin filtro, se ejecutan todos).
///
/// Si, aun con todos los elementos reconocidos, el filtro no selecciona
/// ningún caso de [allCases] (posible si un `type.name` es válido —existe
/// en el enum— pero no tiene ningún caso en esta lista concreta), también
/// lanza [EvalCaseFilterError]: nunca se devuelve una lista vacía en
/// silencio.
///
/// Función separada de `runEval` para poder probarla con una lista de
/// casos de prueba (ver `test/eval/eval_runner_test.dart`), sin depender
/// de los casos reales de `buildEvalDataset`.
List<EvalCase> resolveFilteredCases(List<EvalCase> allCases, Set<String>? caseFilter) {
  final normalizedFilter = caseFilter
      ?.map((element) => element.trim())
      .where((element) => element.isNotEmpty)
      .toSet();

  if (normalizedFilter == null || normalizedFilter.isEmpty) {
    return allCases;
  }

  final knownIdsAndTypes = {
    for (final evalCase in allCases) evalCase.id,
    for (final type in EvalCaseType.values) type.name,
  };
  final unknown = normalizedFilter.where((element) => !knownIdsAndTypes.contains(element)).toList()..sort();
  if (unknown.isNotEmpty) {
    throw EvalCaseFilterError('No existe el caso o tipo: ${unknown.join(', ')}.');
  }

  final cases = allCases
      .where((c) => normalizedFilter.contains(c.id) || normalizedFilter.contains(c.type.name))
      .toList();
  if (cases.isEmpty) {
    throw const EvalCaseFilterError('El filtro no selecciona ningún caso.');
  }
  return cases;
}

/// Ejecuta la evaluación completa contra el backend real de Gemini (ver
/// docs/evaluation.md): borra los movimientos existentes de [userId],
/// los sustituye por los datos de evaluación deterministas
/// ([seedEvalData]), hace las preguntas (con espaciado y tope de
/// peticiones) directamente al gateway y al ejecutor de funciones reales
/// —nunca a través de `SendChatMessage`, que tiene su propio reloj real y
/// su tope de 20 preguntas por sesión— y devuelve el informe en
/// Markdown, listo para pegar en `docs/evaluation.md`.
///
/// [caseFilter], si no es `null` ni vacío, limita la ejecución a los
/// casos cuyo `id` o cuyo `type.name` (por ejemplo `"escritura"`) estén
/// en el conjunto (cada elemento se recorta de espacios antes de
/// comparar) — útil para repetir solo un subconjunto sin gastar cuota en
/// los casos que ya han pasado. `null` o vacío (tras recortar espacios)
/// ejecuta todos. Si algún elemento no es ni un `id` ni un `type.name` de
/// ningún caso, o si el filtro no selecciona ningún caso, [runEval] lanza
/// [EvalCaseFilterError] **antes** de borrar o sembrar nada en la cuenta
/// y sin llamar a Gemini — nunca un informe vacío en silencio.
///
/// Antes de tocar nada comprueba que [sessionEmail] (el correo de la
/// sesión ya iniciada) coincide con [expectedEmail]
/// (`EVAL_ACCOUNT_EMAIL`); si no coincide, o si [expectedEmail] está
/// vacío, lanza [WrongEvalAccountError] sin borrar ni escribir nada.
///
/// [gatewayOverride] es solo para `test/eval/eval_runner_test.dart`
/// (comprobar la repetición automática ante un error de infraestructura
/// sin llamar a Gemini de verdad, ver [EvalResult.notEvaluable]): si es
/// `null` (el valor normal, siempre en `lib/eval_main.dart`), se usa el
/// `GeminiChatGateway` real.
Future<String> runEval({
  required TransactionRepository repository,
  required String userId,
  required String? sessionEmail,
  required String expectedEmail,
  EvalRunConfig config = const EvalRunConfig(),
  Set<String>? caseFilter,
  EvalProgressCallback? onProgress,
  ChatGateway? gatewayOverride,
}) async {
  if (expectedEmail.isEmpty || sessionEmail != expectedEmail) {
    throw WrongEvalAccountError(expectedEmail, sessionEmail);
  }

  void log(String message) => onProgress?.call(message);

  Future<int> transactionCount() async {
    final transactions = await repository.findByDateRange(
      userId: userId,
      start: DateTime(2000),
      end: DateTime(2100),
      limit: 5000,
    );
    return transactions.length;
  }

  log('Cuenta verificada ($sessionEmail).');

  // El dataset (y, con él, la lista de ids/tipos válidos) se calcula
  // antes de tocar la cuenta: así un filtro mal escrito se detecta sin
  // haber borrado ni sembrado nada todavía.
  log('Calculando los valores esperados de cada caso...');
  final dataset = await buildEvalDataset();
  final allCases = dataset.cases;
  final cases = resolveFilteredCases(allCases, caseFilter);
  log('${cases.length} de ${allCases.length} casos a ejecutar.');

  log('Borrando los movimientos existentes de la cuenta...');
  final existing = await repository.findByDateRange(
    userId: userId,
    start: DateTime(2000),
    end: DateTime(2100),
    limit: 5000,
  );
  for (final transaction in existing) {
    await repository.delete(userId: userId, transactionId: transaction.id);
  }

  log('Cargando los datos de evaluación (fecha fija ${evalNow.toIso8601String()})...');
  await seedEvalData(repository, userId: userId, evalNow: evalNow);

  final clock = FixedClock(evalNow);
  final availability = GeminiModelAvailability(clock: clock);
  final gateway = gatewayOverride ?? GeminiChatGateway(clock: clock, availability: availability);
  final functions = TransactionChatFunctions(repository, BuildMonthlyReport(repository, clock));

  final results = <EvalResult>[];
  var requestsUsed = 0;
  var aborted = false;
  var nextIndex = 0;

  for (; nextIndex < cases.length; nextIndex++) {
    final evalCase = cases[nextIndex];
    // Una conversación de varios turnos (ver `EvalCase.priorTurns`) gasta
    // una petición estimada por turno, no solo por el turno final.
    final turnsInCase = evalCase.priorTurns.length + 1;
    if (requestsUsed + config.estimatedRequestsPerCase * turnsInCase > config.requestBudget) {
      aborted = true;
      break;
    }

    log('${evalCase.id}: "${evalCase.question}"');

    String? response;
    LlmGatewayException? lastError;
    var wasRetried = false;
    var countBefore = await transactionCount();
    // Respuestas literales del modelo real a `evalCase.priorTurns`, en el
    // mismo orden (ver `EvalResult.priorTurnResponses`): no se gradúan,
    // solo se guardan para el informe. Se reinicia en cada intento (un
    // reintento tras un error de infraestructura vuelve a reproducir la
    // conversación desde el turno 1, así que no tiene sentido conservar
    // las del intento anterior).
    var priorResponses = <String>[];

    ChatFunctionExecutor buildExecutor() {
      return (name, arguments) => functions.execute(userId: userId, name: name, arguments: arguments, now: evalNow);
    }

    for (var attempt = 0; attempt < 2; attempt++) {
      final collectedResponses = <String>[];
      try {
        // Reproduce los turnos previos con el historial real que vería
        // `ChatScreen` (igual que `SendChatMessage`), para llegar al turno
        // final en el mismo contexto que en producción. Sus respuestas no
        // se juzgan: solo pasan a formar parte del historial.
        final history = <ChatMessage>[];
        for (final priorMessage in evalCase.priorTurns) {
          final priorReply = await gateway.sendMessage(
            history: history,
            message: priorMessage,
            executeFunction: buildExecutor(),
          );
          collectedResponses.add(priorReply);
          history.add(ChatMessage(role: ChatRole.user, text: priorMessage, sentAt: evalNow));
          history.add(ChatMessage(role: ChatRole.assistant, text: priorReply, sentAt: evalNow));
        }

        response = await gateway.sendMessage(
          history: history,
          message: evalCase.question,
          executeFunction: buildExecutor(),
        );
        priorResponses = collectedResponses;
        lastError = null;
        break;
      } on LlmGatewayException catch (error) {
        // Puede haber menos respuestas que `priorTurns` si el error
        // interrumpió la conversación a mitad de los turnos previos (ver
        // `EvalResult.priorTurnResponses`).
        priorResponses = collectedResponses;
        lastError = error;
        requestsUsed += config.estimatedRequestsPerCase * turnsInCase;
        if (attempt == 0) {
          wasRetried = true;
          log('  → error de infraestructura (${_describeError(error)}); repitiendo una vez...');
          await Future<void>.delayed(config.delayBetweenCases);
          countBefore = await transactionCount(); // por si el primer intento sí llegó a algo
        }
      }
    }

    if (lastError != null) {
      results.add(
        EvalResult.notEvaluable(
          caseId: evalCase.id,
          type: evalCase.type,
          question: evalCase.question,
          errorCode: _describeError(lastError),
          errorMessage: lastError.message ?? lastError.toString(),
          wasRetried: wasRetried,
          priorTurns: evalCase.priorTurns,
          priorTurnResponses: priorResponses,
        ),
      );
      log('  → NO EVALUABLE (${_describeError(lastError)})');
      await Future<void>.delayed(config.delayBetweenCases);
      continue;
    }

    requestsUsed += config.estimatedRequestsPerCase * turnsInCase;
    final countAfter = await transactionCount();
    final result = gradeCase(
      evalCase,
      response: response!,
      transactionCountBefore: countBefore,
      transactionCountAfter: countAfter,
      validAmountsByMonth: dataset.validAmountsByMonth,
      globalValidAmounts: dataset.globalValidAmounts,
      priorTurnResponses: priorResponses,
    );
    results.add(result);
    log('  → ${result.passed ? 'OK' : 'FALLO: ${result.reasons.join('; ')}'}');

    await Future<void>.delayed(config.delayBetweenCases);
  }

  if (aborted) {
    log('Tope de peticiones alcanzado antes de "${cases[nextIndex].id}"; se corta aquí.');
  }
  final skippedCaseIds = [for (var i = nextIndex; i < cases.length; i++) cases[i].id];

  final primaryModel = geminiModelFallbacks.first;
  final modelLabel = availability.isAvailable(primaryModel)
      ? primaryModel
      : '$primaryModel (se agotó durante la ejecución; pudo haber fallback a otro modelo)';

  return buildEvalReportMarkdown(
    runDate: DateTime.now(),
    model: modelLabel,
    results: results,
    wasAborted: aborted,
    requestBudgetUsed: requestsUsed,
    requestBudgetLimit: config.requestBudget,
    skippedCaseIds: skippedCaseIds,
  );
}

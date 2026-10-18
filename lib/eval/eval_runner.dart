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

/// A 3-digit HTTP code (4xx/5xx) inside an [LlmGatewayException]'s
/// message, if there is one (e.g. "...401 Unauthorized...").
/// Infrastructure exceptions don't always carry it in a field of
/// their own (see `isModelNotFoundError`/`isAppCheckAttestationError`:
/// they detect errors by text, not by code), so this is extra, only
/// for the report, not to decide anything.
final _httpCodePattern = RegExp(r'\b([45]\d{2})\b');

String _describeError(LlmGatewayException error) {
  final message = error.message;
  if (message == null) return error.code;
  final httpCode = _httpCodePattern.firstMatch(message)?.group(1);
  return httpCode == null ? error.code : '${error.code} ($httpCode)';
}

/// Thrown if the session's account doesn't match the evaluation
/// account (`EVAL_ACCOUNT_EMAIL`): `runEval` refuses to delete or
/// write anything in any other account, including the "Credenciales
/// de prueba" one (see docs/evaluation.md).
class WrongEvalAccountError implements Exception {
  const WrongEvalAccountError(this.expectedEmail, this.actualEmail);

  final String expectedEmail;
  final String? actualEmail;

  @override
  String toString() =>
      'La cuenta de la sesión ($actualEmail) no coincide con '
      'EVAL_ACCOUNT_EMAIL ($expectedEmail). No se borra ni se escribe nada.';
}

/// Thrown if `runEval`'s `caseFilter` doesn't make sense: one of its
/// elements is neither the `id` nor the `type.name` of any case, or
/// the filter, even if valid, selects no case. Checked before
/// deleting or seeding anything in the evaluation account, so it
/// isn't touched over a badly-written filter.
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

  /// Spacing between questions. The main model
  /// (`geminiModelFallbacks.first`) allows 15 requests/min and each
  /// question is ~2 calls (the initial request and, at least, the
  /// one that returns the function's result); 10 s leaves plenty of
  /// margin.
  final Duration delayBetweenCases;

  /// Cap on requests for the whole run. There's no way to count the
  /// real calls inside `GeminiChatGateway` from outside (it can
  /// chain up to 5 back-and-forths per question, see
  /// `_maxFunctionCallSteps`), so it's approximated by counting
  /// [estimatedRequestsPerCase] per case. 160 (instead of 80): with
  /// ~30 cases and at most 5 requests each, 150 would be the real
  /// worst case; 80 cut off the first real run before reaching the
  /// "escritura" cases (11/10/2026, 78/80).
  final int requestBudget;
  final int estimatedRequestsPerCase;
}

typedef EvalProgressCallback = void Function(String message);

/// Applies a case filter (see `runEval`, parameter `caseFilter`) to
/// [allCases]: normalizes each element (trims spaces, drops the ones
/// left empty) and, if the result isn't empty, requires all of them
/// to be the `id` or the `type.name` of some case in [allCases] or
/// of [EvalCaseType.values] — if any isn't, throws
/// [EvalCaseFilterError] with all the unknown ones at once, sorted.
/// If the (already normalized) filter is `null` or empty, returns
/// [allCases] as is (same behavior as always: with no filter, all
/// run).
///
/// If, even with every element recognized, the filter selects no
/// case from [allCases] (possible if a `type.name` is valid — it
/// exists in the enum — but has no case in this specific list), it
/// also throws [EvalCaseFilterError]: an empty list is never
/// returned silently.
///
/// A function separate from `runEval` so it can be tested with a
/// list of test cases (see `test/eval/eval_runner_test.dart`),
/// without depending on `buildEvalDataset`'s real cases.
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

/// Runs the full evaluation against Gemini's real backend (see
/// docs/evaluation.md): deletes [userId]'s existing transactions,
/// replaces them with deterministic evaluation data
/// ([seedEvalData]), asks the questions (with spacing and a request
/// cap) directly to the real gateway and function executor — never
/// through `SendChatMessage`, which has its own real clock and its
/// cap of 20 questions per session — and returns the report in
/// Markdown, ready to paste into `docs/evaluation.md`.
///
/// [caseFilter], if not `null` nor empty, limits the run to the
/// cases whose `id` or `type.name` (for example `"escritura"`) are
/// in the set (each element is trimmed of spaces before comparing)
/// — useful for repeating only a subset without spending quota on
/// cases that have already passed. `null` or empty (after trimming
/// spaces) runs all of them. If any element is neither an `id` nor
/// a `type.name` of any case, or if the filter selects no case,
/// [runEval] throws [EvalCaseFilterError] **before** deleting or
/// seeding anything in the account and without calling Gemini —
/// never a silently empty report.
///
/// Before touching anything, checks that [sessionEmail] (the
/// already-signed-in session's email) matches [expectedEmail]
/// (`EVAL_ACCOUNT_EMAIL`); if it doesn't match, or if [expectedEmail]
/// is empty, throws [WrongEvalAccountError] without deleting or
/// writing anything.
///
/// [gatewayOverride] is only for `test/eval/eval_runner_test.dart`
/// (checking the automatic retry on an infrastructure error without
/// really calling Gemini, see [EvalResult.notEvaluable]): if it's
/// `null` (the normal value, always in `lib/eval_main.dart`), the
/// real `GeminiChatGateway` is used.
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

  // The dataset (and, with it, the list of valid ids/types) is
  // computed before touching the account: this way a badly-written
  // filter is caught without having deleted or seeded anything yet.
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
    // A multi-turn conversation (see `EvalCase.priorTurns`) spends
    // an estimated request per turn, not only for the final turn.
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
    // The real model's literal responses to `evalCase.priorTurns`,
    // in the same order (see `EvalResult.priorTurnResponses`): not
    // graded, only stored for the report. Reset on each attempt (a
    // retry after an infrastructure error reproduces the
    // conversation again from turn 1, so there's no point keeping
    // the previous attempt's ones).
    var priorResponses = <String>[];

    ChatFunctionExecutor buildExecutor() {
      return (name, arguments) => functions.execute(userId: userId, name: name, arguments: arguments, now: evalNow);
    }

    for (var attempt = 0; attempt < 2; attempt++) {
      final collectedResponses = <String>[];
      try {
        // Reproduces the previous turns with the real history
        // `ChatScreen` would see (same as `SendChatMessage`), to
        // reach the final turn in the same context as production.
        // Their responses aren't judged: they only become part of
        // the history.
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
        // There may be fewer responses than `priorTurns` if the
        // error interrupted the conversation midway through the
        // previous turns (see `EvalResult.priorTurnResponses`).
        priorResponses = collectedResponses;
        lastError = error;
        requestsUsed += config.estimatedRequestsPerCase * turnsInCase;
        if (attempt == 0) {
          wasRetried = true;
          log('  → error de infraestructura (${_describeError(error)}); repitiendo una vez...');
          await Future<void>.delayed(config.delayBetweenCases);
          countBefore = await transactionCount(); // in case the first attempt did reach something
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

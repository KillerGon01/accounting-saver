import 'package:firebase_ai/firebase_ai.dart';

import '../../domain/common/clock.dart';

/// Gemini models to try in order when the first one returns quota
/// exhausted (429 / `RESOURCE_EXHAUSTED`), all on the Gemini Developer
/// API's free tier. A single list so the chat and natural language
/// input share the same criterion and, through
/// [GeminiModelAvailability], the same memory of which model is
/// exhausted: both spend the project's same daily quota.
const geminiModelFallbacks = <String>[
  'gemini-3.5-flash-lite',
  'gemini-3.8-flash',
];

/// How long a model is remembered as exhausted before trying it again.
const geminiModelExhaustionDuration = Duration(hours: 1);

/// Remembers in memory, for [geminiModelExhaustionDuration] or until
/// the app restarts, which of [geminiModelFallbacks] have returned
/// quota exhausted, so as not to spend a request retrying a model
/// already known to fail. Also remembers, until the app restarts
/// (never expiring, unlike exhausted quota), which models no longer
/// exist in the API — see [markUnavailableForSession].
///
/// Meant as a single instance shared across the whole app (see the
/// providers): the chat and natural language input spend the
/// project's same daily quota, so they must share this memory.
class GeminiModelAvailability {
  // ignore: prefer_initializing_formals (el nombre público es `clock`, no `_clock`)
  GeminiModelAvailability({Clock clock = const SystemClock()}) : _clock = clock;

  final Clock _clock;
  final _exhaustedUntil = <String, DateTime>{};
  final _unavailableForSession = <String>{};

  bool isAvailable(String model) {
    if (_unavailableForSession.contains(model)) return false;
    final until = _exhaustedUntil[model];
    if (until == null) return true;
    if (_clock.now().isBefore(until)) return false;
    _exhaustedUntil.remove(model);
    return true;
  }

  void markExhausted(String model) {
    _exhaustedUntil[model] = _clock.now().add(geminiModelExhaustionDuration);
  }

  /// For a model that no longer exists in the API (404 `NOT_FOUND`,
  /// see [isModelNotFoundError]), not one with exhausted quota:
  /// retrying it isn't going to make it start existing, so, unlike
  /// [markExhausted], this doesn't expire over time — it's only
  /// forgotten when the app restarts (a new [GeminiModelAvailability]
  /// instance).
  void markUnavailableForSession(String model) {
    _unavailableForSession.add(model);
  }
}

/// `true` if [error] indicates that a Gemini model doesn't exist or
/// is no longer available in this API. Two forms actually seen,
/// neither fully reliable on its own, so both are checked:
/// - A model retired from the API: "models/&lt;nombre&gt; is not found
///   for API version...".
/// - A model no longer available to new projects (this is how
///   `gemini-2.5-*` started responding, before the API retires them
///   entirely): "This model models/&lt;nombre&gt; is no longer
///   available to new users. Please update your code to use
///   models/&lt;otro&gt; ...".
///
/// The `firebase_ai` package (4.0.0, `lib/src/error.dart`, function
/// `parseError`) exposes neither the HTTP code (404) nor the error
/// body's `status` ("NOT_FOUND"): both cases above arrive as a 404
/// with body `{"error": {"code": 404, "message": "...", "status":
/// "NOT_FOUND"}}`, but `parseError`'s `switch` only looks at `message`
/// (and, for other types, `details`/`status` of very specific cases
/// that aren't this one); any error with a text `message` field that
/// doesn't fit those other cases — this one included — falls into the
/// generic `ServerException`, which only stores that text. Checked
/// against the package's own fixture
/// (`test/google_ai_response_parsing_test.dart`, the "for general
/// server errors" case): there's no code or status field to look at
/// in Dart's `error`, only the text. So, same as
/// [isTransientGeminiError] and `isAppCheckAttestationError`, the
/// message's text has to be checked instead of the type or a code the
/// package doesn't keep.
bool isModelNotFoundError(Object error) {
  if (error is QuotaExceeded) return false;
  if (error is! FirebaseAIException) return false;
  final message = error.message;
  return message.contains('is not found for API version') || message.contains('no longer available');
}

/// Tries [attempt] with the first available model from [models]
/// according to [availability]. On exhausted quota ([QuotaExceeded]),
/// marks it as exhausted (temporarily,
/// [GeminiModelAvailability.markExhausted]) and retries with the
/// list's next available model. On a nonexistent model
/// ([isModelNotFoundError]), does the same but marks it as
/// unavailable for the whole session
/// ([GeminiModelAvailability.markUnavailableForSession], never
/// expiring). In both cases, this continues until one responds or the
/// models run out: no loops, at most one attempt per model in the
/// list within this same call. Any other error (503, timeout, App
/// Check 403...) is rethrown immediately, without trying another
/// model — the caller handles it.
///
/// Throws [QuotaExceeded] if no model is left available (all already
/// exhausted or nonexistent) or if every attempt in this call fails
/// with exhausted quota; rethrows the last attempt's error if all fail
/// because the models don't exist.
Future<T> withGeminiModelFallback<T>({
  required GeminiModelAvailability availability,
  required Future<T> Function(String model) attempt,
  List<String> models = geminiModelFallbacks,
}) async {
  final candidates = models.where(availability.isAvailable).toList();
  if (candidates.isEmpty) {
    throw QuotaExceeded('Todos los modelos de Gemini están agotados temporalmente.');
  }

  for (var i = 0; i < candidates.length; i++) {
    try {
      return await attempt(candidates[i]);
    } on QuotaExceeded {
      availability.markExhausted(candidates[i]);
      if (i == candidates.length - 1) rethrow;
    } catch (error) {
      if (!isModelNotFoundError(error)) rethrow;
      availability.markUnavailableForSession(candidates[i]);
      if (i == candidates.length - 1) rethrow;
    }
  }
  throw StateError('unreachable');
}

import 'dart:async';

import 'package:firebase_ai/firebase_ai.dart';

/// How long to wait before the single retry on a transient server
/// failure (see [withTransientRetry]).
const geminiTransientRetryDelay = Duration(milliseconds: 1500);

/// Time cap for a single `generateContent` call, the only place this
/// value is defined (see [withTransientRetry], which applies it to
/// each attempt). 150 s: the latency actually observed on the
/// deployed web app (Gemini 3.8 Flash, free tier) reached 84 s on one
/// call and 108 s on another — with the previous value (90 s), the
/// second one would have cut off a response Google was indeed going
/// to deliver, showing "La IA no está disponible ahora mismo" when
/// there was no real failure (see docs/design.md). A timeout is NEVER
/// retried (see [isTransientGeminiError]): the client can't cancel
/// the request already sent to the server (`.timeout()` only stops
/// waiting on the client side, see the limitation documented in
/// docs/design.md), so retrying would duplicate a request that might
/// still be processing on the backend, spending twice the quota for a
/// single question. The worst case before "La IA no está disponible
/// ahora mismo" on a timeout is, therefore, a single wait of this
/// value, not two.
const geminiRequestTimeout = Duration(seconds: 150);

/// Whether [error] is a transient failure — temporary, not quota —
/// while generating content: a 503, `UNAVAILABLE` or "Deadline
/// expired" that Gemini's own server has returned as a response.
/// `HttpApiClient.makeRequest` (package `firebase_ai` 4.0.0,
/// `lib/src/client.dart`) throws a plain `FirebaseAIException`
/// (neither `QuotaExceeded` nor any other subclass) with the full
/// response body in the message when the backend returns a 5xx code,
/// so we check the text instead of the type. [QuotaExceeded] is
/// explicitly excluded even though it also implements
/// `FirebaseAIException`: exhausted quota is handled by
/// `withGeminiModelFallback` by switching models, not by waiting and
/// retrying the same one.
///
/// A [TimeoutException] (see [geminiRequestTimeout]) is NOT transient
/// for this purpose, on purpose: unlike a 503 (the server has already
/// finished and answered to try again later), a timeout only means
/// the client has stopped waiting; the server may still be
/// processing that same request. Retrying it would send a second
/// request without knowing whether the first will end up responding,
/// so [withTransientRetry] rethrows it immediately, with no retry.
bool isTransientGeminiError(Object error) {
  if (error is QuotaExceeded) return false;
  if (error is! FirebaseAIException) return false;
  final message = error.message;
  return message.contains('UNAVAILABLE') ||
      message.contains('Deadline expired') ||
      message.contains('Server Error [503]');
}

/// Retries [attempt] once, after [delay], if it fails with a
/// transient server error ([isTransientGeminiError]). The initial
/// attempt is cut off at [timeout] with a [TimeoutException] if the
/// server doesn't respond in time; a timeout is never retried (see
/// why in [isTransientGeminiError]), it's rethrown immediately just
/// like any other non-transient error (including exhausted quota),
/// for the caller to handle (for example, `withGeminiModelFallback`
/// switching to the next model). At most one extra attempt per call,
/// never a loop, and only on a 503/`UNAVAILABLE`/"Deadline expired";
/// the retry uses the same [attempt] (the same model), not another
/// one from the fallback list, and the model isn't marked as
/// exhausted (only `withGeminiModelFallback` does that, on exhausted
/// quota).
Future<T> withTransientRetry<T>(
  Future<T> Function() attempt, {
  Duration delay = geminiTransientRetryDelay,
  Duration timeout = geminiRequestTimeout,
}) async {
  try {
    return await attempt().timeout(timeout);
  } catch (error) {
    if (!isTransientGeminiError(error)) rethrow;
    await Future<void>.delayed(delay);
    return attempt().timeout(timeout);
  }
}

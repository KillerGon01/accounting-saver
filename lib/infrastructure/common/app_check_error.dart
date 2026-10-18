import 'package:firebase_ai/firebase_ai.dart';

/// Whether [error] indicates that Gemini's backend rejected the
/// request because the App Check token isn't valid: 403,
/// `PERMISSION_DENIED`, "App attestation failed" — actually seen
/// while testing the chat on October 8, 2026, when enabling App
/// Check. It's not a quota problem nor a transient server failure: it
/// shouldn't be retried ([withTransientRetry] doesn't retry it because
/// its message doesn't contain `UNAVAILABLE`, `Deadline expired` or
/// `Server Error [503]`) nor should the model be marked as exhausted
/// ([withGeminiModelFallback] only acts on [QuotaExceeded], and this
/// error isn't that). It just needs to be translated to the usual
/// message, never showing the error's raw JSON to the user.
bool isAppCheckAttestationError(Object error) {
  if (error is QuotaExceeded) return false;
  if (error is! FirebaseAIException) return false;
  final message = error.message;
  return message.contains('App attestation failed') || message.contains('PERMISSION_DENIED');
}

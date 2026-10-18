import '../../domain/transactions/llm_gateway_exception.dart';
import '../../domain/transactions/not_understood_exception.dart';

const _genericMessage =
    'No se pudo interpretar el texto. Inténtalo de nuevo o añade el movimiento a mano.';

/// Spanish-language message for an error extracting a transaction
/// with AI. Domain validations (`ArgumentError`, for example a
/// category or a date the AI shouldn't have returned) use the same
/// generic message: from the user's point of view, the text has to
/// be reworded or the form filled in by hand.
String llmErrorMessage(Object error) {
  if (error is NotUnderstoodException) return error.message;
  if (error is! LlmGatewayException) return _genericMessage;

  return switch (error.code) {
    'quota-exceeded' => 'Se ha agotado la cuota gratuita de la IA por ahora. '
        'Inténtalo más tarde o añade el movimiento a mano.',
    'network-error' =>
      'No se pudo contactar con la IA. Comprueba tu conexión e inténtalo de nuevo.',
    // Invalid App Check token (403, "App attestation failed"):
    // translated to the AI-unavailable message, not to the generic
    // "no se pudo interpretar el texto" (that would be misleading:
    // the problem isn't the text) nor, of course, to the error's raw
    // JSON.
    'app-check-failed' => 'La IA no está disponible ahora mismo.',
    // A timeout (150 s, no retry) is translated the same as an App
    // Check failure: the problem is the AI's availability, not the
    // user's text, so it doesn't fall into the generic "no se pudo
    // interpretar el texto".
    'timeout' => 'La IA no está disponible ahora mismo.',
    // A retired model (404 "is not found for API version...", see
    // `isModelNotFoundError`) also isn't a problem with the user's
    // text: same message as an App Check failure or a timeout.
    'model-not-found' => 'La IA no está disponible ahora mismo.',
    _ => _genericMessage,
  };
}

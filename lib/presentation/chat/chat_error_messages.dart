import '../../domain/transactions/llm_gateway_exception.dart';

const _genericMessage = 'La IA no está disponible ahora mismo.';

/// Spanish-language message for a chat error. Always generic, so as
/// not to carry technical details (nor the user's text) over to the
/// UI.
String chatErrorMessage(Object error) {
  if (error is StateError) return 'Espera a que termine de responder.';
  if (error is! LlmGatewayException) return _genericMessage;

  return switch (error.code) {
    'quota-exceeded' => 'Se ha agotado la cuota gratuita de la IA por ahora. Inténtalo más tarde.',
    'network-error' =>
      'No se pudo contactar con la IA. Comprueba tu conexión e inténtalo de nuevo.',
    'session-limit-reached' =>
      'Has llegado al máximo de preguntas de esta sesión. Cierra y vuelve a abrir el chat para seguir preguntando.',
    // Same text as the generic one: left explicit (instead of
    // falling into the `_` below) to make clear that an invalid App
    // Check token (403, "App attestation failed") is translated to
    // this message on purpose, never to the error's raw JSON.
    'app-check-failed' => _genericMessage,
    // Same text as the generic one, explicit for the same reason as
    // 'app-check-failed': a timeout (150 s, no retry) is also
    // translated to this message, not to a different one about
    // "taking a long time".
    'timeout' => _genericMessage,
    // Same: a retired model (404 "is not found for API version...",
    // see `isModelNotFoundError`) is translated to this same message,
    // never to the model's name or the error's raw text.
    'model-not-found' => _genericMessage,
    _ => _genericMessage,
  };
}

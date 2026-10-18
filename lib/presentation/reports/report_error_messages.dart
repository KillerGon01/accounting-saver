import '../../domain/transactions/llm_gateway_exception.dart';

const _genericMessage = 'La IA no está disponible ahora mismo.';

/// Spanish-language message for an error generating the monthly
/// report's AI comment. Same texts as `chatErrorMessage` for the
/// shared codes (quota, timeout, App Check); `comment-limit-reached`
/// is the only one specific to this use case (equivalent to
/// `session-limit-reached` in the chat).
String reportErrorMessage(Object error) {
  if (error is StateError) return 'Espera a que termine de generarse el comentario anterior.';
  if (error is! LlmGatewayException) return _genericMessage;

  return switch (error.code) {
    'quota-exceeded' => 'Se ha agotado la cuota gratuita de la IA por ahora. Inténtalo más tarde.',
    'network-error' =>
      'No se pudo contactar con la IA. Comprueba tu conexión e inténtalo de nuevo.',
    'comment-limit-reached' =>
      'Has llegado al máximo de comentarios de esta sesión. Vuelve a abrir el resumen para seguir generando.',
    // Same text as the generic one, explicit for the same reason as
    // in `chatErrorMessage`: an invalid App Check token or a timeout
    // are translated to this message, never to the raw JSON nor to a
    // different one about "taking a long time".
    'app-check-failed' => _genericMessage,
    'timeout' => _genericMessage,
    'model-not-found' => _genericMessage,
    _ => _genericMessage,
  };
}

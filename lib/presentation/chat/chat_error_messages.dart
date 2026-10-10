import '../../domain/transactions/llm_gateway_exception.dart';

const _genericMessage = 'La IA no está disponible ahora mismo.';

/// Mensaje en español para un error del chat. Siempre genérico, para no
/// trasladar detalles técnicos (ni el texto del usuario) a la interfaz.
String chatErrorMessage(Object error) {
  if (error is StateError) return 'Espera a que termine de responder.';
  if (error is! LlmGatewayException) return _genericMessage;

  return switch (error.code) {
    'quota-exceeded' => 'Se ha agotado la cuota gratuita de la IA por ahora. Inténtalo más tarde.',
    'network-error' =>
      'No se pudo contactar con la IA. Comprueba tu conexión e inténtalo de nuevo.',
    'session-limit-reached' =>
      'Has llegado al máximo de preguntas de esta sesión. Cierra y vuelve a abrir el chat para seguir preguntando.',
    // Mismo texto que el genérico: se deja explícito (en vez de caer en
    // el `_` de abajo) para que quede claro que un token de App Check
    // inválido (403, "App attestation failed") se traduce a propósito a
    // este mensaje, nunca al JSON crudo del error.
    'app-check-failed' => _genericMessage,
    // Mismo texto que el genérico, explícito por la misma razón que
    // 'app-check-failed': un timeout (90 s, con un reintento) también se
    // traduce a este mensaje, no a uno distinto sobre "tardando mucho".
    'timeout' => _genericMessage,
    _ => _genericMessage,
  };
}

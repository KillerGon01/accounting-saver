import '../../domain/transactions/llm_gateway_exception.dart';

const _genericMessage = 'La IA no está disponible ahora mismo.';

/// Mensaje en español para un error al generar el comentario de IA del
/// resumen mensual. Mismos textos que `chatErrorMessage` para los
/// códigos compartidos (cuota, timeout, App Check); `comment-limit-reached`
/// es el único propio de este caso de uso (equivalente a
/// `session-limit-reached` en el chat).
String reportErrorMessage(Object error) {
  if (error is StateError) return 'Espera a que termine de generarse el comentario anterior.';
  if (error is! LlmGatewayException) return _genericMessage;

  return switch (error.code) {
    'quota-exceeded' => 'Se ha agotado la cuota gratuita de la IA por ahora. Inténtalo más tarde.',
    'network-error' =>
      'No se pudo contactar con la IA. Comprueba tu conexión e inténtalo de nuevo.',
    'comment-limit-reached' =>
      'Has llegado al máximo de comentarios de esta sesión. Vuelve a abrir el resumen para seguir generando.',
    // Mismo texto que el genérico, explícito por la misma razón que en
    // `chatErrorMessage`: un token de App Check inválido o un timeout se
    // traducen a este mensaje, nunca al JSON crudo ni a uno distinto
    // sobre "tardando mucho".
    'app-check-failed' => _genericMessage,
    'timeout' => _genericMessage,
    _ => _genericMessage,
  };
}

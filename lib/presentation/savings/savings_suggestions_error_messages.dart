import '../../domain/transactions/llm_gateway_exception.dart';

const _genericMessage = 'La IA no está disponible ahora mismo.';

/// Mensaje en español para un error al generar el resumen con IA de las
/// sugerencias de ahorro. Mismos textos que `reportErrorMessage` para los
/// códigos compartidos (cuota, timeout, App Check, red);
/// `explanation-limit-reached` es el único propio de este caso de uso
/// (equivalente a `comment-limit-reached` en el resumen mensual).
String savingsSuggestionsErrorMessage(Object error) {
  if (error is StateError) return 'Espera a que termine de generarse el resumen anterior.';
  if (error is! LlmGatewayException) return _genericMessage;

  return switch (error.code) {
    'quota-exceeded' => 'Se ha agotado la cuota gratuita de la IA por ahora. Inténtalo más tarde.',
    'network-error' =>
      'No se pudo contactar con la IA. Comprueba tu conexión e inténtalo de nuevo.',
    'explanation-limit-reached' =>
      'Has llegado al máximo de resúmenes de esta sesión. Vuelve a abrir la hoja para seguir generando.',
    // Mismo texto que el genérico, explícito por la misma razón que en
    // `reportErrorMessage`: un token de App Check inválido o un timeout se
    // traducen a este mensaje, nunca al JSON crudo ni a uno distinto.
    'app-check-failed' => _genericMessage,
    'timeout' => _genericMessage,
    'model-not-found' => _genericMessage,
    _ => _genericMessage,
  };
}

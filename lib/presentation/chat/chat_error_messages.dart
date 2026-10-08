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
    _ => _genericMessage,
  };
}

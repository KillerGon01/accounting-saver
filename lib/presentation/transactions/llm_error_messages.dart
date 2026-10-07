import '../../domain/transactions/llm_gateway_exception.dart';
import '../../domain/transactions/not_understood_exception.dart';

const _genericMessage =
    'No se pudo interpretar el texto. Inténtalo de nuevo o añade el movimiento a mano.';

/// Mensaje en español para un error al extraer un movimiento con la IA.
/// Las validaciones de dominio (`ArgumentError`, por ejemplo una categoría
/// o una fecha que la IA no debería haber devuelto) usan el mismo mensaje
/// genérico: desde el punto de vista del usuario, hay que reformular el
/// texto o rellenar el formulario a mano.
String llmErrorMessage(Object error) {
  if (error is NotUnderstoodException) return error.message;
  if (error is! LlmGatewayException) return _genericMessage;

  return switch (error.code) {
    'quota-exceeded' => 'Se ha agotado la cuota gratuita de la IA por ahora. '
        'Inténtalo más tarde o añade el movimiento a mano.',
    'network-error' =>
      'No se pudo contactar con la IA. Comprueba tu conexión e inténtalo de nuevo.',
    _ => _genericMessage,
  };
}

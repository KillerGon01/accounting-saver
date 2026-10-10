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
    // Token de App Check inválido (403, "App attestation failed"): se
    // traduce al mensaje de la IA no disponible, no al genérico de "no se
    // pudo interpretar el texto" (sería engañoso: el problema no es el
    // texto) ni, por supuesto, al JSON crudo del error.
    'app-check-failed' => 'La IA no está disponible ahora mismo.',
    // Un timeout (150 s, sin reintento) se traduce igual que el fallo de
    // App Check: el problema es la disponibilidad de la IA, no el texto
    // del usuario, así que no cae en el genérico de "no se pudo
    // interpretar el texto".
    'timeout' => 'La IA no está disponible ahora mismo.',
    // Un modelo retirado (404 "is not found for API version...", ver
    // `isModelNotFoundError`) tampoco es un problema del texto del
    // usuario: mismo mensaje que el fallo de App Check o el timeout.
    'model-not-found' => 'La IA no está disponible ahora mismo.',
    _ => _genericMessage,
  };
}

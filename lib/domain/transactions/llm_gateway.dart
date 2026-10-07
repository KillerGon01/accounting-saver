import 'raw_parsed_transaction.dart';

/// Puerto hacia un modelo de lenguaje capaz de extraer un movimiento a
/// partir de un texto libre. La infraestructura (Gemini) implementa esta
/// interfaz; el dominio y la aplicación no conocen el proveedor.
abstract class LlmGateway {
  /// Extrae un movimiento a partir de [text]. [now] se usa para resolver
  /// fechas relativas ("ayer", "el lunes pasado").
  ///
  /// Si el texto no describe con claridad un movimiento con importe, el
  /// resultado tiene `understood: false` y el resto de campos en `null`;
  /// no lanza una excepción por eso.
  ///
  /// Lanza [LlmGatewayException] si la IA no está disponible (cuota, red)
  /// o si la respuesta no se puede interpretar.
  Future<RawParsedTransaction> extractTransaction({
    required String text,
    required DateTime now,
  });
}

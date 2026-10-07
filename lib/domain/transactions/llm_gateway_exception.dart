/// Error al extraer un movimiento con la IA, independiente del proveedor.
/// La infraestructura traduce sus errores (cuota, red, respuesta
/// inesperada) a este tipo, y la presentación decide el mensaje a mostrar
/// a partir de [code].
class LlmGatewayException implements Exception {
  const LlmGatewayException(this.code, {this.message});

  final String code;
  final String? message;

  @override
  String toString() => 'LlmGatewayException($code)';
}

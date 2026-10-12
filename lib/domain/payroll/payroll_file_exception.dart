/// El archivo elegido no es un PDF válido o supera el tamaño máximo (ver
/// `ParsePayroll.maxPdfBytes`), comprobado en código antes de llamar al
/// modelo: no gasta cuota de Gemini ni cuenta como una lectura de la
/// sesión.
class PayrollFileException implements Exception {
  const PayrollFileException(this.message);

  final String message;

  @override
  String toString() => 'PayrollFileException: $message';
}

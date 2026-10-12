import 'dart:typed_data';

/// Implementación vacía para toda plataforma que no sea web (ver
/// `payroll_file_picker.dart`). Nunca debería llamarse de verdad: la
/// pantalla que la usa (`PayrollScreen`) solo se muestra si `kIsWeb`.
Future<Uint8List?> pickPayrollPdfBytes() {
  throw UnsupportedError('Elegir un PDF de nómina solo está disponible en web.');
}

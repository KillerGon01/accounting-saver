import 'dart:typed_data';

/// Empty implementation for any platform that isn't web (see
/// `payroll_file_picker.dart`). Should never actually be called: the
/// screen that uses it (`PayrollScreen`) only shows if `kIsWeb`.
Future<Uint8List?> pickPayrollPdfBytes() {
  throw UnsupportedError('Elegir un PDF de nómina solo está disponible en web.');
}

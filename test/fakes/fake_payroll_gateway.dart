import 'dart:typed_data';

import 'package:accounting_saver/domain/payroll/extracted_payroll.dart';
import 'package:accounting_saver/domain/payroll/payroll_gateway.dart';

/// Fake configurable con un resultado o un error fijo, para probar
/// [ParsePayroll] sin llamar a Gemini. Igual que [FakeLlmGateway].
class FakePayrollGateway implements PayrollGateway {
  FakePayrollGateway.returning(this._result) : _error = null;

  FakePayrollGateway.throwing(Object error)
    : _error = error,
      _result = null;

  final ExtractedPayroll? _result;
  final Object? _error;

  Uint8List? lastBytes;
  var callCount = 0;

  @override
  Future<ExtractedPayroll> extractPayroll(Uint8List pdfBytes) async {
    lastBytes = pdfBytes;
    callCount++;
    if (_error != null) throw _error;
    return _result!;
  }
}

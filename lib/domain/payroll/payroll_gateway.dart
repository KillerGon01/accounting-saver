import 'dart:typed_data';

import 'extracted_payroll.dart';

/// Port to the AI model that reads a payroll PDF. The infrastructure
/// layer implements this against Gemini (see `GeminiPayrollGateway`);
/// the domain and application layers know nothing about Firebase or
/// `firebase_ai`.
abstract interface class PayrollGateway {
  /// Throws `LlmGatewayException` (`lib/domain/transactions/llm_gateway_exception.dart`)
  /// on any failure: quota exhausted, network, timeout, App Check, or a
  /// response that can't be parsed. The same codes natural language
  /// input already uses, to reuse its messages.
  Future<ExtractedPayroll> extractPayroll(Uint8List pdfBytes);
}

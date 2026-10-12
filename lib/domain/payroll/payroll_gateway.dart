import 'dart:typed_data';

import 'extracted_payroll.dart';

/// Puerto hacia el modelo de IA que lee un PDF de nómina. La infraestructura
/// implementa esto contra Gemini (ver `GeminiPayrollGateway`); el dominio y
/// la aplicación no saben nada de Firebase ni de `firebase_ai`.
abstract interface class PayrollGateway {
  /// Lanza `LlmGatewayException` (`lib/domain/transactions/llm_gateway_exception.dart`)
  /// ante cualquier fallo: cuota agotada, red, timeout, App Check o
  /// respuesta que no se pueda interpretar. Los mismos códigos que ya usa
  /// la entrada en lenguaje natural, para reusar sus mensajes.
  Future<ExtractedPayroll> extractPayroll(Uint8List pdfBytes);
}

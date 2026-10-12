import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/payroll/parse_payroll.dart';
import '../../domain/payroll/payroll_gateway.dart';
import '../../infrastructure/payroll/gemini_payroll_gateway.dart';
import '../common/ai_providers.dart';

final payrollGatewayProvider = Provider<PayrollGateway>(
  (ref) => GeminiPayrollGateway(availability: ref.watch(geminiModelAvailabilityProvider)),
);

/// Una instancia por usuario (familia por `userId`), igual que
/// `sendChatMessageProvider`: así el tope de 5 lecturas por sesión
/// (`ParsePayroll.maxReadsPerSession`) es efectivo aunque la pantalla se
/// cierre y se reabra para el mismo usuario, y no se comparte entre dos
/// usuarios que usen la app en la misma pestaña sin reiniciarla.
final parsePayrollProvider = Provider.family<ParsePayroll, String>((ref, userId) {
  return ParsePayroll(ref.watch(payrollGatewayProvider));
});

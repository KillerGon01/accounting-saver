import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/payroll/parse_payroll.dart';
import '../../domain/payroll/payroll_gateway.dart';
import '../../infrastructure/payroll/gemini_payroll_gateway.dart';
import '../common/ai_providers.dart';

final payrollGatewayProvider = Provider<PayrollGateway>(
  (ref) => GeminiPayrollGateway(availability: ref.watch(geminiModelAvailabilityProvider)),
);

/// One instance per user (a family by `userId`), same as
/// `sendChatMessageProvider`: this way the cap of 5 readings per
/// session (`ParsePayroll.maxReadsPerSession`) stays in effect even
/// if the screen is closed and reopened for the same user, and isn't
/// shared between two users who use the app in the same tab without
/// restarting it.
final parsePayrollProvider = Provider.family<ParsePayroll, String>((ref, userId) {
  return ParsePayroll(ref.watch(payrollGatewayProvider));
});

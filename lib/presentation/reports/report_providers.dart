import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/reports/build_monthly_report.dart';
import '../../application/reports/explain_monthly_report.dart';
import '../../domain/reports/monthly_report.dart';
import '../../domain/reports/monthly_report_gateway.dart';
import '../../infrastructure/reports/gemini_monthly_report_gateway.dart';
import '../common/ai_providers.dart';
import '../transactions/transaction_providers.dart';

final monthlyReportGatewayProvider = Provider<MonthlyReportGateway>(
  (ref) => GeminiMonthlyReportGateway(availability: ref.watch(geminiModelAvailabilityProvider)),
);

final buildMonthlyReportProvider = Provider<BuildMonthlyReport>(
  (ref) => BuildMonthlyReport(ref.watch(transactionRepositoryProvider)),
);

/// Una instancia por usuario (familia por `userId`), igual que
/// `sendChatMessageProvider`: su propia caché y su propio tope de 3
/// comentarios por sesión, aislados entre un usuario y otro.
final explainMonthlyReportProvider = Provider.family<ExplainMonthlyReport, String>((ref, userId) {
  return ExplainMonthlyReport(
    ref.watch(monthlyReportGatewayProvider),
    ref.watch(transactionsChangeNotifierProvider),
  );
});

/// El informe de un mes. Reutiliza `MonthlyTransactionsParams` (ya
/// definido en `transaction_providers.dart`) en vez de crear una clase de
/// parámetros nueva con los mismos tres campos (`userId`, `year`,
/// `month`).
///
/// Observa `transactionsVersionProvider`, no solo
/// `transactionsChangeNotifierProvider`: así Riverpod vuelve a calcular
/// el informe en cuanto cambien los movimientos (crear, editar, borrar,
/// cargar o borrar datos de ejemplo), sin que la pantalla tenga que
/// recargarse a mano.
final monthlyReportProvider = FutureProvider.family<MonthlyReport, MonthlyTransactionsParams>((ref, params) {
  ref.watch(transactionsVersionProvider);
  return ref.watch(buildMonthlyReportProvider)(userId: params.userId, year: params.year, month: params.month);
});

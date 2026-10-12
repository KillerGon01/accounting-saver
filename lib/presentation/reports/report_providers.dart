import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/reports/build_month_end_forecast.dart';
import '../../application/reports/build_monthly_report.dart';
import '../../application/reports/explain_monthly_report.dart';
import '../../domain/reports/month_end_forecast.dart';
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

final buildMonthEndForecastProvider = Provider<BuildMonthEndForecast>(
  (ref) => BuildMonthEndForecast(ref.watch(transactionRepositoryProvider)),
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

/// `null` para cualquier mes que no sea el mes en curso (ver
/// `BuildMonthEndForecast`), o si falla el cálculo (consultas extra sobre
/// los 3 meses anteriores): la pantalla lee este provider con
/// `AsyncValue.value` (nullable, no lanza — ver `MonthlyReportScreen`), así
/// que un error aquí nunca impide que se muestre el resto del resumen
/// mensual — solo hace que la tarjeta de previsión no aparezca.
///
/// `retry: (_, _) => null` (sin reintentos): a diferencia de un fallo de
/// Gemini (que sí conviene reintentar), un error aquí no se resuelve solo
/// con esperar — son las mismas consultas que la propia pantalla volverá
/// a disparar en cuanto cambien los movimientos (`transactionsVersionProvider`
/// más abajo). Reintentar con la política por defecto de Riverpod
/// (`ProviderContainer.defaultRetry`, con temporizadores reales) deja
/// temporizadores pendientes que no hacen falta para este caso y que,
/// detectado al escribir los tests, llegan a saltar la comprobación de
/// `flutter_test` de que no quede ningún `Timer` vivo al terminar un test.
final monthEndForecastProvider = FutureProvider.family<MonthEndForecast?, MonthlyTransactionsParams>(
  (ref, params) {
    ref.watch(transactionsVersionProvider);
    return ref.watch(buildMonthEndForecastProvider)(userId: params.userId, year: params.year, month: params.month);
  },
  retry: (retryCount, error) => null,
);

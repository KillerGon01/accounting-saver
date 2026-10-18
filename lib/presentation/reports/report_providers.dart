import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/reports/build_month_end_forecast.dart';
import '../../application/reports/build_monthly_report.dart';
import '../../application/reports/build_unusual_expenses.dart';
import '../../application/reports/explain_monthly_report.dart';
import '../../domain/reports/month_end_forecast.dart';
import '../../domain/reports/monthly_report.dart';
import '../../domain/reports/monthly_report_gateway.dart';
import '../../domain/reports/unusual_expenses.dart';
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

final buildUnusualExpensesProvider = Provider<BuildUnusualExpenses>(
  (ref) => BuildUnusualExpenses(ref.watch(transactionRepositoryProvider)),
);

/// One instance per user (a family by `userId`), same as
/// `sendChatMessageProvider`: its own cache and its own cap of 3
/// comments per session, isolated between one user and another.
final explainMonthlyReportProvider = Provider.family<ExplainMonthlyReport, String>((ref, userId) {
  return ExplainMonthlyReport(
    ref.watch(monthlyReportGatewayProvider),
    ref.watch(transactionsChangeNotifierProvider),
  );
});

/// A month's report. Reuses `MonthlyTransactionsParams` (already
/// defined in `transaction_providers.dart`) instead of creating a new
/// params class with the same three fields (`userId`, `year`,
/// `month`).
///
/// Watches `transactionsVersionProvider`, not just
/// `transactionsChangeNotifierProvider`: this way Riverpod recomputes
/// the report as soon as the transactions change (creating, editing,
/// deleting, loading, or deleting demo data), without the screen
/// having to be reloaded by hand.
final monthlyReportProvider = FutureProvider.family<MonthlyReport, MonthlyTransactionsParams>((ref, params) {
  ref.watch(transactionsVersionProvider);
  return ref.watch(buildMonthlyReportProvider)(userId: params.userId, year: params.year, month: params.month);
});

/// `null` for any month that isn't the current one (see
/// `BuildMonthEndForecast`), or if the calculation fails (extra
/// queries over the previous 3 months): the screen reads this
/// provider with `AsyncValue.value` (nullable, doesn't throw — see
/// `MonthlyReportScreen`), so an error here never prevents the rest
/// of the monthly report from showing — it only means the forecast
/// card doesn't appear.
///
/// `retry: (_, _) => null` (no retries): unlike a Gemini failure
/// (which is worth retrying), an error here isn't solved just by
/// waiting — they're the same queries the screen itself will fire
/// again as soon as the transactions change
/// (`transactionsVersionProvider` below). Retrying with Riverpod's
/// default policy (`ProviderContainer.defaultRetry`, with real
/// timers) leaves pending timers that aren't needed for this case
/// and that, found while writing the tests, end up tripping
/// `flutter_test`'s check that no `Timer` is left alive when a test
/// finishes.
final monthEndForecastProvider = FutureProvider.family<MonthEndForecast?, MonthlyTransactionsParams>(
  (ref, params) {
    ref.watch(transactionsVersionProvider);
    return ref.watch(buildMonthEndForecastProvider)(userId: params.userId, year: params.year, month: params.month);
  },
  retry: (retryCount, error) => null,
);

/// Same pattern as [monthEndForecastProvider]: `null` for a month
/// that isn't the current one or if the calculation fails (extra
/// queries over the same previous 3 months, see
/// `BuildUnusualExpenses`); the screen reads this provider with
/// `AsyncValue.value` (nullable, doesn't throw), so an error here
/// never prevents the rest of the monthly report from showing — it
/// only means the unusual expenses card doesn't appear. Same
/// `retry: (_, _) => null` and the same reason (see the comment
/// above).
final unusualExpensesProvider = FutureProvider.family<UnusualExpensesResult?, MonthlyTransactionsParams>(
  (ref, params) {
    ref.watch(transactionsVersionProvider);
    return ref.watch(buildUnusualExpensesProvider)(userId: params.userId, year: params.year, month: params.month);
  },
  retry: (retryCount, error) => null,
);

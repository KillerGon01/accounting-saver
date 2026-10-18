import 'monthly_report.dart';

/// Port for asking an AI for a prose comment on an already-computed
/// [MonthlyReport]. Unlike [ChatGateway], this is a single call, no
/// function calling: the [MonthlyReport] it receives only has
/// aggregated figures (totals, by category, comparison), with no field
/// for a transaction's description or concept — so no implementation
/// can leak into the prompt something the type doesn't even carry.
abstract class MonthlyReportGateway {
  Future<String> explain(MonthlyReport report);
}

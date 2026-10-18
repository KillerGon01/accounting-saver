/// Formats a percentage (0-100, or any delta) to one decimal, with a
/// comma as the decimal separator (same as `formatCents`). Rounding
/// happens here, only when displaying: `MonthlyReport`/`BuildMonthlyReport`
/// store the value as `double` without rounding (see
/// `domain/reports/monthly_report.dart`).
String formatPercentage(double value) {
  final text = value.toStringAsFixed(1).replaceAll('.', ',');
  return '$text %';
}

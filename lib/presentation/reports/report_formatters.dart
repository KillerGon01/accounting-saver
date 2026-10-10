/// Formatea un porcentaje (0-100, o cualquier delta) a un decimal, con
/// coma como separador decimal (igual que `formatCents`). El redondeo
/// pasa aquí, solo al mostrar: `MonthlyReport`/`BuildMonthlyReport`
/// guardan el valor en `double` sin redondear (ver
/// `domain/reports/monthly_report.dart`).
String formatPercentage(double value) {
  final text = value.toStringAsFixed(1).replaceAll('.', ',');
  return '$text %';
}

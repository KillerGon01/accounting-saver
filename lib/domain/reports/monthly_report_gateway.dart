import 'monthly_report.dart';

/// Puerto para pedir a una IA un comentario en prosa sobre un
/// [MonthlyReport] ya calculado. A diferencia de [ChatGateway], esto es
/// una sola llamada, sin function calling: el [MonthlyReport] que recibe
/// solo tiene cifras agregadas (totales, por categoría, comparación), sin
/// ningún campo para una descripción o un concepto de movimiento — así
/// que ninguna implementación puede filtrar al prompt algo que el tipo ni
/// siquiera transporta.
abstract class MonthlyReportGateway {
  Future<String> explain(MonthlyReport report);
}

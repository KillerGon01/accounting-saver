import 'savings_suggestions_summary.dart';

/// Puerto para pedir a una IA una redacción en prosa de las opciones de
/// ahorro de una meta, a partir de un [SavingsSuggestionsSummary] ya
/// agregado. Igual que [MonthlyReportGateway] (`domain/reports/`), el tipo
/// que recibe no tiene ningún campo de texto libre del usuario: ninguna
/// implementación puede filtrar al prompt un concepto, una descripción o
/// el nombre de la meta, porque el tipo no los transporta.
abstract class SavingsSuggestionsGateway {
  Future<String> explain(SavingsSuggestionsSummary summary);
}

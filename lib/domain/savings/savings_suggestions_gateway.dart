import 'savings_suggestions_summary.dart';

/// Port for asking an AI for a prose write-up of a goal's savings
/// options, from an already-aggregated [SavingsSuggestionsSummary].
/// Same as [MonthlyReportGateway] (`domain/reports/`), the type it
/// receives has no field for the user's free text: no implementation
/// can leak a concept, a description, or the goal's name into the
/// prompt, because the type doesn't carry them.
abstract class SavingsSuggestionsGateway {
  Future<String> explain(SavingsSuggestionsSummary summary);
}

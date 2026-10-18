import '../domain/savings/savings_goal.dart';
import '../domain/savings/savings_goal_progress.dart';
import '../domain/savings/savings_suggestion.dart';
import '../domain/savings/savings_suggestions_summary.dart';
import '../domain/transactions/category.dart';
import 'eval_cases.dart' show evalNow;

/// A `GeminiSavingsSuggestionsGateway` evaluation case: an
/// already-built [SavingsSuggestionsSummary] (never hand-written
/// text) and a [description] only for the report.
///
/// Unlike `EvalCase` (chat), no account, no Firestore transaction,
/// and no conversation are needed here: the gateway is a single
/// call with no function calling over a summary already computed in
/// memory (see `GeminiSavingsSuggestionsGateway`), so the evaluation
/// case is, directly, that summary.
class SavingsSuggestionsEvalCase {
  const SavingsSuggestionsEvalCase({required this.id, required this.description, required this.summary});

  final String id;
  final String description;
  final SavingsSuggestionsSummary summary;
}

/// Builds [goal]/[suggestions]'s summary with
/// [summarizeSavingsSuggestions], the same as the real suggestions
/// sheet does — never by hand.
SavingsSuggestionsSummary _summaryOf({required SavingsGoal goal, required List<SavingsSuggestion> suggestions}) {
  final progress = calculateSavingsGoalProgress(goal, now: evalNow);
  final result = SavingsSuggestionsResult(
    suggestions: suggestions,
    monthlyCoveredCents: suggestions
        .where((s) => s.type != SavingsSuggestionType.oneOffExcess)
        .fold(0, (sum, s) => sum + s.amountCents),
  );
  return summarizeSavingsSuggestions(goal: goal, progress: progress, suggestions: result);
}

SavingsGoal _goal({
  required String id,
  required int targetCents,
  required int savedCents,
  required int monthsAhead,
}) {
  return SavingsGoal(
    id: id,
    name: 'Meta de evaluación',
    targetCents: targetCents,
    savedCents: savedCents,
    deadline: DateTime(evalNow.year, evalNow.month + monthsAhead, evalNow.day),
    createdAt: evalNow,
  );
}

/// The 5 evaluation cases (see docs/evaluation.md, "Sugerencias de
/// ahorro con IA"). The descriptions of the fabricated recurring
/// expenses/one-off excesses ("Netflix", "Spotify", "Gimnasio") are,
/// on purpose, the same concepts
/// `savingsSuggestionsForbiddenConcepts` forbids in the response
/// (see `savings_suggestions_eval_grading.dart`): this way it's
/// proven in code, not just assumed, that those concepts never
/// reach the summary the model sees (`SavingsSuggestionsSummary`
/// has no field for them — see
/// `test/eval/savings_suggestions_eval_cases_test.dart`), even
/// though they do exist in the source data.
List<SavingsSuggestionsEvalCase> buildSavingsSuggestionsEvalCases() {
  return [
    // (a) Demanding goal, partial coverage: €3,000 in 6 months
    // (required contribution €500.00/month), options that cover
    // €74.64/month (€58.98 recurring + €15.66 cut) and a one-off
    // excess of €141.00 (doesn't count toward coverage).
    SavingsSuggestionsEvalCase(
      id: 'savings-a-parcial-exigente',
      description: 'Meta exigente (3.000 €/6 meses) con cobertura parcial y un exceso puntual',
      summary: _summaryOf(
        goal: _goal(id: 'eval-savings-a', targetCents: 300000, savedCents: 0, monthsAhead: 6),
        suggestions: const [
          SavingsSuggestion(
            type: SavingsSuggestionType.recurring,
            amountCents: 1966,
            description: 'netflix',
            categoryId: Category.suscripciones,
          ),
          SavingsSuggestion(
            type: SavingsSuggestionType.recurring,
            amountCents: 1966,
            description: 'spotify',
            categoryId: Category.suscripciones,
          ),
          SavingsSuggestion(
            type: SavingsSuggestionType.recurring,
            amountCents: 1966,
            description: 'gimnasio',
            categoryId: Category.suscripciones,
          ),
          SavingsSuggestion(type: SavingsSuggestionType.categoryCut, amountCents: 1566, categoryId: Category.ocio),
          SavingsSuggestion(
            type: SavingsSuggestionType.oneOffExcess,
            amountCents: 14100,
            description: 'Concierto',
            categoryId: Category.ocio,
          ),
        ],
      ),
    ),

    // (b) Small goal, sufficient coverage: €100 in 11 months
    // (required contribution €9.10/month), one option of
    // €15.00/month. No one-off excess.
    SavingsSuggestionsEvalCase(
      id: 'savings-b-suficiente-pequena',
      description: 'Meta pequeña (100 €/11 meses) con cobertura suficiente, sin exceso puntual',
      summary: _summaryOf(
        goal: _goal(id: 'eval-savings-b', targetCents: 10000, savedCents: 0, monthsAhead: 11),
        suggestions: const [
          SavingsSuggestion(
            type: SavingsSuggestionType.recurring,
            amountCents: 1500,
            description: 'netflix',
            categoryId: Category.suscripciones,
          ),
        ],
      ),
    ),

    // (c) Zero coverage: no option computed at all (no recurring,
    // no cuts, no one-off excesses).
    SavingsSuggestionsEvalCase(
      id: 'savings-c-sin-opciones',
      description: 'Meta sin ninguna opción de ahorro calculada',
      summary: _summaryOf(
        goal: _goal(id: 'eval-savings-c', targetCents: 50000, savedCents: 0, monthsAhead: 4),
        suggestions: const [],
      ),
    ),

    // (d) No one-off excess: recurring and cut present (partial
    // coverage), but no one-off excess this month.
    SavingsSuggestionsEvalCase(
      id: 'savings-d-sin-exceso-puntual',
      description: 'Recurrente y recorte presentes, cobertura parcial, sin exceso puntual',
      summary: _summaryOf(
        goal: _goal(id: 'eval-savings-d', targetCents: 50000, savedCents: 0, monthsAhead: 5),
        suggestions: const [
          SavingsSuggestion(
            type: SavingsSuggestionType.recurring,
            amountCents: 2500,
            description: 'gimnasio',
            categoryId: Category.otros,
          ),
          SavingsSuggestion(type: SavingsSuggestionType.categoryCut, amountCents: 1500, categoryId: Category.transporte),
        ],
      ),
    ),

    // (e) All three options at once, in different categories, with
    // sufficient coverage.
    SavingsSuggestionsEvalCase(
      id: 'savings-e-mezcla-completa',
      description: 'Recurrentes, recortes y exceso puntual a la vez, cobertura suficiente',
      summary: _summaryOf(
        goal: _goal(id: 'eval-savings-e', targetCents: 120000, savedCents: 20000, monthsAhead: 4),
        suggestions: const [
          SavingsSuggestion(
            type: SavingsSuggestionType.recurring,
            amountCents: 1966,
            description: 'netflix',
            categoryId: Category.suscripciones,
          ),
          SavingsSuggestion(
            type: SavingsSuggestionType.recurring,
            amountCents: 1966,
            description: 'spotify',
            categoryId: Category.suscripciones,
          ),
          SavingsSuggestion(type: SavingsSuggestionType.categoryCut, amountCents: 3000, categoryId: Category.restaurantes),
          SavingsSuggestion(
            type: SavingsSuggestionType.oneOffExcess,
            amountCents: 8000,
            description: 'Regalo de cumpleaños',
            categoryId: Category.otros,
          ),
        ],
      ),
    ),
  ];
}

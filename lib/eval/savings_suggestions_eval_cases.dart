import '../domain/savings/savings_goal.dart';
import '../domain/savings/savings_goal_progress.dart';
import '../domain/savings/savings_suggestion.dart';
import '../domain/savings/savings_suggestions_summary.dart';
import '../domain/transactions/category.dart';
import 'eval_cases.dart' show evalNow;

/// Un caso de evaluación de `GeminiSavingsSuggestionsGateway`: un
/// [SavingsSuggestionsSummary] ya construido (nunca texto escrito a mano)
/// y una [description] solo para el informe.
///
/// A diferencia de `EvalCase` (chat), aquí no hace falta ninguna cuenta,
/// ningún movimiento en Firestore ni ninguna conversación: el gateway es
/// una sola llamada sin function calling sobre un resumen ya calculado en
/// memoria (ver `GeminiSavingsSuggestionsGateway`), así que el caso de
/// evaluación es, directamente, ese resumen.
class SavingsSuggestionsEvalCase {
  const SavingsSuggestionsEvalCase({required this.id, required this.description, required this.summary});

  final String id;
  final String description;
  final SavingsSuggestionsSummary summary;
}

/// Construye el resumen de [goal]/[suggestions] con [summarizeSavingsSuggestions],
/// igual que hace la hoja de sugerencias de verdad — nunca a mano.
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

/// Los 5 casos de evaluación (ver docs/evaluation.md, "Sugerencias de
/// ahorro con IA"). Las descripciones de los recurrentes/excesos
/// puntuales fabricados ("Netflix", "Spotify", "Gimnasio") son, a
/// propósito, los mismos conceptos que
/// `savingsSuggestionsForbiddenConcepts` prohíbe en la respuesta (ver
/// `savings_suggestions_eval_grading.dart`): así queda probado en código,
/// no solo supuesto, que esos conceptos nunca llegan al resumen que ve el
/// modelo (`SavingsSuggestionsSummary` no tiene ningún campo para ellos —
/// ver `test/eval/savings_suggestions_eval_cases_test.dart`), aunque sí
/// existan en los datos de partida.
List<SavingsSuggestionsEvalCase> buildSavingsSuggestionsEvalCases() {
  return [
    // (a) Meta exigente, cobertura parcial: 3.000 € en 6 meses (aportación
    // necesaria 500,00 €/mes), opciones que cubren 74,64 €/mes (58,98 €
    // de recurrentes + 15,66 € de recorte) y un exceso puntual de 141,00 €
    // (no cuenta para la cobertura).
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

    // (b) Meta pequeña, cobertura suficiente: 100 € en 11 meses
    // (aportación necesaria 9,10 €/mes), una opción de 15,00 €/mes. Sin
    // exceso puntual.
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

    // (c) Cobertura cero: sin ninguna opción calculada (ni recurrentes,
    // ni recortes, ni excesos puntuales).
    SavingsSuggestionsEvalCase(
      id: 'savings-c-sin-opciones',
      description: 'Meta sin ninguna opción de ahorro calculada',
      summary: _summaryOf(
        goal: _goal(id: 'eval-savings-c', targetCents: 50000, savedCents: 0, monthsAhead: 4),
        suggestions: const [],
      ),
    ),

    // (d) Sin exceso puntual: recurrente y recorte presentes (cobertura
    // parcial), pero ningún exceso puntual este mes.
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

    // (e) Las tres opciones a la vez, en categorías distintas, con
    // cobertura suficiente.
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

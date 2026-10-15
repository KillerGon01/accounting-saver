import '../../domain/common/transactions_change_notifier.dart';
import '../../domain/savings/savings_goal.dart';
import '../../domain/savings/savings_goal_progress.dart';
import '../../domain/savings/savings_suggestion.dart';
import '../../domain/savings/savings_suggestions_gateway.dart';
import '../../domain/savings/savings_suggestions_summary.dart';
import '../../domain/transactions/llm_gateway_exception.dart';

/// Pide a la IA una redacción de las opciones de ahorro de una meta ya
/// calculadas (ver `calculateSavingsSuggestions`/`summarizeSavingsSuggestions`),
/// con el mismo patrón de cuota que `ExplainMonthlyReport`: como mucho
/// [maxExplanationsPerSession] llamadas con éxito por sesión (una
/// instancia), caché en memoria por meta y ninguna llamada simultánea.
class ExplainSavingsSuggestions {
  ExplainSavingsSuggestions(this._gateway, [TransactionsChangeNotifier? changeNotifier])
    : _changeNotifier = changeNotifier ?? TransactionsChangeNotifier();

  /// Mismo valor que `ExplainMonthlyReport.maxCommentsPerSession`: mismo
  /// cupo diario compartido de Gemini, mismo criterio.
  static const maxExplanationsPerSession = 6;

  final SavingsSuggestionsGateway _gateway;
  final TransactionsChangeNotifier _changeNotifier;
  final _cache = <String, _CachedExplanation>{};

  bool _isGenerating = false;
  int _explanationsGenerated = 0;

  /// Resúmenes que quedan en esta sesión antes de llegar a
  /// [maxExplanationsPerSession]. Nunca negativo.
  int get remainingExplanations =>
      (maxExplanationsPerSession - _explanationsGenerated).clamp(0, maxExplanationsPerSession);

  /// [suggestions] ya calculadas (ver `BuildSavingsSuggestions`, llamado
  /// desde la pantalla, no desde aquí): este caso de uso no vuelve a leer
  /// Firestore, solo redacta sobre lo que ya se le pasa.
  Future<String> call({
    required SavingsGoal goal,
    required SavingsGoalProgress progress,
    required SavingsSuggestionsResult suggestions,
  }) async {
    if (_isGenerating) {
      throw StateError('Ya hay una petición de resumen en curso.');
    }
    if (_explanationsGenerated >= maxExplanationsPerSession) {
      throw const LlmGatewayException(
        'explanation-limit-reached',
        message: 'Has llegado al máximo de resúmenes de esta sesión.',
      );
    }

    _isGenerating = true;
    try {
      final cached = _cache[goal.id];
      // Invalidada si cambian los movimientos (`transactionsVersion`) o la
      // propia meta (`savedCents`/`targetCents`/`deadline`): comparación
      // explícita campo a campo, no implícita en la igualdad de un
      // resumen ya construido, para que quede claro de qué depende la
      // caché sin tener que leer `summarizeSavingsSuggestions`.
      if (cached != null &&
          cached.transactionsVersion == _changeNotifier.version &&
          cached.savedCents == goal.savedCents &&
          cached.targetCents == goal.targetCents &&
          cached.deadline == goal.deadline) {
        return cached.explanation;
      }

      final summary = summarizeSavingsSuggestions(goal: goal, progress: progress, suggestions: suggestions);
      final explanation = await _gateway.explain(summary);

      // Solo se cuenta aquí, tras una llamada al modelo que ha terminado
      // con éxito: ni el acierto de caché de arriba ni un error más abajo
      // (que se propaga sin pasar por esta línea) gastan un resumen.
      _explanationsGenerated++;
      _cache[goal.id] = _CachedExplanation(
        explanation,
        transactionsVersion: _changeNotifier.version,
        savedCents: goal.savedCents,
        targetCents: goal.targetCents,
        deadline: goal.deadline,
      );
      return explanation;
    } finally {
      _isGenerating = false;
    }
  }
}

class _CachedExplanation {
  _CachedExplanation(
    this.explanation, {
    required this.transactionsVersion,
    required this.savedCents,
    required this.targetCents,
    required this.deadline,
  });

  final String explanation;
  final int transactionsVersion;
  final int savedCents;
  final int targetCents;
  final DateTime deadline;
}

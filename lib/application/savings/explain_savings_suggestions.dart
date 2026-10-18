import '../../domain/common/transactions_change_notifier.dart';
import '../../domain/savings/savings_goal.dart';
import '../../domain/savings/savings_goal_progress.dart';
import '../../domain/savings/savings_suggestion.dart';
import '../../domain/savings/savings_suggestions_gateway.dart';
import '../../domain/savings/savings_suggestions_summary.dart';
import '../../domain/transactions/llm_gateway_exception.dart';

/// Asks the AI for a write-up of a goal's already-computed savings
/// options (see `calculateSavingsSuggestions`/`summarizeSavingsSuggestions`),
/// with the same quota pattern as `ExplainMonthlyReport`: at most
/// [maxExplanationsPerSession] successful calls per session (one
/// instance), an in-memory cache per goal, and no simultaneous calls.
class ExplainSavingsSuggestions {
  ExplainSavingsSuggestions(this._gateway, [TransactionsChangeNotifier? changeNotifier])
    : _changeNotifier = changeNotifier ?? TransactionsChangeNotifier();

  /// Same value as `ExplainMonthlyReport.maxCommentsPerSession`: same
  /// shared daily Gemini quota, same criterion.
  static const maxExplanationsPerSession = 6;

  final SavingsSuggestionsGateway _gateway;
  final TransactionsChangeNotifier _changeNotifier;
  final _cache = <String, _CachedExplanation>{};

  bool _isGenerating = false;
  int _explanationsGenerated = 0;

  /// Write-ups left in this session before reaching
  /// [maxExplanationsPerSession]. Never negative.
  int get remainingExplanations =>
      (maxExplanationsPerSession - _explanationsGenerated).clamp(0, maxExplanationsPerSession);

  /// [suggestions] already computed (see `BuildSavingsSuggestions`,
  /// called from the screen, not from here): this use case doesn't
  /// read Firestore again, it only writes up what's already passed to
  /// it.
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
      // Invalidated if the transactions change (`transactionsVersion`)
      // or the goal itself does (`savedCents`/`targetCents`/`deadline`):
      // explicit field-by-field comparison, not implicit in an
      // already-built summary's equality, so it's clear what the
      // cache depends on without having to read
      // `summarizeSavingsSuggestions`.
      if (cached != null &&
          cached.transactionsVersion == _changeNotifier.version &&
          cached.savedCents == goal.savedCents &&
          cached.targetCents == goal.targetCents &&
          cached.deadline == goal.deadline) {
        return cached.explanation;
      }

      final summary = summarizeSavingsSuggestions(goal: goal, progress: progress, suggestions: suggestions);
      final explanation = await _gateway.explain(summary);

      // Only counted here, after a model call that has succeeded:
      // neither the cache hit above nor an error below (which
      // propagates without passing through this line) spend a write-up.
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

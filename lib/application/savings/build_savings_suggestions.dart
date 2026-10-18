import '../../domain/common/clock.dart';
import '../../domain/savings/savings_suggestion.dart';
import '../../domain/transactions/transaction.dart';
import '../../domain/transactions/transaction_repository.dart';
import '../reports/build_month_end_forecast.dart';

/// Computes a goal's savings options (see
/// `calculateSavingsSuggestions`) from the history of the previous
/// `BuildMonthEndForecast.recurringExpensesMonths` full months and
/// what's registered in the current month — the same window, and with
/// the same safety cap (`BuildMonthEndForecast.maxFetchLimit`), that
/// `BuildMonthEndForecast`/`BuildUnusualExpenses` already use.
///
/// Called on demand, when pressing a goal's "¿De dónde puedo ahorrar?"
/// button, not when opening the goals screen: **adds 2 queries to
/// Firestore per sheet opening** (the same two, history and current
/// month, that `BuildUnusualExpenses` already makes — it doesn't share
/// its results, same tradeoff already accepted among the monthly
/// report's use cases, see docs/design.md).
class BuildSavingsSuggestions {
  BuildSavingsSuggestions(this._repository, [Clock clock = const SystemClock()]) : _clock = clock;

  final TransactionRepository _repository;
  final Clock _clock;

  Future<SavingsSuggestionsResult> call({required String userId, DateTime? now}) async {
    final effectiveNow = now ?? _clock.now();
    final monthStart = DateTime(effectiveNow.year, effectiveNow.month);
    final nextMonthStart = DateTime(effectiveNow.year, effectiveNow.month + 1);
    final windowStart = DateTime(
      effectiveNow.year,
      effectiveNow.month - BuildMonthEndForecast.recurringExpensesMonths,
    );

    final history = await _fetch(userId: userId, start: windowStart, end: monthStart);
    final current = await _fetch(userId: userId, start: monthStart, end: nextMonthStart);

    final result = calculateSavingsSuggestions(
      historyTransactions: history.transactions,
      currentMonthTransactions: current.transactions,
    );
    return result.copyWith(truncated: history.truncated || current.truncated);
  }

  Future<_Fetch> _fetch({required String userId, required DateTime start, required DateTime end}) async {
    final transactions = await _repository.findByDateRange(
      userId: userId,
      start: start,
      end: end,
      limit: BuildMonthEndForecast.maxFetchLimit + 1,
    );
    final truncated = transactions.length > BuildMonthEndForecast.maxFetchLimit;
    return _Fetch(truncated ? transactions.sublist(0, BuildMonthEndForecast.maxFetchLimit) : transactions, truncated);
  }
}

class _Fetch {
  _Fetch(this.transactions, this.truncated);

  final List<Transaction> transactions;
  final bool truncated;
}

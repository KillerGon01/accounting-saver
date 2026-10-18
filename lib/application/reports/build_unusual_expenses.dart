import '../../domain/common/clock.dart';
import '../../domain/reports/unusual_expenses.dart';
import '../../domain/transactions/transaction.dart';
import '../../domain/transactions/transaction_repository.dart';
import 'build_month_end_forecast.dart';

/// Computes the current month's unusual expenses (see
/// `detectUnusualExpenses`) from the history of the previous
/// `BuildMonthEndForecast.recurringExpensesMonths` full months — the
/// same window, and with the same safety cap
/// (`BuildMonthEndForecast.maxFetchLimit`), that `BuildMonthEndForecast`
/// already uses to detect recurring expenses. Only makes sense for the
/// current month: for any other month, [call] returns `null` without
/// querying anything — same as `BuildMonthEndForecast`.
///
/// **Doesn't share the same Firestore read as `BuildMonthEndForecast`**,
/// even though it requests the same date range: it makes its own two
/// queries (see docs/design.md, "Riesgos" — same tradeoff already
/// accepted between `BuildMonthlyReport` and `BuildMonthEndForecast`;
/// the current month's report goes from 4 to 6 queries per screen load
/// with this function active).
class BuildUnusualExpenses {
  BuildUnusualExpenses(this._repository, [Clock clock = const SystemClock()]) : _clock = clock;

  final TransactionRepository _repository;
  final Clock _clock;

  /// [now] optional, same as `BuildMonthEndForecast.call`.
  Future<UnusualExpensesResult?> call({
    required String userId,
    required int year,
    required int month,
    DateTime? now,
  }) async {
    final effectiveNow = now ?? _clock.now();
    final isCurrentMonth = effectiveNow.year == year && effectiveNow.month == month;
    if (!isCurrentMonth) return null;

    final monthStart = DateTime(year, month);
    final nextMonthStart = DateTime(year, month + 1);
    final windowStart = DateTime(year, month - BuildMonthEndForecast.recurringExpensesMonths);

    final history = await _fetch(userId: userId, start: windowStart, end: monthStart);
    final current = await _fetch(userId: userId, start: monthStart, end: nextMonthStart);

    final expenses = detectUnusualExpenses(
      currentMonthTransactions: current.transactions,
      historyTransactions: history.transactions,
    );

    return UnusualExpensesResult(
      expenses: expenses,
      truncated: history.truncated || current.truncated,
    );
  }

  Future<_Fetch> _fetch({required String userId, required DateTime start, required DateTime end}) async {
    final transactions = await _repository.findByDateRange(
      userId: userId,
      start: start,
      end: end,
      limit: BuildMonthEndForecast.maxFetchLimit + 1,
    );
    final truncated = transactions.length > BuildMonthEndForecast.maxFetchLimit;
    return _Fetch(
      truncated ? transactions.sublist(0, BuildMonthEndForecast.maxFetchLimit) : transactions,
      truncated,
    );
  }
}

class _Fetch {
  _Fetch(this.transactions, this.truncated);

  final List<Transaction> transactions;
  final bool truncated;
}

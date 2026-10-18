import '../../domain/common/clock.dart';
import '../../domain/reports/month_end_forecast.dart';
import '../../domain/transactions/monthly_summary.dart';
import '../../domain/transactions/recurring_expenses.dart';
import '../../domain/transactions/transaction.dart';
import '../../domain/transactions/transaction_repository.dart';

/// Computes the month-end forecast (see `MonthEndForecast`) from the
/// recurring expenses of the previous 3 full months and what's already
/// registered this month. Only makes sense for the current month: for
/// any other month, [call] returns `null` without querying anything.
class BuildMonthEndForecast {
  BuildMonthEndForecast(this._repository, [Clock clock = const SystemClock()]) : _clock = clock;

  /// How many previous full months are analyzed to detect a recurring
  /// expense, same as `TransactionChatFunctions.recurringExpensesMonths`
  /// (same criterion, two names because they're two separate use cases
  /// that don't share a class).
  static const recurringExpensesMonths = 3;

  /// Same cap as `BuildMonthlyReport.maxFetchLimit`: a safety measure,
  /// not a limit expected to be reached in normal use.
  static const maxFetchLimit = 2000;

  final TransactionRepository _repository;
  final Clock _clock;

  /// [now] optional, same as `BuildMonthlyReport.call`: so whoever
  /// already has a resolved `now` doesn't have to go through a second
  /// `Clock`.
  Future<MonthEndForecast?> call({
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
    final windowStart = DateTime(year, month - recurringExpensesMonths);
    final lastDayOfMonth = nextMonthStart.subtract(const Duration(days: 1)).day;
    final today = effectiveNow.day;

    final previousMonthsFetch = await _fetch(userId: userId, start: windowStart, end: monthStart);
    final currentMonthFetch = await _fetch(userId: userId, start: monthStart, end: nextMonthStart);

    final recurring = findRecurringExpenses(previousMonthsFetch.transactions);

    final registeredThisMonth = <({String description, int amountCentsAbs})>{};
    for (final transaction in currentMonthFetch.transactions) {
      if (transaction.amountCents >= 0) continue;
      registeredThisMonth.add((
        description: normalizeExpenseDescription(transaction.description),
        amountCentsAbs: -transaction.amountCents,
      ));
    }

    final pending = <PendingRecurringExpense>[];
    final overdue = <PendingRecurringExpense>[];
    for (final expense in recurring) {
      final key = (description: expense.description, amountCentsAbs: expense.amountCentsAbs);
      if (registeredThisMonth.contains(key)) continue;

      final usualDay = expense.mostRecentDay.clamp(1, lastDayOfMonth);
      final item = PendingRecurringExpense(
        description: expense.description,
        amountCentsAbs: expense.amountCentsAbs,
        usualDay: usualDay,
      );
      if (usualDay > today) {
        pending.add(item);
      } else {
        overdue.add(item);
      }
    }

    final summary = MonthlySummary.fromTransactions(currentMonthFetch.transactions);
    final pendingTotalCents = pending.fold(0, (sum, p) => sum + p.amountCentsAbs);

    return MonthEndForecast(
      year: year,
      month: month,
      accumulatedExpenseCents: summary.expenseCents,
      pendingRecurringExpenses: pending,
      overdueUnregisteredExpenses: overdue,
      forecastExpenseCents: summary.expenseCents + pendingTotalCents,
      registeredIncomeCents: summary.incomeCents,
      truncated: previousMonthsFetch.truncated || currentMonthFetch.truncated,
    );
  }

  Future<_Fetch> _fetch({required String userId, required DateTime start, required DateTime end}) async {
    final transactions = await _repository.findByDateRange(
      userId: userId,
      start: start,
      end: end,
      limit: maxFetchLimit + 1,
    );
    final truncated = transactions.length > maxFetchLimit;
    return _Fetch(truncated ? transactions.sublist(0, maxFetchLimit) : transactions, truncated);
  }
}

class _Fetch {
  _Fetch(this.transactions, this.truncated);

  final List<Transaction> transactions;
  final bool truncated;
}

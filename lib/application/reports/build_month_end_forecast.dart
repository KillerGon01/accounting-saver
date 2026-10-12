import '../../domain/common/clock.dart';
import '../../domain/reports/month_end_forecast.dart';
import '../../domain/transactions/monthly_summary.dart';
import '../../domain/transactions/recurring_expenses.dart';
import '../../domain/transactions/transaction.dart';
import '../../domain/transactions/transaction_repository.dart';

/// Calcula la previsión de fin de mes (ver `MonthEndForecast`) a partir de
/// los gastos recurrentes de los 3 meses anteriores completos y de lo ya
/// registrado este mes. Solo tiene sentido para el mes en curso: para
/// cualquier otro mes, [call] devuelve `null` sin consultar nada.
class BuildMonthEndForecast {
  BuildMonthEndForecast(this._repository, [Clock clock = const SystemClock()]) : _clock = clock;

  /// Cuántos meses anteriores completos se analizan para detectar un
  /// recurrente, igual que `TransactionChatFunctions.recurringExpensesMonths`
  /// (mismo criterio, dos nombres porque son dos casos de uso distintos
  /// que no comparten clase).
  static const recurringExpensesMonths = 3;

  /// Mismo tope que `BuildMonthlyReport.maxFetchLimit`: una medida de
  /// seguridad, no un límite que se espere alcanzar en el uso normal.
  static const maxFetchLimit = 2000;

  final TransactionRepository _repository;
  final Clock _clock;

  /// [now] opcional, igual que `BuildMonthlyReport.call`: para que quien ya
  /// tiene un `now` resuelto no tenga que pasar por un segundo `Clock`.
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

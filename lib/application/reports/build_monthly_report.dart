import '../../domain/common/clock.dart';
import '../../domain/reports/monthly_report.dart';
import '../../domain/transactions/category.dart';
import '../../domain/transactions/monthly_summary.dart';
import '../../domain/transactions/transaction.dart';
import '../../domain/transactions/transaction_repository.dart';

/// Computes a month's [MonthlyReport] from the user's transactions:
/// one query per month (this one and the previous one) with
/// `findByDateRange`, filtering by date only — everything else
/// (totals, expense by category, comparison) is computed here, in
/// code, in cents.
class BuildMonthlyReport {
  BuildMonthlyReport(this._repository, [Clock clock = const SystemClock()]) : _clock = clock;

  /// Cap on transactions read per query (this month or the previous
  /// one), same as `TransactionChatFunctions.maxFetchLimit`: a safety
  /// measure, not a limit ever expected to be reached in a person's
  /// normal use.
  static const maxFetchLimit = 2000;

  final TransactionRepository _repository;
  final Clock _clock;

  /// [now] is only used to decide [MonthlyReport.isCurrentMonth] and
  /// [MonthlyReport.elapsedDays]. It's optional (if not passed, the
  /// constructor's `Clock` is used, as always) so whoever already has
  /// a `now` resolved for the whole request (for example, the chat:
  /// see `TransactionChatFunctions`) can pass it without this use case
  /// having to keep a second clock for the same purpose.
  Future<MonthlyReport> call({
    required String userId,
    required int year,
    required int month,
    DateTime? now,
  }) async {
    final start = DateTime(year, month);
    final end = DateTime(year, month + 1);
    final previousStart = DateTime(year, month - 1);

    final current = await _fetch(userId: userId, start: start, end: end);
    final previous = await _fetch(userId: userId, start: previousStart, end: start);

    final summary = MonthlySummary.fromTransactions(current.transactions);
    final categoryBreakdown = _breakdownByCategory(current.transactions, summary.expenseCents);

    final comparison = previous.transactions.isEmpty
        ? null
        : _buildComparison(
            current: categoryBreakdown,
            currentExpenseCents: summary.expenseCents,
            previousTransactions: previous.transactions,
          );

    final effectiveNow = now ?? _clock.now();
    final isCurrentMonth = effectiveNow.year == year && effectiveNow.month == month;

    return MonthlyReport(
      year: year,
      month: month,
      incomeCents: summary.incomeCents,
      expenseCents: summary.expenseCents,
      transactionCount: current.transactions.length,
      categoryBreakdown: categoryBreakdown,
      comparison: comparison,
      truncated: current.truncated || previous.truncated,
      isCurrentMonth: isCurrentMonth,
      elapsedDays: isCurrentMonth ? effectiveNow.day : null,
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

  List<CategoryExpense> _breakdownByCategory(List<Transaction> transactions, int totalExpenseCents) {
    if (totalExpenseCents == 0) return const [];

    final amountsByCategory = <Category, int>{};
    for (final transaction in transactions) {
      if (!transaction.isExpense) continue;
      final amount = -transaction.amountCents;
      amountsByCategory[transaction.categoryId] = (amountsByCategory[transaction.categoryId] ?? 0) + amount;
    }

    final breakdown = [
      for (final entry in amountsByCategory.entries)
        CategoryExpense(
          category: entry.key,
          amountCents: entry.value,
          percentageOfExpense: entry.value / totalExpenseCents * 100,
        ),
    ];
    breakdown.sort((a, b) => b.amountCents.compareTo(a.amountCents));
    return breakdown;
  }

  /// Delegates the arithmetic to [compareCategoryBreakdowns] (domain
  /// layer): this method only converts the previous month's
  /// transactions into its own breakdown by category, with the same
  /// `_breakdownByCategory` already used for the current month, so as
  /// not to have two different ways of summing by category within the
  /// same class.
  MonthlyComparison _buildComparison({
    required List<CategoryExpense> current,
    required int currentExpenseCents,
    required List<Transaction> previousTransactions,
  }) {
    final previousSummary = MonthlySummary.fromTransactions(previousTransactions);
    final previousBreakdown = _breakdownByCategory(previousTransactions, previousSummary.expenseCents);
    return compareCategoryBreakdowns(
      currentBreakdown: current,
      currentExpenseCents: currentExpenseCents,
      previousBreakdown: previousBreakdown,
      previousExpenseCents: previousSummary.expenseCents,
    );
  }
}

class _Fetch {
  _Fetch(this.transactions, this.truncated);

  final List<Transaction> transactions;
  final bool truncated;
}

import '../../../domain/common/money_formatting.dart';
import '../../../domain/transactions/recurring_expenses.dart';
import '../../../domain/transactions/transaction_repository.dart';
import '../../reports/build_monthly_report.dart';
import 'shared.dart';

/// `getMonthlySummary`, `getCategoryBreakdown` and `recurringExpenses`:
/// every chat function that summarizes a single month (or, for
/// `recurringExpenses`, a few of them) rather than listing individual
/// transactions or comparing two months.
class BreakdownFunctions {
  /// [buildMonthlyReport] is optional only so as not to force every
  /// test that doesn't need one to build one; in the app, the same
  /// `BuildMonthlyReport` the monthly report already uses is always
  /// passed (see `chat_providers.dart`), so `getCategoryBreakdown` is,
  /// byte for byte, the same source of truth as the report screen
  /// (see docs/design.md: the chat used to improvise its own
  /// per-category calculation from `listTransactions`, which produced
  /// figures different from the report's).
  BreakdownFunctions(TransactionRepository repository, [BuildMonthlyReport? buildMonthlyReport])
    : _repository = repository,
      _buildMonthlyReport = buildMonthlyReport ?? BuildMonthlyReport(repository);

  final TransactionRepository _repository;
  final BuildMonthlyReport _buildMonthlyReport;

  Future<Map<String, Object?>> getMonthlySummary({
    required String userId,
    required Map<String, Object?> arguments,
    required DateTime now,
  }) async {
    final yearRaw = asInt(arguments['year']);
    final monthRaw = asInt(arguments['month']);
    final error = yearMonthError(yearRaw, monthRaw, now);
    if (error != null) return error;
    final year = yearRaw!;
    final month = monthRaw!;

    final start = DateTime(year, month);
    final end = DateTime(year, month + 1);
    final fetch = await fetchRange(repository: _repository, userId: userId, start: start, end: end);
    final totals = sumIncomeAndExpense(fetch.transactions);

    return {
      'year': year,
      'month': month,
      'incomeCents': totals.incomeCents,
      'expenseCents': totals.expenseCents,
      'balanceCents': totals.incomeCents - totals.expenseCents,
      if (fetch.safetyLimitReached) ...safetyLimitWarning(),
    };
  }

  /// A month's expense breakdown by category, computed by
  /// [BuildMonthlyReport] (the same source of truth as the monthly
  /// report: see docs/design.md), not by the model. `rankingLines` is
  /// the breakdown already written in plain text ("1. Hogar: 938,90 €
  /// (62,2 %)", from highest to lowest expense) for the model to copy
  /// as-is in rankings; `categories` is the same data raw, in case a
  /// specific value is needed that isn't in a line.
  Future<Map<String, Object?>> getCategoryBreakdown({
    required String userId,
    required Map<String, Object?> arguments,
    required DateTime now,
  }) async {
    final yearRaw = asInt(arguments['year']);
    final monthRaw = asInt(arguments['month']);
    final error = yearMonthError(yearRaw, monthRaw, now);
    if (error != null) return error;
    final year = yearRaw!;
    final month = monthRaw!;

    final report = await _buildMonthlyReport(userId: userId, year: year, month: month, now: now);

    final categories = <Map<String, Object?>>[];
    final rankingLines = <String>[];
    for (var i = 0; i < report.categoryBreakdown.length; i++) {
      final expense = report.categoryBreakdown[i];
      final percentage = roundTo1Decimal(expense.percentageOfExpense);
      categories.add({
        'categoryId': expense.category.name,
        'amountCents': expense.amountCents,
        'percentageOfExpense': percentage,
      });
      rankingLines.add(
        '${i + 1}. ${categoryLabel(expense.category)}: '
        '${formatEurosWithSymbol(expense.amountCents)} (${formatPercent(percentage)})',
      );
    }

    if (report.isCurrentMonth) {
      rankingLines.insert(0, currentMonthWarning(report));
    }

    return {
      'year': year,
      'month': month,
      'totalExpenseCents': report.expenseCents,
      'categories': categories,
      'rankingLines': rankingLines,
      'isCurrentMonth': report.isCurrentMonth,
      if (report.isCurrentMonth) 'elapsedDays': report.elapsedDays,
      if (categories.isEmpty) 'note': 'No hay ningún gasto registrado en ese mes.',
      if (report.truncated) ...safetyLimitWarning(),
    };
  }

  /// An expense is recurring if, with the same normalized description
  /// (lowercase and no extra spaces) and the same exact amount, it
  /// appears in 2 or more distinct months within the analyzed range.
  /// A deterministic definition, computed in code by
  /// [findRecurringExpenses] (domain layer, shared with
  /// `BuildMonthEndForecast` — see docs/design.md, "Previsión de fin
  /// de mes"): the model doesn't decide what counts as recurring, it
  /// only reads the already-computed list. This function only keeps
  /// each recurring expense's set of months; the day of each
  /// occurrence (which `BuildMonthEndForecast` does use) isn't needed
  /// here.
  Future<Map<String, Object?>> recurringExpenses({required String userId, required DateTime now}) async {
    final thisMonthStart = DateTime(now.year, now.month);
    final start = DateTime(now.year, now.month - ChatFunctionLimits.recurringExpensesMonths);
    final end = thisMonthStart;
    final lastDayAnalyzed = end.subtract(const Duration(days: 1));

    final fetch = await fetchRange(repository: _repository, userId: userId, start: start, end: end);

    final recurringExpenses = findRecurringExpenses(fetch.transactions);
    final recurring = [
      for (final expense in recurringExpenses)
        {
          'description': expense.description,
          'amountEuros': formatEuroAmount(expense.amountCentsAbs),
          'months': (expense.occurrences.map((o) => o.isoMonth).toSet().toList()..sort()),
        },
    ];

    final desde = isoDate(start);
    final hasta = isoDate(lastDayAnalyzed);
    return {
      'desde': desde,
      'hasta': hasta,
      'recurringExpenses': recurring,
      if (recurring.isEmpty)
        'note': 'No se ha encontrado ningún gasto recurrente entre $desde y $hasta.',
      if (fetch.safetyLimitReached) ...safetyLimitWarning(),
    };
  }
}

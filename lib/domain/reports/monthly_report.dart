import '../transactions/category.dart';

/// Monthly report computed from the user's transactions: totals,
/// expense by category, and comparison with the previous month. Pure
/// Dart (no Firebase, no Flutter); `BuildMonthlyReport` (application
/// layer) computes it and the report screen (presentation layer)
/// consumes it.
class MonthlyReport {
  const MonthlyReport({
    required this.year,
    required this.month,
    required this.incomeCents,
    required this.expenseCents,
    required this.transactionCount,
    required this.categoryBreakdown,
    required this.comparison,
    required this.truncated,
    required this.isCurrentMonth,
    required this.elapsedDays,
  });

  final int year;
  final int month;
  final int incomeCents;

  /// Positive magnitude: the total spent, unsigned (same as
  /// `MonthlySummary.expenseCents`).
  final int expenseCents;

  final int transactionCount;

  int get balanceCents => incomeCents - expenseCents;

  /// Expense by category for the month, sorted from highest to lowest
  /// amount. Only includes categories with spending (> 0 cents) in the
  /// month.
  final List<CategoryExpense> categoryBreakdown;

  /// The top 3 categories by spending (or fewer, if there are fewer
  /// than 3 with spending). Derived from [categoryBreakdown], not
  /// stored separately.
  List<CategoryExpense> get topCategories => categoryBreakdown.take(3).toList();

  /// `null` if the previous month has no transactions: there's nothing
  /// to compare against, and no figure is made up (for example, a 100%
  /// drop that doesn't reflect the lack of data).
  final MonthlyComparison? comparison;

  /// `true` if either of the two queries (this month or the previous
  /// one) hit `BuildMonthlyReport.maxFetchLimit` transactions read: the
  /// figures may not reflect the full month.
  final bool truncated;

  /// `true` if this report is for the current month (according to
  /// `BuildMonthlyReport`'s `Clock`), not an already-closed month.
  final bool isCurrentMonth;

  /// Day of the month the data reaches up to, only if [isCurrentMonth]
  /// is `true` (otherwise `null`): a current month never has all its
  /// days yet, so comparing it with a full previous month as if they
  /// were equivalent would be misleading.
  final int? elapsedDays;
}

/// A category's expense for the month, with its percentage of the total
/// spent. The percentage is stored at full precision (not rounded):
/// it's only rounded when displayed (see `report_formatters.dart`).
class CategoryExpense {
  const CategoryExpense({
    required this.category,
    required this.amountCents,
    required this.percentageOfExpense,
  });

  final Category category;

  /// Positive magnitude.
  final int amountCents;

  /// Percentage (0-100) of [amountCents] over the total spent in the
  /// month.
  final double percentageOfExpense;
}

/// Comparison of total and per-category spending between this month
/// and the previous one. Percentage differences are `null` when the
/// comparison base (the previous month's amount) is zero: there's no
/// percentage that isn't made up for "from €0 to €X".
class MonthlyComparison {
  const MonthlyComparison({
    required this.previousExpenseCents,
    required this.expenseDeltaCents,
    required this.expenseDeltaPercent,
    required this.perCategoryDeltas,
  });

  final int previousExpenseCents;

  /// This month's expense minus the previous month's: positive if more
  /// was spent.
  final int expenseDeltaCents;

  final double? expenseDeltaPercent;

  /// Only includes categories with spending this month, the previous
  /// one, or both.
  final Map<Category, CategoryComparison> perCategoryDeltas;
}

class CategoryComparison {
  const CategoryComparison({
    required this.currentAmountCents,
    required this.previousAmountCents,
    required this.deltaCents,
    required this.deltaPercent,
  });

  final int currentAmountCents;
  final int previousAmountCents;
  final int deltaCents;
  final double? deltaPercent;
}

/// Compares the expense by category of two already-computed months
/// (by [BuildMonthlyReport] or equivalent): `currentBreakdown` is the
/// month being evaluated, `previousBreakdown` the comparison's base
/// month (the one that shows up as "before" or "versus" in the
/// result).
///
/// Pure: only depends on each month's already-aggregated breakdown and
/// total, not on the original transactions. That way a single function
/// serves both "this month against the previous one" (the comparison
/// [BuildMonthlyReport] already includes in every report) and comparing
/// any two months (see the chat's `CompareMonths`, in
/// `TransactionChatFunctions`), without duplicating the cents
/// arithmetic in two places.
MonthlyComparison compareCategoryBreakdowns({
  required List<CategoryExpense> currentBreakdown,
  required int currentExpenseCents,
  required List<CategoryExpense> previousBreakdown,
  required int previousExpenseCents,
}) {
  final currentByCategory = {for (final expense in currentBreakdown) expense.category: expense.amountCents};
  final previousByCategory = {for (final expense in previousBreakdown) expense.category: expense.amountCents};
  final categories = {...currentByCategory.keys, ...previousByCategory.keys};

  final perCategoryDeltas = {
    for (final category in categories)
      category: _compareCategoryAmount(currentByCategory[category] ?? 0, previousByCategory[category] ?? 0),
  };

  final expenseDeltaCents = currentExpenseCents - previousExpenseCents;
  return MonthlyComparison(
    previousExpenseCents: previousExpenseCents,
    expenseDeltaCents: expenseDeltaCents,
    expenseDeltaPercent: previousExpenseCents == 0 ? null : expenseDeltaCents / previousExpenseCents * 100,
    perCategoryDeltas: perCategoryDeltas,
  );
}

CategoryComparison _compareCategoryAmount(int currentAmountCents, int previousAmountCents) {
  final deltaCents = currentAmountCents - previousAmountCents;
  return CategoryComparison(
    currentAmountCents: currentAmountCents,
    previousAmountCents: previousAmountCents,
    deltaCents: deltaCents,
    deltaPercent: previousAmountCents == 0 ? null : deltaCents / previousAmountCents * 100,
  );
}

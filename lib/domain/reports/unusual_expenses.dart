import '../transactions/category.dart';
import '../transactions/recurring_expenses.dart';
import '../transactions/transaction.dart';

/// Factor by which an expense's amount must exceed its category's
/// median to count as unusual (see [detectUnusualExpenses]): strictly
/// more than double, not equal to it.
const unusualExpenseFactor = 2;

/// Minimum number of expenses a category needs in the analyzed history
/// for a reliable median to be computed and something flagged. With
/// fewer, any expense would "look" unusual just from having a small
/// sample (see "Límites" in docs/design.md).
const unusualExpenseMinHistoryCount = 4;

/// Full previous months analyzed as history, same as
/// `BuildMonthEndForecast.recurringExpensesMonths` (same criterion,
/// different name because they're two separate use cases that don't
/// share a class).
const unusualExpenseHistoryMonths = 3;

/// An expense in the current month that stands out against its own
/// category's history (see [detectUnusualExpenses]).
class UnusualExpense {
  const UnusualExpense({
    required this.description,
    required this.categoryId,
    required this.amountCentsAbs,
    required this.date,
    required this.categoryMedianCentsAbs,
    required this.categoryHistoryCount,
  });

  /// Exactly as the user wrote it (not normalized: it's for display,
  /// not for comparing — the comparison already happened in
  /// [detectUnusualExpenses]).
  final String description;
  final Category categoryId;

  /// Positive magnitude.
  final int amountCentsAbs;
  final DateTime date;

  /// The median (see [_median]) of the amounts (positive magnitude) of
  /// [categoryId]'s individual expenses in the analyzed history.
  final int categoryMedianCentsAbs;

  /// How many individual expenses of [categoryId] were in that history
  /// (so the card can explain where the comparison comes from).
  final int categoryHistoryCount;
}

/// Result of [detectUnusualExpenses] through a use case that does query
/// Firestore (see `BuildUnusualExpenses`): the list, plus whether any
/// of its queries hit the safety cap.
class UnusualExpensesResult {
  const UnusualExpensesResult({required this.expenses, required this.truncated});

  final List<UnusualExpense> expenses;
  final bool truncated;
}

/// An expense in [currentMonthTransactions] counts as unusual if:
/// - Its category has at least [minHistoryCount] individual expenses in
///   [historyTransactions] (normally the previous 3 full months, see
///   `BuildUnusualExpenses`/`BuildMonthEndForecast`): with fewer,
///   there's no sample big enough to compute a reliable median, so
///   nothing is flagged for that category.
/// - Its amount (magnitude) **strictly** exceeds [factor] times the
///   median of the amounts of those historical expenses in its same
///   category — exactly double doesn't count as unusual.
///
/// Expenses that match a recurring one from [historyTransactions]
/// (same normalized description and exact amount that
/// [findRecurringExpenses] uses, called here with its default
/// `minMonths`, without changing its behavior or its contract) are
/// excluded: an expensive recurring expense (rent, for example) isn't
/// "unusual", it's expected.
///
/// Pure Dart, with no date or repository: deciding which month is "the
/// current month" and which transactions belong to the history is the
/// caller's job (see `BuildUnusualExpenses`).
List<UnusualExpense> detectUnusualExpenses({
  required List<Transaction> currentMonthTransactions,
  required List<Transaction> historyTransactions,
  int factor = unusualExpenseFactor,
  int minHistoryCount = unusualExpenseMinHistoryCount,
}) {
  final recurringKeys = <({String description, int amountCentsAbs})>{
    for (final recurring in findRecurringExpenses(historyTransactions))
      (description: recurring.description, amountCentsAbs: recurring.amountCentsAbs),
  };

  final historyAmountsByCategory = <Category, List<int>>{};
  for (final transaction in historyTransactions) {
    if (transaction.amountCents >= 0) continue;
    historyAmountsByCategory.putIfAbsent(transaction.categoryId, () => []).add(-transaction.amountCents);
  }

  final medianByCategory = <Category, int>{
    for (final entry in historyAmountsByCategory.entries) entry.key: _median(entry.value),
  };

  final unusual = <UnusualExpense>[];
  for (final transaction in currentMonthTransactions) {
    if (transaction.amountCents >= 0) continue;

    final key = (
      description: normalizeExpenseDescription(transaction.description),
      amountCentsAbs: -transaction.amountCents,
    );
    if (recurringKeys.contains(key)) continue;

    final historyCount = historyAmountsByCategory[transaction.categoryId]?.length ?? 0;
    if (historyCount < minHistoryCount) continue;

    final median = medianByCategory[transaction.categoryId]!;
    final amountCentsAbs = -transaction.amountCents;
    if (amountCentsAbs <= median * factor) continue;

    unusual.add(
      UnusualExpense(
        description: transaction.description,
        categoryId: transaction.categoryId,
        amountCentsAbs: amountCentsAbs,
        date: transaction.date,
        categoryMedianCentsAbs: median,
        categoryHistoryCount: historyCount,
      ),
    );
  }

  unusual.sort((a, b) => b.amountCentsAbs.compareTo(a.amountCentsAbs));
  return unusual;
}

/// Median of [values] (non-empty, already in cents, no `double`). With
/// an odd number of elements, the middle one after sorting; with an
/// even number, the integer average of the two middle ones, **rounded
/// down** (`~/`, integer division): with 6,200 and 6,201, the real
/// median is 6,200.5 and this gives 6,200, never 6,201 — documented
/// this way in docs/design.md because of the effect it has on the edge
/// of [detectUnusualExpenses] (double of 6,200 is 12,400: an expense of
/// 12,400 isn't unusual, one of 12,401 is).
int _median(List<int> values) {
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) ~/ 2;
}

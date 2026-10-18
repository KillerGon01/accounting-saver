import '../reports/unusual_expenses.dart';
import '../transactions/category.dart';
import '../transactions/recurring_expenses.dart';
import '../transactions/transaction.dart';

/// Full previous months analyzed as history, same as
/// `BuildMonthEndForecast.recurringExpensesMonths`/`unusualExpenseHistoryMonths`
/// (same criterion, different name because it's a separate use case
/// that doesn't share a class).
const savingsSuggestionHistoryMonths = 3;

/// Suggested cut percentage over the monthly average of a category's
/// NON-recurring expense (see [calculateSavingsSuggestions]).
const savingsSuggestionCutPercent = 20;

/// Categories where a percentage cut makes sense to suggest: usually
/// variable spending that is, to some degree, avoidable. Explicitly
/// excludes those in [savingsSuggestionExcludedCategories].
const savingsSuggestionCutCategories = {
  Category.restaurantes,
  Category.ocio,
  Category.suscripciones,
  Category.otros,
};

/// Categories that never generate a suggestion (no percentage cut, no
/// recurring, no unusual one-off expense): fixed or necessary spending
/// (housing, health), or not a user expense to decide a cut on
/// (payroll is income with a negative sign because of how it's
/// recorded in some use cases, but conceptually it's never "possible
/// saving").
const savingsSuggestionExcludedCategories = {
  Category.hogar,
  Category.salud,
  Category.nomina,
};

/// Type of savings suggestion (see [calculateSavingsSuggestions]).
enum SavingsSuggestionType {
  /// A detected recurring expense (see `findRecurringExpenses`): frees
  /// its full monthly amount if cancelled or stopped.
  recurring,

  /// A percentage cut over the monthly average of a
  /// [savingsSuggestionCutCategories] category's NON-recurring expense.
  categoryCut,

  /// A one-off expense in the current month that stood out against
  /// its category's history (see `detectUnusualExpenses`): the excess
  /// over the median, not the full expense. Doesn't count toward the
  /// monthly coverage (see
  /// [SavingsSuggestionsResult.monthlyCoveredCents]): it's an event of
  /// this month, not something that can be counted on every month.
  oneOffExcess,
}

/// An option of where to save for a goal, computed in code (never with
/// AI, see docs/design.md "Sugerencias de ahorro por meta").
class SavingsSuggestion {
  const SavingsSuggestion({
    required this.type,
    required this.amountCents,
    this.description,
    this.categoryId,
  });

  final SavingsSuggestionType type;

  /// Positive magnitude: monthly amount freed up ([recurring],
  /// [categoryCut]) or the one-off excess amount over the median
  /// ([oneOffExcess]).
  final int amountCents;

  /// Only for [recurring] (the description, already normalized) and
  /// [oneOffExcess] (the description exactly as the user wrote it).
  /// `null` in [categoryCut], which doesn't come from a specific
  /// transaction.
  final String? description;

  /// `null` in [recurring] if the recurring expense's category
  /// couldn't be determined (see "Límite" in
  /// [calculateSavingsSuggestions]).
  final Category? categoryId;
}

/// Result of [calculateSavingsSuggestions]: the options, already
/// sorted from highest to lowest amount without distinguishing type,
/// and how much of that can be counted on each month.
class SavingsSuggestionsResult {
  const SavingsSuggestionsResult({
    required this.suggestions,
    required this.monthlyCoveredCents,
    this.truncated = false,
  });

  final List<SavingsSuggestion> suggestions;

  /// Sum of the amounts of [SavingsSuggestionType.recurring] and
  /// [SavingsSuggestionType.categoryCut] suggestions only: the
  /// [SavingsSuggestionType.oneOffExcess] ones don't repeat every
  /// month, so they don't add up here (see
  /// [SavingsSuggestionType.oneOffExcess]).
  final int monthlyCoveredCents;

  /// Same as `MonthEndForecast.truncated`/`UnusualExpensesResult.truncated`:
  /// whether either of `BuildSavingsSuggestions`'s two queries hit the
  /// safety cap. `false` by default for this function's tests, which
  /// don't go through any cap (`BuildSavingsSuggestions` sets it after
  /// calling this).
  final bool truncated;

  SavingsSuggestionsResult copyWith({bool? truncated}) {
    return SavingsSuggestionsResult(
      suggestions: suggestions,
      monthlyCoveredCents: monthlyCoveredCents,
      truncated: truncated ?? this.truncated,
    );
  }
}

/// Computes a goal's savings options from [historyTransactions] (the
/// previous [historyMonths] full months) and [currentMonthTransactions]
/// for the current month. Pure Dart, with no date or repository:
/// deciding which transactions are history and which belong to the
/// current month is the caller's job (see `BuildSavingsSuggestions`).
///
/// Reuses `findRecurringExpenses` (for (a)) and `detectUnusualExpenses`
/// (for (c)) as is, without changing their contract.
///
/// **(a) Recurring.** Each [RecurringExpense] from
/// `findRecurringExpenses` frees its full monthly amount, unless its
/// category is in [savingsSuggestionExcludedCategories].
///
/// **Documented limit:** a [RecurringExpense] doesn't store its
/// category (it could, in theory, have a different category on each
/// occurrence). Here, the category of the most recent occurrence in
/// [historyTransactions] with that same key (normalized description +
/// exact amount) is used. If the user changes a recurring expense's
/// category from one month to another, this function decides with the
/// last month's, not with all of them; in the (uncommon) case that
/// category can't be determined, the suggestion is still shown, with
/// `categoryId: null`, instead of being dropped.
///
/// **(b) Category cut.** For each category in
/// [savingsSuggestionCutCategories]: sum of its expenses in
/// [historyTransactions] that do NOT match a recurring key from (a)
/// (no double counting), divided by [historyMonths] (integer division,
/// rounded down) for the monthly average, and from there the
/// [cutPercent] % (again integer division, rounded down). If the
/// resulting cut is 0 (category with no non-recurring expense, or too
/// small an average), no suggestion is generated.
///
/// **(c) One-off excess.** Every expense from `detectUnusualExpenses`
/// over [currentMonthTransactions]/[historyTransactions], unless its
/// category is in [savingsSuggestionExcludedCategories]: the suggested
/// amount is the excess over its category's median
/// (`amountCentsAbs - categoryMedianCentsAbs`), not the full expense.
///
/// The result is sorted from highest to lowest amount, mixing the
/// three types together: they aren't grouped by type because what
/// matters to whoever looks at the list is how much each option frees
/// up, not which type it is.
SavingsSuggestionsResult calculateSavingsSuggestions({
  required List<Transaction> historyTransactions,
  required List<Transaction> currentMonthTransactions,
  int cutPercent = savingsSuggestionCutPercent,
  int historyMonths = savingsSuggestionHistoryMonths,
}) {
  final recurring = findRecurringExpenses(historyTransactions);
  final recurringKeys = <({String description, int amountCentsAbs})>{
    for (final expense in recurring) (description: expense.description, amountCentsAbs: expense.amountCentsAbs),
  };

  final categoryByKey = <({String description, int amountCentsAbs}), Category>{};
  final sortedHistory = [...historyTransactions]..sort((a, b) => a.date.compareTo(b.date));
  for (final transaction in sortedHistory) {
    if (transaction.amountCents >= 0) continue;
    final key = (
      description: normalizeExpenseDescription(transaction.description),
      amountCentsAbs: -transaction.amountCents,
    );
    if (recurringKeys.contains(key)) categoryByKey[key] = transaction.categoryId;
  }

  final suggestions = <SavingsSuggestion>[];
  var monthlyCoveredCents = 0;

  for (final expense in recurring) {
    final key = (description: expense.description, amountCentsAbs: expense.amountCentsAbs);
    final category = categoryByKey[key];
    if (category != null && savingsSuggestionExcludedCategories.contains(category)) continue;

    suggestions.add(
      SavingsSuggestion(
        type: SavingsSuggestionType.recurring,
        amountCents: expense.amountCentsAbs,
        description: expense.description,
        categoryId: category,
      ),
    );
    monthlyCoveredCents += expense.amountCentsAbs;
  }

  final nonRecurringSumByCategory = <Category, int>{};
  for (final transaction in historyTransactions) {
    if (transaction.amountCents >= 0) continue;
    if (!savingsSuggestionCutCategories.contains(transaction.categoryId)) continue;

    final key = (
      description: normalizeExpenseDescription(transaction.description),
      amountCentsAbs: -transaction.amountCents,
    );
    if (recurringKeys.contains(key)) continue;

    nonRecurringSumByCategory[transaction.categoryId] =
        (nonRecurringSumByCategory[transaction.categoryId] ?? 0) + (-transaction.amountCents);
  }

  for (final category in savingsSuggestionCutCategories) {
    final sum = nonRecurringSumByCategory[category] ?? 0;
    if (sum == 0) continue;

    final monthlyAverage = sum ~/ historyMonths;
    final cutCents = (monthlyAverage * cutPercent) ~/ 100;
    if (cutCents == 0) continue;

    suggestions.add(SavingsSuggestion(type: SavingsSuggestionType.categoryCut, amountCents: cutCents, categoryId: category));
    monthlyCoveredCents += cutCents;
  }

  final unusualExpenses = detectUnusualExpenses(
    currentMonthTransactions: currentMonthTransactions,
    historyTransactions: historyTransactions,
  );
  for (final unusual in unusualExpenses) {
    if (savingsSuggestionExcludedCategories.contains(unusual.categoryId)) continue;

    final excessCents = unusual.amountCentsAbs - unusual.categoryMedianCentsAbs;
    if (excessCents <= 0) continue;

    suggestions.add(
      SavingsSuggestion(
        type: SavingsSuggestionType.oneOffExcess,
        amountCents: excessCents,
        description: unusual.description,
        categoryId: unusual.categoryId,
      ),
    );
  }

  suggestions.sort((a, b) => b.amountCents.compareTo(a.amountCents));

  return SavingsSuggestionsResult(suggestions: suggestions, monthlyCoveredCents: monthlyCoveredCents);
}

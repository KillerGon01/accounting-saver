import 'transaction.dart';

/// Lowercase, no leading or trailing spaces, and no double spaces in
/// between: so "Netflix", "netflix " and "netflix  " all count as the
/// same description when looking for recurring expenses. The same
/// normalization `TransactionChatFunctions._normalizeDescription`
/// already used, now here so `findRecurringExpenses` can use it too.
String normalizeExpenseDescription(String text) {
  return text.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// Once an expense (normalized description + exact amount) appears in
/// [minMonths] or more distinct months of the ones analyzed, each
/// specific occurrence: which month (`isoMonth`, "YYYY-MM") and which
/// day of that month.
class RecurringExpenseOccurrence {
  const RecurringExpenseOccurrence({required this.isoMonth, required this.day});

  final String isoMonth;
  final int day;
}

/// An already-detected recurring expense: same normalized description
/// and same exact amount in 2 or more distinct months (see
/// [findRecurringExpenses]).
class RecurringExpense {
  const RecurringExpense({
    required this.description,
    required this.amountCentsAbs,
    required this.occurrences,
  });

  /// Already normalized (see [normalizeExpenseDescription]).
  final String description;

  /// Positive magnitude.
  final int amountCentsAbs;

  /// Sorted from oldest to most recent month.
  final List<RecurringExpenseOccurrence> occurrences;

  /// The day of the most recent occurrence: if the usual day has
  /// changed from one month to another, this is "the most recent one"
  /// (see `BuildMonthEndForecast`, which is what gives this meaning).
  int get mostRecentDay => occurrences.last.day;
}

/// An expense is recurring if, with the same normalized description
/// (lowercase and no extra spaces) and the same exact amount, it
/// appears in [minMonths] or more distinct months among
/// [transactions]. A deterministic definition, computed here in code,
/// not by any AI model.
///
/// Extracted from `TransactionChatFunctions._recurringExpenses` (see
/// docs/design.md, "Previsión de fin de mes"): the only difference is
/// that here each occurrence also stores the day of the month, not
/// just the month, because `BuildMonthEndForecast` needs to know each
/// recurring expense's usual day to decide whether it has already
/// arrived within the current month or not. `TransactionChatFunctions`
/// only needs the set of months, so it just takes
/// `RecurringExpense.occurrences.map((o) => o.isoMonth)`.
///
/// Only looks at expenses (`amountCents < 0`); income is never
/// considered recurring here, even if it repeats.
List<RecurringExpense> findRecurringExpenses(
  List<Transaction> transactions, {
  int minMonths = 2,
}) {
  final occurrencesByGroup = <({String description, int amountCentsAbs}), List<RecurringExpenseOccurrence>>{};

  for (final transaction in transactions) {
    if (transaction.amountCents >= 0) continue;
    final key = (
      description: normalizeExpenseDescription(transaction.description),
      amountCentsAbs: -transaction.amountCents,
    );
    occurrencesByGroup
        .putIfAbsent(key, () => [])
        .add(RecurringExpenseOccurrence(isoMonth: _isoMonth(transaction.date), day: transaction.date.day));
  }

  final recurring = <RecurringExpense>[];
  for (final entry in occurrencesByGroup.entries) {
    final distinctMonths = entry.value.map((o) => o.isoMonth).toSet();
    if (distinctMonths.length < minMonths) continue;

    final sortedOccurrences = [...entry.value]..sort((a, b) => a.isoMonth.compareTo(b.isoMonth));
    recurring.add(
      RecurringExpense(
        description: entry.key.description,
        amountCentsAbs: entry.key.amountCentsAbs,
        occurrences: sortedOccurrences,
      ),
    );
  }
  recurring.sort((a, b) => a.description.compareTo(b.description));
  return recurring;
}

String _isoMonth(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$year-$month';
}

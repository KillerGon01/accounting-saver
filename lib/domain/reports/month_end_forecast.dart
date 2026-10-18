/// A recurring expense that hasn't come in yet this month: its
/// description, its exact amount (the same it already charged in
/// previous months), and the day of the month it usually charges on
/// ("usual day" — see `BuildMonthEndForecast`, which decides this
/// value).
class PendingRecurringExpense {
  const PendingRecurringExpense({
    required this.description,
    required this.amountCentsAbs,
    required this.usualDay,
  });

  /// Already normalized (lowercase, no extra spaces).
  final String description;

  /// Positive magnitude.
  final int amountCentsAbs;

  /// Day of the current month this expense is expected on, already
  /// adjusted if the current month has fewer days than the month that
  /// day comes from (see `BuildMonthEndForecast`).
  final int usualDay;
}

/// Month-end forecast for the current month, computed in code from the
/// recurring expenses detected in previous months (see
/// `BuildMonthEndForecast` and `findRecurringExpenses`). Only exists for
/// the current month: a forecast for an already-closed month, or for a
/// future one with no transactions yet, makes no sense.
///
/// It's an estimate, not an exact calculation: it only accounts for
/// detected recurring expenses (same description and amount in 2 or
/// more of the previous 3 months). It doesn't forecast future income or
/// variable spending (see docs/design.md, "Límites").
class MonthEndForecast {
  const MonthEndForecast({
    required this.year,
    required this.month,
    required this.accumulatedExpenseCents,
    required this.pendingRecurringExpenses,
    required this.overdueUnregisteredExpenses,
    required this.forecastExpenseCents,
    required this.registeredIncomeCents,
    required this.truncated,
  });

  final int year;
  final int month;

  /// What's already been spent this month up to today (positive
  /// magnitude), exactly as `MonthlySummary` would compute it over the
  /// current month's transactions.
  final int accumulatedExpenseCents;

  /// Recurring expenses whose usual day hasn't arrived yet and that
  /// haven't already been registered this month with that same
  /// description and amount. Added to the forecast expense.
  final List<PendingRecurringExpense> pendingRecurringExpenses;

  /// Recurring expenses whose usual day has already passed but that
  /// haven't been registered this month. Separate, informative: not
  /// added to the forecast expense (there's no guarantee they'll still
  /// come in).
  final List<PendingRecurringExpense> overdueUnregisteredExpenses;

  /// `accumulatedExpenseCents` + the sum of `pendingRecurringExpenses`.
  final int forecastExpenseCents;

  /// Income already registered this month (signed magnitude, like
  /// `MonthlySummary.incomeCents`): income that hasn't come in yet isn't
  /// included in any calculation of this class.
  final int registeredIncomeCents;

  /// `true` if either query (current month or the previous 3) hit the
  /// cap on transactions read: the forecast may not reflect every
  /// transaction.
  final bool truncated;

  /// `registeredIncomeCents - forecastExpenseCents`: income that
  /// hasn't come in yet isn't included.
  int get forecastBalanceCents => registeredIncomeCents - forecastExpenseCents;

  int get pendingTotalCents => pendingRecurringExpenses.fold(0, (sum, p) => sum + p.amountCentsAbs);
}

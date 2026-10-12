/// Un gasto recurrente que todavía no ha entrado este mes: su concepto,
/// su importe exacto (el mismo que ya cobraba en meses anteriores) y el
/// día del mes en que suele cobrarse ("día habitual" — ver
/// `BuildMonthEndForecast`, que decide este valor).
class PendingRecurringExpense {
  const PendingRecurringExpense({
    required this.description,
    required this.amountCentsAbs,
    required this.usualDay,
  });

  /// Ya normalizado (minúsculas, sin espacios de más).
  final String description;

  /// Magnitud positiva.
  final int amountCentsAbs;

  /// Día del mes en curso en que se espera este gasto, ya ajustado si el
  /// mes en curso tiene menos días que el mes del que viene ese día (ver
  /// `BuildMonthEndForecast`).
  final int usualDay;
}

/// Previsión de fin de mes para el mes en curso, calculada en código a
/// partir de los gastos recurrentes detectados en los meses anteriores
/// (ver `BuildMonthEndForecast` y `findRecurringExpenses`). Solo existe
/// para el mes en curso: no tiene sentido una previsión de un mes ya
/// cerrado ni de uno futuro sin ningún movimiento todavía.
///
/// Es una estimación, no un cálculo exacto: solo tiene en cuenta gastos
/// recurrentes detectados (mismo concepto e importe en 2 o más de los 3
/// meses anteriores). No prevé ingresos futuros ni gasto variable (ver
/// docs/design.md, "Límites").
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

  /// Lo ya gastado este mes hasta hoy (magnitud positiva), tal cual lo
  /// calcularía `MonthlySummary` sobre los movimientos del mes en curso.
  final int accumulatedExpenseCents;

  /// Recurrentes cuyo día habitual todavía no ha llegado y que no se han
  /// registrado ya este mes con ese mismo concepto e importe. Se suman al
  /// gasto previsto.
  final List<PendingRecurringExpense> pendingRecurringExpenses;

  /// Recurrentes cuyo día habitual ya ha pasado pero que no se han
  /// registrado este mes. Aparte, informativo: no se suman al gasto
  /// previsto (no hay garantía de que vayan a llegar).
  final List<PendingRecurringExpense> overdueUnregisteredExpenses;

  /// `accumulatedExpenseCents` + la suma de `pendingRecurringExpenses`.
  final int forecastExpenseCents;

  /// Ingresos ya registrados este mes (magnitud con signo, como
  /// `MonthlySummary.incomeCents`): los ingresos que todavía no han
  /// entrado no se incluyen en ningún cálculo de esta clase.
  final int registeredIncomeCents;

  /// `true` si alguna de las consultas (mes en curso o los 3 anteriores)
  /// llegó al tope de movimientos leídos: la previsión puede no reflejar
  /// todos los movimientos.
  final bool truncated;

  /// `registeredIncomeCents - forecastExpenseCents`: los ingresos que aún
  /// no hayan entrado no se incluyen.
  int get forecastBalanceCents => registeredIncomeCents - forecastExpenseCents;

  int get pendingTotalCents => pendingRecurringExpenses.fold(0, (sum, p) => sum + p.amountCentsAbs);
}

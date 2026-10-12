import 'transaction.dart';

/// Minúsculas, sin espacios al principio o al final, y sin espacios dobles
/// en medio: así "Netflix", "netflix " y "netflix  " cuentan como el mismo
/// concepto al buscar gastos recurrentes. La misma normalización que ya
/// usaba `TransactionChatFunctions._normalizeDescription`, ahora aquí para
/// que la use también `findRecurringExpenses`.
String normalizeExpenseDescription(String text) {
  return text.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// Una vez que un gasto (concepto normalizado + importe exacto) aparece en
/// [minMonths] o más meses distintos de los analizados, cada aparición
/// concreta: en qué mes (`isoMonth`, "AAAA-MM") y en qué día de ese mes.
class RecurringExpenseOccurrence {
  const RecurringExpenseOccurrence({required this.isoMonth, required this.day});

  final String isoMonth;
  final int day;
}

/// Un gasto recurrente ya detectado: mismo concepto normalizado y mismo
/// importe exacto en 2 o más meses distintos (ver [findRecurringExpenses]).
class RecurringExpense {
  const RecurringExpense({
    required this.description,
    required this.amountCentsAbs,
    required this.occurrences,
  });

  /// Ya normalizado (ver [normalizeExpenseDescription]).
  final String description;

  /// Magnitud positiva.
  final int amountCentsAbs;

  /// Ordenadas de mes más antiguo a más reciente.
  final List<RecurringExpenseOccurrence> occurrences;

  /// El día de la ocurrencia más reciente: si el día habitual ha cambiado
  /// de un mes a otro, este es "el más reciente" (ver
  /// `BuildMonthEndForecast`, que es quien le da este significado).
  int get mostRecentDay => occurrences.last.day;
}

/// Un gasto es recurrente si, con el mismo concepto normalizado (en
/// minúsculas y sin espacios de más) y el mismo importe exacto, aparece en
/// [minMonths] o más meses distintos entre [transactions]. Definición
/// determinista, calculada aquí en código, no por ningún modelo de IA.
///
/// Extraída de `TransactionChatFunctions._recurringExpenses` (ver
/// docs/design.md, "Previsión de fin de mes"): la única diferencia es que
/// aquí cada aparición guarda también el día del mes, no solo el mes,
/// porque `BuildMonthEndForecast` necesita saber el día habitual de cada
/// recurrente para decidir si ya ha llegado o no dentro del mes en curso.
/// `TransactionChatFunctions` solo necesita el conjunto de meses, así que
/// se queda con `RecurringExpense.occurrences.map((o) => o.isoMonth)`.
///
/// Solo mira gastos (`amountCents < 0`); los ingresos nunca se consideran
/// recurrentes aquí, aunque se repitan.
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

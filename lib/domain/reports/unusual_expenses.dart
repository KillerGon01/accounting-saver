import '../transactions/category.dart';
import '../transactions/recurring_expenses.dart';
import '../transactions/transaction.dart';

/// Factor por el que el importe de un gasto debe superar la mediana de su
/// categoría para considerarse inusual (ver [detectUnusualExpenses]):
/// estrictamente superior al doble, no igual.
const unusualExpenseFactor = 2;

/// Gastos mínimos que debe tener una categoría en el histórico analizado
/// para que se le pueda calcular una mediana fiable y avisar de algo. Con
/// menos, cualquier gasto "parecería" inusual solo por tener poca muestra
/// (ver "Límites" en docs/design.md).
const unusualExpenseMinHistoryCount = 4;

/// Meses anteriores completos que se analizan como histórico, igual que
/// `BuildMonthEndForecast.recurringExpensesMonths` (mismo criterio, otro
/// nombre porque son dos casos de uso distintos que no comparten clase).
const unusualExpenseHistoryMonths = 3;

/// Un gasto del mes en curso que destaca frente al historial de su propia
/// categoría (ver [detectUnusualExpenses]).
class UnusualExpense {
  const UnusualExpense({
    required this.description,
    required this.categoryId,
    required this.amountCentsAbs,
    required this.date,
    required this.categoryMedianCentsAbs,
    required this.categoryHistoryCount,
  });

  /// Tal cual la escribió el usuario (sin normalizar: es para mostrar, no
  /// para comparar — la comparación ya se hizo en [detectUnusualExpenses]).
  final String description;
  final Category categoryId;

  /// Magnitud positiva.
  final int amountCentsAbs;
  final DateTime date;

  /// La mediana (ver [_median]) de los importes (magnitud positiva) de
  /// los gastos individuales de [categoryId] en el histórico analizado.
  final int categoryMedianCentsAbs;

  /// Cuántos gastos individuales de [categoryId] había en ese histórico
  /// (para que la tarjeta pueda explicar de dónde sale la comparación).
  final int categoryHistoryCount;
}

/// Resultado de [detectUnusualExpenses] a través de un caso de uso que sí
/// consulta Firestore (ver `BuildUnusualExpenses`): la lista, más si
/// alguna de sus consultas llegó al tope de seguridad.
class UnusualExpensesResult {
  const UnusualExpensesResult({required this.expenses, required this.truncated});

  final List<UnusualExpense> expenses;
  final bool truncated;
}

/// Un gasto de [currentMonthTransactions] se considera inusual si:
/// - Su categoría tiene al menos [minHistoryCount] gastos individuales en
///   [historyTransactions] (normalmente los 3 meses anteriores completos,
///   ver `BuildUnusualExpenses`/`BuildMonthEndForecast`): con menos, no
///   hay muestra suficiente para calcular una mediana fiable, así que no
///   se avisa de nada para esa categoría.
/// - Su importe (magnitud) supera **estrictamente** [factor] veces la
///   mediana de los importes de esos gastos históricos de su misma
///   categoría — el doble exacto no cuenta como inusual.
///
/// Se excluyen los gastos que coinciden con un recurrente de
/// [historyTransactions] (mismo concepto normalizado e importe exacto que
/// usa [findRecurringExpenses], llamada aquí con su `minMonths` por
/// defecto, sin cambiar su comportamiento ni su contrato): un recurrente
/// caro (el alquiler, por ejemplo) no es "inusual", es esperado.
///
/// Dart puro, sin fecha ni repositorio: decidir qué mes es "el mes en
/// curso" y qué transacciones pertenecen al histórico es cosa de quien
/// llama (ver `BuildUnusualExpenses`).
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

/// Mediana de [values] (no vacío, ya en céntimos, sin ningún `double`). Con
/// un número impar de elementos, el del centro tras ordenar; con uno par,
/// la media entera de los dos centrales, **redondeada hacia abajo**
/// (`~/`, división entera): con 6.200 y 6.201, la mediana real es 6.200,5
/// y esto da 6.200, nunca 6.201 — documentado así en docs/design.md por
/// el efecto que tiene en el borde de [detectUnusualExpenses] (el doble de
/// 6.200 es 12.400: un gasto de 12.400 no es inusual, uno de 12.401 sí).
int _median(List<int> values) {
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) ~/ 2;
}

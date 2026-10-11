import '../transactions/category.dart';

/// Resumen mensual calculado a partir de los movimientos del usuario:
/// totales, gasto por categoría y comparación con el mes anterior. Dart
/// puro (sin Firebase ni Flutter); lo calcula `BuildMonthlyReport`
/// (aplicación) y lo consume la pantalla de resumen (presentación).
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

  /// Magnitud positiva: el total gastado, sin signo (igual que
  /// `MonthlySummary.expenseCents`).
  final int expenseCents;

  final int transactionCount;

  int get balanceCents => incomeCents - expenseCents;

  /// Gasto por categoría del mes, ordenado de mayor a menor importe. Solo
  /// incluye categorías con gasto (> 0 céntimos) en el mes.
  final List<CategoryExpense> categoryBreakdown;

  /// Las 3 categorías de mayor gasto (o menos, si hay menos de 3 con
  /// gasto). Derivado de [categoryBreakdown], no se guarda aparte.
  List<CategoryExpense> get topCategories => categoryBreakdown.take(3).toList();

  /// `null` si el mes anterior no tiene ningún movimiento: no hay nada con
  /// qué comparar, y no se inventa una cifra (por ejemplo, un descenso del
  /// 100 % que no refleja la ausencia de datos).
  final MonthlyComparison? comparison;

  /// `true` si alguna de las dos consultas (este mes o el anterior) llegó
  /// al tope de `BuildMonthlyReport.maxFetchLimit` movimientos leídos: las
  /// cifras pueden no reflejar el mes completo.
  final bool truncated;

  /// `true` si este informe es del mes en curso (según el `Clock` de
  /// `BuildMonthlyReport`), no de un mes ya cerrado.
  final bool isCurrentMonth;

  /// Día del mes hasta el que llegan los datos, solo si [isCurrentMonth]
  /// es `true` (si no, `null`): un mes en curso nunca tiene todos sus
  /// días, así que compararlo con un mes anterior completo como si
  /// fueran equivalentes sería engañoso.
  final int? elapsedDays;
}

/// Gasto de una categoría en el mes, con su porcentaje sobre el total
/// gastado. El porcentaje se guarda con toda su precisión (sin redondear):
/// solo se redondea al mostrarlo (ver `report_formatters.dart`).
class CategoryExpense {
  const CategoryExpense({
    required this.category,
    required this.amountCents,
    required this.percentageOfExpense,
  });

  final Category category;

  /// Magnitud positiva.
  final int amountCents;

  /// Porcentaje (0-100) de [amountCents] sobre el total gastado en el mes.
  final double percentageOfExpense;
}

/// Comparación del gasto total y por categoría entre este mes y el
/// anterior. Las diferencias porcentuales son `null` cuando la base de
/// comparación (el importe del mes anterior) es cero: no hay un
/// porcentaje que no sea inventado para "de 0 € a X €".
class MonthlyComparison {
  const MonthlyComparison({
    required this.previousExpenseCents,
    required this.expenseDeltaCents,
    required this.expenseDeltaPercent,
    required this.perCategoryDeltas,
  });

  final int previousExpenseCents;

  /// Gasto de este mes menos el del mes anterior: positivo si se ha
  /// gastado más.
  final int expenseDeltaCents;

  final double? expenseDeltaPercent;

  /// Solo incluye categorías con gasto en este mes, en el anterior, o en
  /// los dos.
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

/// Compara el gasto por categoría de dos meses ya calculados (por
/// [BuildMonthlyReport] o equivalente): `currentBreakdown` es el mes que se
/// evalúa, `previousBreakdown` el mes base de la comparación (el que
/// aparece como "antes" o "frente a" en el resultado).
///
/// Pura: solo depende del desglose y el total ya agregados de cada mes, no
/// de las transacciones originales. Así una sola función sirve tanto para
/// "este mes contra el anterior" (la comparación que ya incluye
/// [BuildMonthlyReport] en cada informe) como para comparar dos meses
/// cualesquiera (ver `CompareMonths` del chat, en
/// `TransactionChatFunctions`), sin duplicar la aritmética de céntimos en
/// dos sitios.
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

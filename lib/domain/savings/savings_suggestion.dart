import '../reports/unusual_expenses.dart';
import '../transactions/category.dart';
import '../transactions/recurring_expenses.dart';
import '../transactions/transaction.dart';

/// Meses anteriores completos que se analizan como histórico, igual que
/// `BuildMonthEndForecast.recurringExpensesMonths`/`unusualExpenseHistoryMonths`
/// (mismo criterio, otro nombre porque es un caso de uso distinto que no
/// comparte clase).
const savingsSuggestionHistoryMonths = 3;

/// Porcentaje de recorte sugerido sobre la media mensual del gasto NO
/// recurrente de una categoría (ver [calculateSavingsSuggestions]).
const savingsSuggestionCutPercent = 20;

/// Categorías en las que tiene sentido sugerir un recorte porcentual: gasto
/// habitualmente variable y, en mayor o menor medida, evitable. Excluye
/// explícitamente las de [savingsSuggestionExcludedCategories].
const savingsSuggestionCutCategories = {
  Category.restaurantes,
  Category.ocio,
  Category.suscripciones,
  Category.otros,
};

/// Categorías que nunca generan una sugerencia (ni recorte porcentual, ni
/// recurrente, ni gasto puntual inusual): gasto fijo o necesario (vivienda,
/// salud) o que no es un gasto del usuario sobre el que decidir recortar
/// (la nómina es un ingreso con signo negativo por cómo se registra en
/// algunos casos de uso, pero conceptualmente nunca es "ahorro posible").
const savingsSuggestionExcludedCategories = {
  Category.hogar,
  Category.salud,
  Category.nomina,
};

/// Tipo de sugerencia de ahorro (ver [calculateSavingsSuggestions]).
enum SavingsSuggestionType {
  /// Un gasto recurrente detectado (ver `findRecurringExpenses`): libera su
  /// importe mensual completo si se cancela o se deja de pagar.
  recurring,

  /// Un recorte porcentual sobre la media mensual del gasto NO recurrente
  /// de una categoría de [savingsSuggestionCutCategories].
  categoryCut,

  /// Un gasto puntual del mes en curso que destacó frente al histórico de
  /// su categoría (ver `detectUnusualExpenses`): el exceso sobre la
  /// mediana, no el gasto completo. No cuenta para la cobertura mensual
  /// (ver [SavingsSuggestionsResult.monthlyCoveredCents]): es un suceso de
  /// este mes, no algo con lo que se pueda contar todos los meses.
  oneOffExcess,
}

/// Una opción de dónde ahorrar para una meta, calculada en código (nunca
/// con IA, ver docs/design.md "Sugerencias de ahorro por meta").
class SavingsSuggestion {
  const SavingsSuggestion({
    required this.type,
    required this.amountCents,
    this.description,
    this.categoryId,
  });

  final SavingsSuggestionType type;

  /// Magnitud positiva: importe mensual liberado ([recurring],
  /// [categoryCut]) o importe del exceso puntual sobre la mediana
  /// ([oneOffExcess]).
  final int amountCents;

  /// Solo para [recurring] (el concepto, ya normalizado) y [oneOffExcess]
  /// (la descripción tal cual la escribió el usuario). `null` en
  /// [categoryCut], que no viene de una transacción concreta.
  final String? description;

  /// `null` en [recurring] si no se pudo determinar la categoría del
  /// recurrente (ver "Límite" en [calculateSavingsSuggestions]).
  final Category? categoryId;
}

/// Resultado de [calculateSavingsSuggestions]: las opciones, ya ordenadas
/// de mayor a menor importe sin distinguir tipo, y cuánto de eso puede
/// contarse cada mes.
class SavingsSuggestionsResult {
  const SavingsSuggestionsResult({
    required this.suggestions,
    required this.monthlyCoveredCents,
    this.truncated = false,
  });

  final List<SavingsSuggestion> suggestions;

  /// Suma de los importes de las sugerencias [SavingsSuggestionType.recurring]
  /// y [SavingsSuggestionType.categoryCut] únicamente: las
  /// [SavingsSuggestionType.oneOffExcess] no se repiten todos los meses, así
  /// que no suman aquí (ver [SavingsSuggestionType.oneOffExcess]).
  final int monthlyCoveredCents;

  /// Igual que `MonthEndForecast.truncated`/`UnusualExpensesResult.truncated`:
  /// si alguna de las dos consultas de `BuildSavingsSuggestions` llegó al
  /// tope de seguridad. `false` por defecto para los tests de esta función,
  /// que no pasan por ningún tope (lo pone `BuildSavingsSuggestions` tras
  /// llamar aquí).
  final bool truncated;

  SavingsSuggestionsResult copyWith({bool? truncated}) {
    return SavingsSuggestionsResult(
      suggestions: suggestions,
      monthlyCoveredCents: monthlyCoveredCents,
      truncated: truncated ?? this.truncated,
    );
  }
}

/// Calcula las opciones de ahorro de una meta a partir de los
/// [historyTransactions] (los [historyMonths] meses anteriores completos) y
/// las [currentMonthTransactions] del mes en curso. Dart puro, sin fecha ni
/// repositorio: decidir qué transacciones son histórico y cuáles son del
/// mes en curso es cosa de quien llama (ver `BuildSavingsSuggestions`).
///
/// Reutiliza `findRecurringExpenses` (para (a)) y `detectUnusualExpenses`
/// (para (c)) tal cual, sin cambiar su contrato.
///
/// **(a) Recurrentes.** Cada [RecurringExpense] de `findRecurringExpenses`
/// libera su importe mensual completo, salvo que su categoría esté en
/// [savingsSuggestionExcludedCategories].
///
/// **Límite documentado:** un [RecurringExpense] no guarda su categoría
/// (puede, en teoría, tener una categoría distinta en cada aparición). Aquí
/// se usa la categoría de la aparición más reciente en [historyTransactions]
/// con esa misma clave (concepto normalizado + importe exacto). Si el
/// usuario cambia la categoría de un gasto recurrente de un mes a otro,
/// esta función decide con la del último mes, no con la de todos; en el
/// caso (infrecuente) de que esa categoría no pueda determinarse, la
/// sugerencia se muestra igualmente, con `categoryId: null`, en vez de
/// descartarla.
///
/// **(b) Recorte por categoría.** Para cada categoría de
/// [savingsSuggestionCutCategories]: suma de sus gastos en
/// [historyTransactions] que NO coincidan con una clave recurrente de (a)
/// (sin doble cómputo), dividida entre [historyMonths] (división entera
/// hacia abajo) para la media mensual, y de ahí el [cutPercent] % (de nuevo
/// división entera hacia abajo). Si el recorte resultante es 0 (categoría
/// sin gasto no recurrente, o media demasiado pequeña), no genera
/// sugerencia.
///
/// **(c) Exceso puntual.** Cada gasto de `detectUnusualExpenses` sobre
/// [currentMonthTransactions]/[historyTransactions], salvo que su categoría
/// esté en [savingsSuggestionExcludedCategories]: el importe sugerido es el
/// exceso sobre la mediana de su categoría (`amountCentsAbs -
/// categoryMedianCentsAbs`), no el gasto completo.
///
/// El resultado va ordenado de mayor a menor importe, mezclando los tres
/// tipos: no se agrupan por tipo porque lo que importa a quien mira la
/// lista es cuánto libera cada opción, no de qué tipo es.
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

import 'savings_goal.dart';
import 'savings_goal_progress.dart';
import 'savings_suggestion.dart';
import '../transactions/category.dart';

/// Opciones de un mismo tipo ([SavingsSuggestionType]) agrupadas por
/// categoría, con su importe agregado ya formateado en euros y una [line]
/// ya redactada y lista para copiar tal cual en una respuesta (ver
/// `summarizeSavingsSuggestions`/`GeminiSavingsSuggestionsGateway`): ni el
/// modelo ni nadie tiene que calcular ni volver a formatear nada a partir
/// de [amountFormatted].
class SavingsSuggestionCategoryAggregate {
  const SavingsSuggestionCategoryAggregate({
    required this.category,
    this.count,
    required this.amountFormatted,
    required this.line,
  });

  /// `null` solo puede pasar en un recurrente sin categoría determinable
  /// (ver el límite documentado en `calculateSavingsSuggestions`).
  final Category? category;

  /// Número de cargos agregados en este grupo. Solo se rellena para
  /// [SavingsSuggestionType.recurring] (ver `summarizeSavingsSuggestions`):
  /// un recorte o un exceso puntual son un único importe agregado por
  /// categoría, no "cargos" que contar.
  final int? count;

  final String amountFormatted;

  /// Frase ya redactada en español, p. ej. "Recurrentes en Suscripciones:
  /// 3 cargos, 58,98 €/mes.".
  final String line;
}

/// Resumen agregado de la meta y de sus opciones de ahorro, pensado para
/// enviarse tal cual a `SavingsSuggestionsGateway`: **ningún campo es
/// texto libre del usuario** (ni el nombre de la meta, ni ningún concepto
/// o descripción de movimiento) — solo cifras, el enum [Category] (9
/// valores fijos del código) y el enum [SavingsGoalStatus]. No es un
/// filtrado que pueda fallar: el tipo, literalmente, no tiene ningún campo
/// por el que ese texto pudiera llegar aquí.
class SavingsSuggestionsSummary {
  const SavingsSuggestionsSummary({
    required this.targetFormatted,
    required this.savedFormatted,
    required this.monthlyContributionFormatted,
    required this.monthsRemaining,
    required this.status,
    required this.monthlyCoveredFormatted,
    required this.recurringByCategory,
    required this.categoryCuts,
    required this.oneOffExcesses,
  });

  final String targetFormatted;
  final String savedFormatted;
  final String monthlyContributionFormatted;
  final int monthsRemaining;
  final SavingsGoalStatus status;

  /// Suma de recurrentes + recortes (ver
  /// `SavingsSuggestionsResult.monthlyCoveredCents`), ya formateada.
  final String monthlyCoveredFormatted;

  final List<SavingsSuggestionCategoryAggregate> recurringByCategory;
  final List<SavingsSuggestionCategoryAggregate> categoryCuts;
  final List<SavingsSuggestionCategoryAggregate> oneOffExcesses;
}

/// Construye el [SavingsSuggestionsSummary] de [goal]/[progress]/[suggestions],
/// con todas las cifras ya formateadas en euros y una [SavingsSuggestionCategoryAggregate.line]
/// ya redactada por grupo. Dart puro: no importa nada de `presentation/`
/// (el dominio no depende de la capa de presentación, aunque
/// `CategoryLabel` en esa capa no tenga ningún import de Flutter) — las
/// etiquetas de categoría se duplican aquí a propósito, mismo patrón que
/// `_euros`/`_groupThousands` ya duplicados en `GeminiMonthlyReportGateway`.
SavingsSuggestionsSummary summarizeSavingsSuggestions({
  required SavingsGoal goal,
  required SavingsGoalProgress progress,
  required SavingsSuggestionsResult suggestions,
}) {
  return SavingsSuggestionsSummary(
    targetFormatted: _euros(goal.targetCents),
    savedFormatted: _euros(goal.savedCents),
    monthlyContributionFormatted: _euros(progress.monthlyContributionCents),
    monthsRemaining: progress.monthsRemaining,
    status: progress.status,
    monthlyCoveredFormatted: _euros(suggestions.monthlyCoveredCents),
    recurringByCategory: _groupByCategory(
      suggestions.suggestions.where((s) => s.type == SavingsSuggestionType.recurring),
      withCount: true,
      lineBuilder: (category, count, amountFormatted) =>
          'Recurrentes en ${_categoryLabel(category)}: ${_cargos(count!)}, $amountFormatted/mes.',
    ),
    categoryCuts: _groupByCategory(
      suggestions.suggestions.where((s) => s.type == SavingsSuggestionType.categoryCut),
      withCount: false,
      lineBuilder: (category, count, amountFormatted) => 'Recorte en ${_categoryLabel(category)}: $amountFormatted/mes.',
    ),
    oneOffExcesses: _groupByCategory(
      suggestions.suggestions.where((s) => s.type == SavingsSuggestionType.oneOffExcess),
      withCount: false,
      lineBuilder: (category, count, amountFormatted) =>
          'Gasto puntual en ${_categoryLabel(category)}: $amountFormatted (este mes, no se repite).',
    ),
  );
}

List<SavingsSuggestionCategoryAggregate> _groupByCategory(
  Iterable<SavingsSuggestion> items, {
  required bool withCount,
  required String Function(Category? category, int? count, String amountFormatted) lineBuilder,
}) {
  final totals = <Category?, int>{};
  final counts = <Category?, int>{};
  for (final item in items) {
    totals[item.categoryId] = (totals[item.categoryId] ?? 0) + item.amountCents;
    counts[item.categoryId] = (counts[item.categoryId] ?? 0) + 1;
  }

  final categories = totals.keys.toList()..sort((a, b) => totals[b]!.compareTo(totals[a]!));
  return [
    for (final category in categories)
      SavingsSuggestionCategoryAggregate(
        category: category,
        count: withCount ? counts[category] : null,
        amountFormatted: _euros(totals[category]!),
        line: lineBuilder(category, withCount ? counts[category] : null, _euros(totals[category]!)),
      ),
  ];
}

String _cargos(int count) => count == 1 ? '1 cargo' : '$count cargos';

String _categoryLabel(Category? category) {
  if (category == null) return 'una categoría sin determinar';
  return switch (category) {
    Category.supermercado => 'Supermercado',
    Category.restaurantes => 'Restaurantes',
    Category.transporte => 'Transporte',
    Category.suscripciones => 'Suscripciones',
    Category.ocio => 'Ocio',
    Category.salud => 'Salud',
    Category.hogar => 'Hogar',
    Category.nomina => 'Nómina',
    Category.otros => 'Otros',
  };
}

String _euros(int cents) {
  final sign = cents < 0 ? '-' : '';
  final absolute = cents.abs();
  final euros = _groupThousands(absolute ~/ 100);
  final decimals = (absolute % 100).toString().padLeft(2, '0');
  return '$sign$euros,$decimals €';
}

String _groupThousands(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final remaining = digits.length - i;
    if (i > 0 && remaining % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

import 'savings_goal.dart';
import 'savings_goal_progress.dart';
import 'savings_suggestion.dart';
import '../transactions/category.dart';

/// Options of the same type ([SavingsSuggestionType]) grouped by
/// category, with their aggregated amount already formatted in euros
/// and a [line] already written and ready to copy as-is into a reply
/// (see `summarizeSavingsSuggestions`/`GeminiSavingsSuggestionsGateway`):
/// neither the model nor anyone else has to compute or reformat
/// anything from [amountFormatted].
class SavingsSuggestionCategoryAggregate {
  const SavingsSuggestionCategoryAggregate({
    required this.category,
    this.count,
    required this.amountFormatted,
    required this.line,
  });

  /// `null` can only happen for a recurring expense with no
  /// determinable category (see the documented limit in
  /// `calculateSavingsSuggestions`).
  final Category? category;

  /// Number of charges aggregated in this group. Only filled in for
  /// [SavingsSuggestionType.recurring] (see
  /// `summarizeSavingsSuggestions`): a cut or a one-off excess are a
  /// single aggregated amount per category, not "charges" to count.
  final int? count;

  final String amountFormatted;

  /// Sentence already written in Spanish, e.g. "Recurrentes en
  /// Suscripciones: 3 cargos, 58,98 €/mes.".
  final String line;
}

/// Aggregated summary of the goal and its savings options, meant to be
/// sent as-is to `SavingsSuggestionsGateway`: **no field is the user's
/// free text** (not the goal's name, nor any transaction concept or
/// description) — only figures, the [Category] enum (9 fixed values
/// from the code), and the [SavingsGoalStatus] enum. It's not a
/// filtering step that could fail: the type, literally, has no field
/// that text could reach here through.
class SavingsSuggestionsSummary {
  const SavingsSuggestionsSummary({
    required this.targetFormatted,
    required this.savedFormatted,
    required this.monthlyContributionFormatted,
    required this.monthsRemaining,
    required this.status,
    required this.monthlyCoveredFormatted,
    required this.coverageLine,
    required this.recurringByCategory,
    required this.categoryCuts,
    required this.oneOffExcesses,
  });

  final String targetFormatted;
  final String savedFormatted;
  final String monthlyContributionFormatted;
  final int monthsRemaining;
  final SavingsGoalStatus status;

  /// Sum of recurring expenses + cuts (see
  /// `SavingsSuggestionsResult.monthlyCoveredCents`), already
  /// formatted.
  final String monthlyCoveredFormatted;

  /// Sentence already written in Spanish that relates
  /// [monthlyCoveredFormatted] to [monthlyContributionFormatted] (see
  /// [savingsSuggestionCoverageText]): the same text, word for word,
  /// that the suggestions sheet already shows — so the model doesn't
  /// have to relate the two amounts on its own, only copy this line.
  final String coverageLine;

  final List<SavingsSuggestionCategoryAggregate> recurringByCategory;
  final List<SavingsSuggestionCategoryAggregate> categoryCuts;
  final List<SavingsSuggestionCategoryAggregate> oneOffExcesses;
}

/// Sentence already written in Spanish that relates what the savings
/// options would cover each month ([coveredCents]) to what the goal
/// needs each month ([neededCents]), in integer cents. Pure Dart, no
/// `double` at all: the only "how much it covers" logic in the whole
/// app, used both by `SavingsSuggestionsSheet` (to display it) and by
/// `summarizeSavingsSuggestions` (so it also travels to the model as
/// [SavingsSuggestionsSummary.coverageLine]) — a single place, not two
/// texts that could drift apart.
///
/// Three cases:
/// - [coveredCents] is 0 or less (there are only one-off excesses,
///   which don't count here): it says so explicitly, without the
///   "up to X of Y" template.
/// - [coveredCents] is less than [neededCents]: "Podrías cubrir hasta
///   X de los Y/mes que necesitas aportar.".
/// - [coveredCents] reaches or exceeds [neededCents]: a natural
///   sentence without the "up to X of Y" template (saying "up to
///   2,000 of the €500/month" would sound absurd when it's already
///   covered with plenty to spare).
String savingsSuggestionCoverageText(int coveredCents, int neededCents) {
  if (coveredCents <= 0) {
    return 'Estas opciones son gastos puntuales de este mes: no cubren nada de tu aportación mensual de '
        '${_euros(neededCents)}.';
  }
  if (coveredCents >= neededCents) {
    return 'Con estas opciones podrías cubrir toda tu aportación mensual de ${_euros(neededCents)} '
        'e incluso dejar margen de sobra.';
  }
  return 'Podrías cubrir hasta ${_euros(coveredCents)} de los ${_euros(neededCents)}/mes que necesitas aportar.';
}

/// Builds the [SavingsSuggestionsSummary] of [goal]/[progress]/[suggestions],
/// with every figure already formatted in euros and a
/// [SavingsSuggestionCategoryAggregate.line] already written per
/// group. Pure Dart: imports nothing from `presentation/` (the domain
/// layer doesn't depend on the presentation layer, even though
/// `CategoryLabel` in that layer has no Flutter import at all) — the
/// category labels are duplicated here on purpose, same pattern as
/// `_euros`/`_groupThousands`, already duplicated in
/// `GeminiMonthlyReportGateway`.
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
    coverageLine: savingsSuggestionCoverageText(suggestions.monthlyCoveredCents, progress.monthlyContributionCents),
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

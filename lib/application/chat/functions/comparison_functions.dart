import '../../../domain/reports/monthly_report.dart';
import '../../reports/build_monthly_report.dart';
import 'shared.dart';

/// `compareMonths`: compares any two months (not necessarily
/// consecutive).
class ComparisonFunctions {
  ComparisonFunctions(this._buildMonthlyReport);

  final BuildMonthlyReport _buildMonthlyReport;

  /// Compares any two months (not necessarily consecutive): A is the
  /// base month ("before"/"versus") and B the one being evaluated,
  /// with the same meaning as "current" and "previous" in the monthly
  /// report (see [BuildMonthlyReport] and [compareCategoryBreakdowns]).
  /// If A has no transactions, no comparison is computed (same as the
  /// report does with the previous month), so as not to make up a
  /// +100% or -100% delta that doesn't reflect the lack of data.
  Future<Map<String, Object?>> compareMonths({
    required String userId,
    required Map<String, Object?> arguments,
    required DateTime now,
  }) async {
    final yearARaw = asInt(arguments['yearA']);
    final monthARaw = asInt(arguments['monthA']);
    final errorA = yearMonthError(yearARaw, monthARaw, now, 'A');
    if (errorA != null) return errorA;

    final yearBRaw = asInt(arguments['yearB']);
    final monthBRaw = asInt(arguments['monthB']);
    final errorB = yearMonthError(yearBRaw, monthBRaw, now, 'B');
    if (errorB != null) return errorB;

    final reportA = await _buildMonthlyReport(
      userId: userId,
      year: yearARaw!,
      month: monthARaw!,
      now: now,
    );
    final reportB = await _buildMonthlyReport(
      userId: userId,
      year: yearBRaw!,
      month: monthBRaw!,
      now: now,
    );

    final hasComparison = reportA.transactionCount > 0;
    final comparisonJson = hasComparison ? _buildComparisonJson(reportA, reportB) : null;

    return {
      'monthA': _monthSummaryJson(reportA),
      'monthB': _monthSummaryJson(reportB),
      'expenseDeltaCents': comparisonJson?['expenseDeltaCents'],
      'expenseDeltaPercent': comparisonJson?['expenseDeltaPercent'],
      'categoryDeltas': comparisonJson?['categoryDeltas'] ?? const [],
      'comparisonLines': comparisonJson?['comparisonLines'] ?? const [],
      'categoryComparisonLines': comparisonJson?['categoryComparisonLines'] ?? const [],
      if (!hasComparison)
        'note':
            'El mes A (${reportA.year}-${reportA.month.toString().padLeft(2, '0')}) no tiene '
            'ningún movimiento: no se calcula ninguna comparación con él.',
      if (reportA.truncated || reportB.truncated) ...safetyLimitWarning(),
    };
  }

  Map<String, Object?> _monthSummaryJson(MonthlyReport report) {
    return {
      'year': report.year,
      'month': report.month,
      'incomeCents': report.incomeCents,
      'expenseCents': report.expenseCents,
      'balanceCents': report.balanceCents,
      'transactionCount': report.transactionCount,
      'isCurrentMonth': report.isCurrentMonth,
      if (report.isCurrentMonth) 'elapsedDays': report.elapsedDays,
      if (report.transactionCount == 0) 'note': 'Este mes no tiene ningún movimiento.',
    };
  }

  /// Delta of total and per-category expense between two
  /// already-computed reports, plus the same figures already written
  /// in plain text ("Gastos: 1.508,59 € frente a 1.447,21 € (+4,2 %)")
  /// for the model to copy as-is. Categories are sorted by B's expense
  /// (the evaluated month), from highest to lowest, same as
  /// `rankingLines` in `BreakdownFunctions.getCategoryBreakdown`.
  Map<String, Object?> _buildComparisonJson(MonthlyReport reportA, MonthlyReport reportB) {
    final comparison = compareCategoryBreakdowns(
      currentBreakdown: reportB.categoryBreakdown,
      currentExpenseCents: reportB.expenseCents,
      previousBreakdown: reportA.categoryBreakdown,
      previousExpenseCents: reportA.expenseCents,
    );

    final categories = comparison.perCategoryDeltas.keys.toList()
      ..sort(
        (a, b) => comparison.perCategoryDeltas[b]!.currentAmountCents.compareTo(
          comparison.perCategoryDeltas[a]!.currentAmountCents,
        ),
      );

    final categoryDeltas = <Map<String, Object?>>[];
    final categoryComparisonLines = <String>[];
    for (final category in categories) {
      final delta = comparison.perCategoryDeltas[category]!;
      final deltaPercent = delta.deltaPercent == null ? null : roundTo1Decimal(delta.deltaPercent!);
      categoryDeltas.add({
        'categoryId': category.name,
        'currentAmountCents': delta.currentAmountCents,
        'previousAmountCents': delta.previousAmountCents,
        'deltaCents': delta.deltaCents,
        'deltaPercent': deltaPercent,
      });
      categoryComparisonLines.add(
        '${categoryLabel(category)}: ${formatEurosWithSymbol(delta.currentAmountCents)} frente a '
        '${formatEurosWithSymbol(delta.previousAmountCents)} (${formatDeltaPercent(deltaPercent)})',
      );
    }

    final expenseDeltaPercent = comparison.expenseDeltaPercent == null
        ? null
        : roundTo1Decimal(comparison.expenseDeltaPercent!);

    // Current-month notices come first (A and, if it's also the
    // case, B): before any figure, so they can't be omitted or
    // softened when drafting the reply (see the system instruction in
    // gemini_chat_gateway.dart).
    final comparisonLines = [
      if (reportA.isCurrentMonth) currentMonthWarning(reportA),
      if (reportB.isCurrentMonth) currentMonthWarning(reportB),
      'Gastos: ${formatEurosWithSymbol(reportB.expenseCents)} frente a '
          '${formatEurosWithSymbol(reportA.expenseCents)} (${formatDeltaPercent(expenseDeltaPercent)})',
      'Ingresos: ${formatEurosWithSymbol(reportB.incomeCents)} frente a '
          '${formatEurosWithSymbol(reportA.incomeCents)}',
      'Balance: ${formatEurosWithSymbol(reportB.balanceCents)} frente a '
          '${formatEurosWithSymbol(reportA.balanceCents)}',
    ];

    return {
      'expenseDeltaCents': comparison.expenseDeltaCents,
      'expenseDeltaPercent': expenseDeltaPercent,
      'categoryDeltas': categoryDeltas,
      'comparisonLines': comparisonLines,
      'categoryComparisonLines': categoryComparisonLines,
    };
  }
}

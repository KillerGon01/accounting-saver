import 'package:flutter/material.dart';

import '../../../domain/reports/monthly_report.dart';
import '../../theme/app_theme.dart';
import '../../transactions/formatters.dart';
import '../report_formatters.dart';

class ComparisonBody extends StatelessWidget {
  const ComparisonBody({super.key, required this.comparison});

  final MonthlyComparison? comparison;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final comparison = this.comparison;
    if (comparison == null) {
      return Text(
        'Sin datos del mes anterior.',
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      );
    }

    return ComparisonRow(
      label: 'Gasto total',
      deltaCents: comparison.expenseDeltaCents,
      deltaPercent: comparison.expenseDeltaPercent,
    );
  }
}

/// Comparison row: arrow + text (never only color or only the arrow)
/// with the absolute difference and, if it can be computed, the
/// percentage.
class ComparisonRow extends StatelessWidget {
  const ComparisonRow({super.key, required this.label, required this.deltaCents, required this.deltaPercent});

  final String label;
  final int deltaCents;
  final double? deltaPercent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final finance = theme.extension<FinanceColors>()!;
    final isIncrease = deltaCents > 0;
    final isDecrease = deltaCents < 0;
    final color = isIncrease ? finance.expense : (isDecrease ? finance.income : theme.colorScheme.onSurface);
    final icon = isIncrease
        ? Icons.arrow_upward
        : (isDecrease ? Icons.arrow_downward : Icons.remove);
    final percentText = deltaPercent == null ? '' : ' (${formatPercentage(deltaPercent!.abs())})';
    final text = '$label: ${formatCents(deltaCents.abs())} ${isIncrease ? 'más' : (isDecrease ? 'menos' : 'igual')}'
        ' que el mes anterior$percentText';

    return Semantics(
      label: text,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

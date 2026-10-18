import 'package:flutter/material.dart';

import '../../../domain/reports/unusual_expenses.dart';
import '../../theme/app_theme.dart';
import '../../transactions/formatters.dart';
import 'report_common.dart';

/// "Gastos inusuales" card: expenses in the current month whose
/// amount stands out against its own category's history (see
/// `detectUnusualExpenses`, docs/design.md "Detección de gastos
/// inusuales"). Only shown when `MonthlyReportScreen` receives a
/// non-null result (current month, and the calculation hasn't
/// failed — see `report_providers.dart`).
class UnusualExpensesCard extends StatelessWidget {
  const UnusualExpensesCard({super.key, required this.result});

  final UnusualExpensesResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Gastos inusuales (estimación)', style: theme.textTheme.labelLarge),
            if (result.truncated) ...[
              const SizedBox(height: AppSpacing.xs),
              const InfoBanner(
                icon: Icons.warning_amber_outlined,
                text: 'Análisis parcial: se han leído los primeros 2.000 movimientos de alguno de '
                    'los meses analizados.',
              ),
            ],
            const SizedBox(height: AppSpacing.s),
            if (result.expenses.isEmpty)
              Text(
                'No se han detectado gastos inusuales. Se compara cada gasto de este mes con la '
                'mediana de su categoría en los 3 meses anteriores; necesita al menos '
                '$unusualExpenseMinHistoryCount gastos de esa categoría en ese histórico para '
                'poder comparar.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              )
            else
              for (final expense in result.expenses) _UnusualExpenseTile(expense: expense),
            const SizedBox(height: AppSpacing.s),
            Text(
              'Estimación estadística, no una alerta de fraude: puede equivocarse, sobre todo con '
              'poco histórico.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A `UnusualExpensesCard` row: the icon and the amount's color are
/// visual support, never the only clue — the text already says
/// "unusual" explicitly through `Semantics.label`, and the comparison
/// with the median always goes in a second line of text, not just in
/// the color.
class _UnusualExpenseTile extends StatelessWidget {
  const _UnusualExpenseTile({required this.expense});

  final UnusualExpense expense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amountText = formatCents(-expense.amountCentsAbs);
    final detailText =
        '${formatDate(expense.date)} — mediana de ${expense.categoryId.label}: '
        '${formatCents(expense.categoryMedianCentsAbs)} (${expense.categoryHistoryCount} gastos '
        'analizados)';
    final semanticsLabel =
        'Gasto inusual: ${_capitalize(expense.description)}, $amountText, $detailText';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Semantics(
        label: semanticsLabel,
        child: ExcludeSemantics(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.trending_up, size: 18, color: theme.colorScheme.error),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_capitalize(expense.description)} · ${expense.categoryId.label}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    Text(
                      detailText,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Text(
                amountText,
                style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.error),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return '${text[0].toUpperCase()}${text.substring(1)}';
  }
}

import 'package:flutter/material.dart';

import '../../../domain/transactions/monthly_summary.dart';
import '../../common/animated_balance_text.dart';
import '../../theme/app_theme.dart';
import '../formatters.dart';

class SummaryCard extends StatelessWidget {
  const SummaryCard({super.key, required this.summary});

  final MonthlySummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final finance = theme.extension<FinanceColors>()!;
    final balanceColor = summary.balanceCents < 0 ? finance.expense : finance.income;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: AppSpacing.s),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Balance del mes', style: theme.textTheme.labelLarge),
            const SizedBox(height: AppSpacing.xs),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: AnimatedBalanceText(
                cents: summary.balanceCents,
                style: theme.textTheme.displaySmall?.copyWith(
                  color: balanceColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.m),
            Row(
              children: [
                Expanded(
                  child: SummaryItem(
                    label: 'Ingresos',
                    value: formatCents(summary.incomeCents),
                    color: finance.income,
                  ),
                ),
                Expanded(
                  child: SummaryItem(
                    label: 'Gastos',
                    value: formatCents(-summary.expenseCents),
                    color: finance.expense,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SummaryItem extends StatelessWidget {
  const SummaryItem({super.key, required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        const SizedBox(height: AppSpacing.xs),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

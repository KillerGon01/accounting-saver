import 'package:flutter/material.dart';

import '../../../domain/reports/month_end_forecast.dart';
import '../../../domain/reports/monthly_report.dart';
import '../../../domain/reports/unusual_expenses.dart';
import '../../common/animated_balance_text.dart';
import '../../common/staggered_entrance.dart';
import '../../theme/app_theme.dart';
import '../../transactions/formatters.dart';
import '../category_bar_chart.dart';
import 'comparison_section.dart';
import 'month_end_forecast_card.dart';
import 'report_common.dart';
import 'unusual_expenses_card.dart';

class ReportBody extends StatelessWidget {
  const ReportBody({
    super.key,
    required this.report,
    required this.forecast,
    required this.unusualExpenses,
    required this.showAiComment,
    required this.comment,
    required this.isGenerating,
    required this.progressMessage,
    required this.remainingComments,
    required this.onGenerateComment,
  });

  final MonthlyReport report;

  /// `null` if the month shown isn't the current one, or if the
  /// calculation failed (see `MonthlyReportScreen.build`): in both
  /// cases, no forecast card.
  final MonthEndForecast? forecast;

  /// `null` if the month shown isn't the current one, or if the
  /// calculation failed: in both cases, no unusual expenses card.
  final UnusualExpensesResult? unusualExpenses;
  final bool showAiComment;
  final String? comment;
  final bool isGenerating;
  final String progressMessage;
  final int remainingComments;
  final VoidCallback onGenerateComment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final finance = theme.extension<FinanceColors>()!;
    final balanceColor = report.balanceCents < 0 ? finance.expense : finance.income;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.m),
      children: [
        if (report.isCurrentMonth)
          InfoBanner(
            icon: Icons.schedule,
            text: 'Mes en curso, hasta el día ${report.elapsedDays}.',
          ),
        if (report.truncated)
          const InfoBanner(
            icon: Icons.warning_amber_outlined,
            text: 'Informe parcial: se han leído los primeros 2.000 movimientos de este rango.',
          ),
        StaggeredEntrance(
          index: 0,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Balance del mes', style: theme.textTheme.labelLarge),
                  const SizedBox(height: AppSpacing.xs),
                  AnimatedBalanceText(
                    cents: report.balanceCents,
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: balanceColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.m),
                  Row(
                    children: [
                      Expanded(
                        child: SummaryTile(
                          label: 'Ingresos',
                          value: formatCents(report.incomeCents),
                          color: finance.income,
                        ),
                      ),
                      Expanded(
                        child: SummaryTile(
                          // Signed, same as in the transactions screen
                          // (`SummaryCard`/`SummaryItem`) and each
                          // individual transaction (`TransactionTile`):
                          // `report.expenseCents` is a positive
                          // magnitude in the domain layer (see
                          // `MonthlySummary`/`MonthlyReport`), and only
                          // how to display it is decided here.
                          label: 'Gastos',
                          value: formatCents(-report.expenseCents),
                          color: finance.expense,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${report.transactionCount} movimientos',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.m),
        StaggeredEntrance(
          index: 1,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Gasto por categoría', style: theme.textTheme.labelLarge),
                  const SizedBox(height: AppSpacing.s),
                  CategoryBarChart(categories: report.categoryBreakdown),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.m),
        StaggeredEntrance(
          index: 2,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpacing.xs,
                    children: [
                      Text('Comparación con el mes anterior', style: theme.textTheme.labelLarge),
                      if (report.isCurrentMonth && report.comparison != null)
                        Text(
                          '(parcial, mes en curso)',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s),
                  ComparisonBody(comparison: report.comparison),
                ],
              ),
            ),
          ),
        ),
        if (showAiComment) ...[
          const SizedBox(height: AppSpacing.m),
          StaggeredEntrance(
            index: 3,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.m),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (report.transactionCount == 0)
                      const Text('No hay movimientos este mes')
                    else ...[
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          remainingComments <= 0
                              ? 'Has llegado al máximo de comentarios de esta sesión'
                              : 'Te quedan $remainingComments comentarios',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      if (comment != null) Text(comment!, style: theme.textTheme.bodyMedium),
                      if (comment != null) const SizedBox(height: AppSpacing.s),
                      if (isGenerating)
                        Row(
                          children: [
                            const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: AppSpacing.s),
                            Expanded(
                              child: Text(
                                progressMessage,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        )
                      else
                        FilledButton.icon(
                          onPressed: remainingComments <= 0 ? null : onGenerateComment,
                          icon: const Icon(Icons.auto_awesome),
                          label: const Text('Generar comentario con IA'),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
        if (forecast != null) ...[
          const SizedBox(height: AppSpacing.m),
          StaggeredEntrance(index: 4, child: MonthEndForecastCard(forecast: forecast!)),
        ],
        if (unusualExpenses != null) ...[
          const SizedBox(height: AppSpacing.m),
          StaggeredEntrance(index: 5, child: UnusualExpensesCard(result: unusualExpenses!)),
        ],
      ],
    );
  }
}

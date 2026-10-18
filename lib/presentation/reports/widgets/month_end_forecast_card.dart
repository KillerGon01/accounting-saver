import 'package:flutter/material.dart';

import '../../../domain/reports/month_end_forecast.dart';
import '../../theme/app_theme.dart';
import '../../transactions/formatters.dart';
import 'report_common.dart';

/// "Previsión de fin de mes" card: expense accumulated up to today,
/// each pending recurring expense with its amount and day, the
/// forecast expense (sum of the two), and the forecast balance. Only
/// shown when `MonthlyReportScreen` receives a non-null forecast
/// (current month, and the calculation hasn't failed — see
/// `report_providers.dart`).
class MonthEndForecastCard extends StatelessWidget {
  const MonthEndForecastCard({super.key, required this.forecast});

  final MonthEndForecast forecast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Previsión de fin de mes (estimación)', style: theme.textTheme.labelLarge),
            if (forecast.truncated) ...[
              const SizedBox(height: AppSpacing.xs),
              const InfoBanner(
                icon: Icons.warning_amber_outlined,
                text: 'Previsión parcial: se han leído los primeros 2.000 movimientos de alguno de los meses analizados.',
              ),
            ],
            const SizedBox(height: AppSpacing.s),
            _ForecastLine(
              label: 'Gastado hasta hoy',
              value: formatCents(forecast.accumulatedExpenseCents),
            ),
            if (forecast.pendingRecurringExpenses.isEmpty)
              _ForecastLine(label: 'Recurrentes pendientes este mes', value: 'ninguno', indent: true)
            else
              for (final pending in forecast.pendingRecurringExpenses)
                _ForecastLine(
                  label: '${_capitalize(pending.description)} (día ${pending.usualDay})',
                  value: formatCents(pending.amountCentsAbs),
                  indent: true,
                ),
            const Divider(height: AppSpacing.m),
            _ForecastLine(
              label: 'Gasto previsto',
              value: formatCents(forecast.forecastExpenseCents),
              emphasize: true,
            ),
            const SizedBox(height: AppSpacing.xs),
            _ForecastLine(
              label: 'Balance previsto',
              value: formatCents(forecast.forecastBalanceCents),
              emphasize: true,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Los ingresos que aún no hayan entrado no se incluyen.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Ingresos registrados: ${formatCents(forecast.registeredIncomeCents)}.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (forecast.overdueUnregisteredExpenses.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s),
              Text(
                'Esperados y no registrados todavía (no incluidos en la previsión):',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              for (final overdue in forecast.overdueUnregisteredExpenses)
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.s, top: 2),
                  child: Text(
                    '${_capitalize(overdue.description)} (día ${overdue.usualDay}): '
                    '${formatCents(overdue.amountCentsAbs)}',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
            ],
            const SizedBox(height: AppSpacing.s),
            Text(
              'Estimación basada solo en gastos recurrentes detectados en meses '
              'anteriores: no prevé ingresos futuros ni gasto variable.',
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

  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return '${text[0].toUpperCase()}${text.substring(1)}';
  }
}

/// A "label: amount" row in the forecast card. [indent] marks a
/// breakdown line (a pending recurring expense) with indentation, to
/// visually distinguish it from the totals without relying only on a
/// color.
class _ForecastLine extends StatelessWidget {
  const _ForecastLine({
    required this.label,
    required this.value,
    this.indent = false,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool indent;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = emphasize
        ? theme.textTheme.titleSmall
        : theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Padding(
      padding: EdgeInsets.only(left: indent ? AppSpacing.m : 0, top: 2, bottom: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

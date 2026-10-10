import 'package:flutter/material.dart';

import '../../domain/reports/monthly_report.dart';
import '../theme/app_theme.dart';
import '../transactions/category_style.dart';
import '../transactions/formatters.dart';
import 'report_formatters.dart';

/// Gráfico de barras horizontales del gasto por categoría, con widgets
/// propios (sin `CustomPainter` ni ningún paquete de gráficos): cada fila
/// es un icono, una etiqueta, el importe y el porcentaje en texto, y una
/// barra coloreada cuyo ancho es proporcional al gasto de la categoría
/// respecto a la de mayor gasto. Ninguna fila es solo color: el importe y
/// el porcentaje siempre van en texto, y cada barra tiene una etiqueta
/// semántica (`Semantics`) con esa misma información para quien use un
/// lector de pantalla.
///
/// No muestra ninguna fila de "Total: 100 %": cada porcentaje ya es por
/// categoría, y sumar uno aparte sería redundante (siempre ~100 %, salvo
/// el margen de redondeo de `formatPercentage`).
class CategoryBarChart extends StatelessWidget {
  const CategoryBarChart({super.key, required this.categories});

  final List<CategoryExpense> categories;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
        child: Text(
          'Sin gasto por categoría este mes.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    // `categories` ya viene ordenado de mayor a menor gasto (ver
    // `BuildMonthlyReport._breakdownByCategory`), así que el primero es
    // el de mayor importe: la referencia para el ancho de las barras.
    final maxAmountCents = categories.first.amountCents;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final expense in categories)
          _CategoryBarRow(expense: expense, maxAmountCents: maxAmountCents),
      ],
    );
  }
}

class _CategoryBarRow extends StatelessWidget {
  const _CategoryBarRow({required this.expense, required this.maxAmountCents});

  final CategoryExpense expense;
  final int maxAmountCents;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = expense.category;
    final widthFactor = maxAmountCents == 0 ? 0.0 : expense.amountCents / maxAmountCents;
    final percentageText = formatPercentage(expense.percentageOfExpense);
    final amountText = formatCents(expense.amountCents);

    return Semantics(
      label: '${category.label}: $amountText, $percentageText del gasto total',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(category.icon, color: category.color, size: 18),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(category.label, style: theme.textTheme.bodyMedium),
                ),
                Text(amountText, style: theme.textTheme.bodyMedium),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  percentageText,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Container(
                height: 8,
                color: theme.colorScheme.surfaceContainerHighest,
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: widthFactor.clamp(0.0, 1.0),
                  child: Container(color: category.color),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

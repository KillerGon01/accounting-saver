import 'package:flutter/material.dart';

import '../../domain/reports/monthly_report.dart';
import '../common/motion.dart';
import '../theme/app_theme.dart';
import '../transactions/category_style.dart';
import '../transactions/formatters.dart';
import 'report_formatters.dart';

/// Mínimo visible del ancho de cada barra, como fracción del carril
/// (3 %): sin esto, una categoría muy pequeña frente al gasto total
/// dibujaría una barra de un puñado de píxeles o invisible, aunque su
/// importe y porcentaje de verdad (en texto, al lado) sean correctos. No
/// afecta a ningún cálculo de dominio, solo al ancho dibujado.
const _minBarWidthFactor = 0.03;

/// Gráfico de barras horizontales del gasto por categoría, con widgets
/// propios (sin `CustomPainter` ni ningún paquete de gráficos): cada fila
/// es un icono, una etiqueta, el importe y el porcentaje en texto, y una
/// barra coloreada cuyo ancho es proporcional al porcentaje de esa
/// categoría sobre el gasto TOTAL del mes (`CategoryExpense.percentageOfExpense`,
/// el mismo porcentaje que ya se muestra en texto, nunca relativo a la
/// categoría de mayor gasto). Ninguna fila es solo color: el importe y
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final expense in categories) _CategoryBarRow(expense: expense),
      ],
    );
  }
}

class _CategoryBarRow extends StatelessWidget {
  const _CategoryBarRow({required this.expense});

  final CategoryExpense expense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = expense.category;
    final widthFactor = (expense.percentageOfExpense / 100).clamp(_minBarWidthFactor, 1.0);
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
              borderRadius: BorderRadius.circular(6),
              child: Container(
                height: 10,
                color: theme.colorScheme.surfaceContainerHighest,
                alignment: Alignment.centerLeft,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: widthFactor),
                  duration: AppMotion.of(context, AppMotion.base),
                  curve: Curves.easeOut,
                  builder: (context, value, child) => FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: value,
                    child: Container(color: category.color),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

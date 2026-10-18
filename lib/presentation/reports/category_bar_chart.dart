import 'package:flutter/material.dart';

import '../../domain/reports/monthly_report.dart';
import '../common/motion.dart';
import '../theme/app_theme.dart';
import '../transactions/category_style.dart';
import '../transactions/formatters.dart';
import 'report_formatters.dart';

/// Minimum visible width for each bar, as a fraction of the track
/// (3%): without this, a category very small compared to the total
/// expense would draw a bar a handful of pixels wide or invisible,
/// even though its real amount and percentage (in text, next to it)
/// are correct. Doesn't affect any domain calculation, only the
/// drawn width.
const _minBarWidthFactor = 0.03;

/// Horizontal bar chart of expense by category, with the app's own
/// widgets (no `CustomPainter` or any charting package): each row is
/// an icon, a label, the amount and percentage in text, and a
/// colored bar whose width is proportional to that category's
/// percentage of the month's TOTAL expense
/// (`CategoryExpense.percentageOfExpense`, the same percentage
/// already shown in text, never relative to the highest-spending
/// category). No row is color alone: the amount and the percentage
/// always go in text, and each bar has a semantic label
/// (`Semantics`) with that same information for whoever uses a
/// screen reader.
///
/// Doesn't show any "Total: 100%" row: each percentage is already
/// per category, and adding a separate one would be redundant
/// (always ~100%, aside from `formatPercentage`'s rounding margin).
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

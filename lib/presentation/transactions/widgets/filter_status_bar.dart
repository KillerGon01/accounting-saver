import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Row with "N de M movimientos" and a button to clear the filters,
/// only visible when some criterion is set (`TransactionFilter.isActive`).
/// The text is the main notice (it doesn't rely solely on the icon's
/// badge, which is color-based, to know a filter is active).
class FilterStatusBar extends StatelessWidget {
  const FilterStatusBar({
    super.key,
    required this.matchCount,
    required this.totalCount,
    required this.onClear,
  });

  final int matchCount;
  final int totalCount;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.m, 0, AppSpacing.s, AppSpacing.s),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$matchCount de $totalCount movimientos',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            onPressed: onClear,
            child: const Text('Quitar filtros'),
          ),
        ],
      ),
    );
  }
}

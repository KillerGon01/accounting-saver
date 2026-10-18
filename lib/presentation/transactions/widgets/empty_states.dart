import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Empty state when the month has transactions but none match the
/// active search or filters — distinct from `EmptyMonth` (which is
/// when the month has no transactions at all, with or without a
/// filter).
class FilteredEmptyState extends StatelessWidget {
  const FilteredEmptyState({super.key, required this.onClearFilters});

  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.l),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.search_off,
                      size: 56,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(height: AppSpacing.m),
                    Text(
                      'Ningún movimiento coincide con la búsqueda o los filtros',
                      style: theme.textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.l),
                    OutlinedButton(
                      onPressed: onClearFilters,
                      child: const Text('Quitar filtros'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class EmptyMonth extends StatelessWidget {
  const EmptyMonth({super.key, required this.isLoadingDemo, required this.onLoadDemo});

  final bool isLoadingDemo;
  final VoidCallback onLoadDemo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.l),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 56,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(height: AppSpacing.m),
                    Text(
                      'No hay movimientos este mes',
                      style: theme.textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Añade uno con el botón Nuevo o carga datos de ejemplo para probar la app.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.l),
                    FilledButton.tonalIcon(
                      onPressed: isLoadingDemo ? null : onLoadDemo,
                      icon: const Icon(Icons.dataset_outlined),
                      label: const Text('Cargar datos de ejemplo'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/savings/savings_goal.dart';
import '../../domain/savings/savings_goal_progress.dart';
import '../../domain/savings/savings_suggestion.dart';
import '../theme/app_theme.dart';
import '../transactions/category_style.dart';
import '../transactions/formatters.dart';
import 'savings_goal_providers.dart';

/// Hoja modal con las opciones de ahorro de [goal] (ver
/// `BuildSavingsSuggestions`/`calculateSavingsSuggestions`). Se calcula al
/// abrirse (bajo demanda, no al abrir la pantalla de metas): 2 consultas a
/// Firestore por apertura (ver docs/design.md).
///
/// Si el cálculo falla, muestra un mensaje genérico dentro de la propia
/// hoja: el resto de la pantalla de metas sigue funcionando (el `Future`
/// vive solo aquí, no en ningún provider que pueda arrastrar el error a
/// otro sitio).
class SavingsSuggestionsSheet extends ConsumerStatefulWidget {
  const SavingsSuggestionsSheet({super.key, required this.userId, required this.goal, required this.progress});

  final String userId;
  final SavingsGoal goal;
  final SavingsGoalProgress progress;

  static Future<void> show(
    BuildContext context, {
    required String userId,
    required SavingsGoal goal,
    required SavingsGoalProgress progress,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SavingsSuggestionsSheet(userId: userId, goal: goal, progress: progress),
    );
  }

  @override
  ConsumerState<SavingsSuggestionsSheet> createState() => _SavingsSuggestionsSheetState();
}

class _SavingsSuggestionsSheetState extends ConsumerState<SavingsSuggestionsSheet> {
  late final Future<SavingsSuggestionsResult> _future = ref.read(buildSavingsSuggestionsProvider)(
    userId: widget.userId,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.m, 0, AppSpacing.m, AppSpacing.m),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '¿De dónde puedo ahorrar?',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                widget.goal.name,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.m),
              Expanded(
                child: FutureBuilder<SavingsSuggestionsResult>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return const _SheetMessage(
                        icon: Icons.error_outline,
                        text: 'No se han podido calcular las opciones de ahorro. Inténtalo de nuevo más tarde.',
                      );
                    }
                    return _SuggestionsList(result: snapshot.requireData, progress: widget.progress);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestionsList extends StatelessWidget {
  const _SuggestionsList({required this.result, required this.progress});

  final SavingsSuggestionsResult result;
  final SavingsGoalProgress progress;

  @override
  Widget build(BuildContext context) {
    if (result.suggestions.isEmpty) {
      return const _SheetMessage(
        icon: Icons.inbox_outlined,
        text: 'No hay histórico suficiente en los últimos 3 meses para calcular opciones de ahorro.',
      );
    }

    final theme = Theme.of(context);
    return ListView(
      children: [
        Text(
          _coverageText(result.monthlyCoveredCents, progress.monthlyContributionCents),
          style: theme.textTheme.bodyMedium,
        ),
        if (result.truncated) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Icon(Icons.warning_amber_outlined, size: 18, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Cálculo parcial: se han leído los primeros 2.000 movimientos de cada rango analizado.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.m),
        for (final suggestion in result.suggestions) ...[
          _SuggestionTile(suggestion: suggestion),
          const SizedBox(height: AppSpacing.s),
        ],
        const SizedBox(height: AppSpacing.s),
        const Divider(),
        const SizedBox(height: AppSpacing.s),
        Text(
          'Opciones informativas calculadas con tus gastos de los últimos 3 meses. '
          'Decidir qué recortar es cosa tuya: no son recomendaciones financieras.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

String _coverageText(int coveredCents, int neededCents) {
  if (coveredCents <= 0) {
    return 'Estas opciones son gastos puntuales de este mes: no cubren nada de tu aportación mensual de '
        '${formatCents(neededCents)}.';
  }
  if (coveredCents >= neededCents) {
    return 'Con estas opciones podrías cubrir toda tu aportación mensual de ${formatCents(neededCents)} '
        'e incluso dejar margen de sobra.';
  }
  return 'Podrías cubrir hasta ${formatCents(coveredCents)} de los ${formatCents(neededCents)}/mes que necesitas aportar.';
}

/// Icono, texto (nunca solo el icono) y, si procede, categoría de
/// [suggestion] (ver [SavingsSuggestionType]).
class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({required this.suggestion});

  final SavingsSuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(_icon(suggestion)),
        title: Text(_title(suggestion)),
        subtitle: Text(_subtitle(suggestion)),
        trailing: Text(
          '${formatCents(suggestion.amountCents)}${suggestion.type == SavingsSuggestionType.oneOffExcess ? '' : '/mes'}',
          style: theme.textTheme.titleSmall,
        ),
        isThreeLine: true,
      ),
    );
  }
}

IconData _icon(SavingsSuggestion suggestion) {
  return switch (suggestion.type) {
    SavingsSuggestionType.recurring => Icons.autorenew,
    SavingsSuggestionType.categoryCut => suggestion.categoryId?.icon ?? Icons.content_cut,
    SavingsSuggestionType.oneOffExcess => Icons.bolt_outlined,
  };
}

String _title(SavingsSuggestion suggestion) {
  return switch (suggestion.type) {
    // El concepto de un recurrente ya viene normalizado (en minúsculas, ver
    // `normalizeExpenseDescription`): aquí solo se capitaliza para mostrarlo,
    // sin tocar el dato que se usa para comparar.
    SavingsSuggestionType.recurring => _capitalize(suggestion.description) ?? 'Gasto recurrente',
    SavingsSuggestionType.categoryCut =>
      'Recorte del $savingsSuggestionCutPercent % en ${suggestion.categoryId?.label ?? 'una categoría'}',
    SavingsSuggestionType.oneOffExcess => suggestion.description ?? 'Gasto puntual',
  };
}

String? _capitalize(String? text) {
  if (text == null || text.isEmpty) return text;
  return '${text[0].toUpperCase()}${text.substring(1)}';
}

String _subtitle(SavingsSuggestion suggestion) {
  final categorySuffix = suggestion.categoryId != null ? ' · ${suggestion.categoryId!.label}' : '';
  return switch (suggestion.type) {
    SavingsSuggestionType.recurring => 'Gasto recurrente$categorySuffix',
    SavingsSuggestionType.categoryCut => 'Recorte estimado sobre tu gasto habitual en esta categoría',
    SavingsSuggestionType.oneOffExcess => 'Gasto puntual de este mes$categorySuffix, por encima de lo habitual',
  };
}

class _SheetMessage extends StatelessWidget {
  const _SheetMessage({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: theme.colorScheme.outline),
            const SizedBox(height: AppSpacing.m),
            Text(text, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

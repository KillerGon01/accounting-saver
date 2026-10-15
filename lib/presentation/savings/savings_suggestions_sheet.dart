import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_check_config.dart';
import '../../domain/savings/savings_goal.dart';
import '../../domain/savings/savings_goal_progress.dart';
import '../../domain/savings/savings_suggestion.dart';
import '../../domain/savings/savings_suggestions_summary.dart';
import '../theme/app_theme.dart';
import '../transactions/category_style.dart';
import '../transactions/formatters.dart';
import 'savings_goal_providers.dart';
import 'savings_suggestions_error_messages.dart';

const _slowReplyWarningDelay = Duration(seconds: 10);
const _verySlowReplyWarningDelay = Duration(seconds: 45);
const _extremelySlowReplyWarningDelay = Duration(seconds: 120);

/// Hoja modal con las opciones de ahorro de [goal] (ver
/// `BuildSavingsSuggestions`/`calculateSavingsSuggestions`). Se calcula al
/// abrirse (bajo demanda, no al abrir la pantalla de metas): 2 consultas a
/// Firestore por apertura (ver docs/design.md).
///
/// Si el cálculo falla, muestra un mensaje genérico dentro de la propia
/// hoja: el resto de la pantalla de metas sigue funcionando (el `Future`
/// vive solo aquí, no en ningún provider que pueda arrastrar el error a
/// otro sitio).
///
/// Si [showAiButton] lo permite (por defecto [effectiveEnableAi], igual
/// que `MonthlyReportScreen.showAiComment`: solo existe como parámetro
/// para poder probar la hoja con y sin IA sin depender de con qué
/// `--dart-define=ENABLE_AI` se haya lanzado `flutter test`), debajo de
/// la lista aparece un botón para redactar con IA un resumen en prosa de
/// esas mismas opciones (nunca las sustituye).
class SavingsSuggestionsSheet extends ConsumerStatefulWidget {
  SavingsSuggestionsSheet({
    super.key,
    required this.userId,
    required this.goal,
    required this.progress,
    bool? showAiButton,
  }) : showAiButton = showAiButton ?? effectiveEnableAi;

  final String userId;
  final SavingsGoal goal;
  final SavingsGoalProgress progress;
  final bool showAiButton;

  static Future<void> show(
    BuildContext context, {
    required String userId,
    required SavingsGoal goal,
    required SavingsGoalProgress progress,
    bool? showAiButton,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          SavingsSuggestionsSheet(userId: userId, goal: goal, progress: progress, showAiButton: showAiButton),
    );
  }

  @override
  ConsumerState<SavingsSuggestionsSheet> createState() => _SavingsSuggestionsSheetState();
}

class _SavingsSuggestionsSheetState extends ConsumerState<SavingsSuggestionsSheet> {
  late final Future<SavingsSuggestionsResult> _future = ref.read(buildSavingsSuggestionsProvider)(
    userId: widget.userId,
  );

  String? _aiText;
  bool _isGeneratingAi = false;
  int? _remainingExplanations;
  Timer? _slowReplyTimer;
  Timer? _verySlowReplyTimer;
  Timer? _extremelySlowReplyTimer;
  bool _isSlowReply = false;
  bool _isVerySlowReply = false;
  bool _isExtremelySlowReply = false;

  @override
  void initState() {
    super.initState();
    if (widget.showAiButton) {
      _remainingExplanations = ref.read(explainSavingsSuggestionsProvider(widget.userId)).remainingExplanations;
    }
  }

  @override
  void dispose() {
    _slowReplyTimer?.cancel();
    _verySlowReplyTimer?.cancel();
    _extremelySlowReplyTimer?.cancel();
    super.dispose();
  }

  Future<void> _generateAiSummary(SavingsSuggestionsResult result) async {
    setState(() {
      _isGeneratingAi = true;
      _isSlowReply = false;
      _isVerySlowReply = false;
      _isExtremelySlowReply = false;
    });

    // Timers, no un `Future.delayed` esperado: no bloquean nada (mismo
    // patrón que `MonthlyReportScreen`).
    _slowReplyTimer = Timer(_slowReplyWarningDelay, () {
      if (!mounted || !_isGeneratingAi) return;
      setState(() => _isSlowReply = true);
    });
    _verySlowReplyTimer = Timer(_verySlowReplyWarningDelay, () {
      if (!mounted || !_isGeneratingAi) return;
      setState(() => _isVerySlowReply = true);
    });
    _extremelySlowReplyTimer = Timer(_extremelySlowReplyWarningDelay, () {
      if (!mounted || !_isGeneratingAi) return;
      setState(() => _isExtremelySlowReply = true);
    });

    try {
      final text = await ref.read(explainSavingsSuggestionsProvider(widget.userId))(
        goal: widget.goal,
        progress: widget.progress,
        suggestions: result,
      );
      if (!mounted) return;
      setState(() => _aiText = text);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(savingsSuggestionsErrorMessage(error))));
    } finally {
      _slowReplyTimer?.cancel();
      _verySlowReplyTimer?.cancel();
      _extremelySlowReplyTimer?.cancel();
      final remaining = ref.read(explainSavingsSuggestionsProvider(widget.userId)).remainingExplanations;
      if (mounted) {
        setState(() {
          _isGeneratingAi = false;
          _remainingExplanations = remaining;
        });
      }
    }
  }

  String get _aiProgressMessage {
    final parts = ['Redactando el resumen...'];
    if (_isSlowReply) parts.add('Esto está tardando más de lo normal...');
    if (_isVerySlowReply) parts.add('Puede tardar hasta un par de minutos.');
    if (_isExtremelySlowReply) {
      parts.add('Sigue en marcha: hoy el servicio está lento y puede tardar hasta unos 3 minutos.');
    }
    return parts.join(' ');
  }

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
                    final result = snapshot.requireData;
                    // Todo en un único `SingleChildScrollView` (sugerencias
                    // + sección de IA), no un `ListView` más una sección
                    // fija aparte: así el texto generado por la IA, que
                    // puede ocupar varias líneas con texto grande, nunca
                    // desborda — simplemente hace que el conjunto scrollee
                    // un poco más.
                    return SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ..._suggestionsSectionChildren(context, result, widget.progress),
                          if (widget.showAiButton) ..._buildAiSection(context, result),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildAiSection(BuildContext context, SavingsSuggestionsResult result) {
    final theme = Theme.of(context);
    return [
      const SizedBox(height: AppSpacing.m),
      const Divider(),
      const SizedBox(height: AppSpacing.m),
      Align(
        alignment: Alignment.centerRight,
        child: Text(
          _remainingExplanationsLabel(_remainingExplanations ?? 0),
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
      const SizedBox(height: AppSpacing.xs),
      if (_aiText != null) ...[
        Container(
          padding: const EdgeInsets.all(AppSpacing.s),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_aiText!, style: theme.textTheme.bodyMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Texto generado por IA a partir de las cifras de arriba.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s),
      ],
      if (_isGeneratingAi)
        Row(
          children: [
            const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: AppSpacing.s),
            Expanded(
              child: Text(
                _aiProgressMessage,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        )
      else
        FilledButton.icon(
          onPressed: (_remainingExplanations ?? 0) <= 0 ? null : () => _generateAiSummary(result),
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Redactar resumen con IA'),
        ),
    ];
  }
}

String _remainingExplanationsLabel(int remaining) {
  if (remaining <= 0) return 'Has llegado al máximo de esta sesión';
  return remaining == 1 ? 'Te queda 1 resumen' : 'Te quedan $remaining resúmenes';
}

List<Widget> _suggestionsSectionChildren(
  BuildContext context,
  SavingsSuggestionsResult result,
  SavingsGoalProgress progress,
) {
  if (result.suggestions.isEmpty) {
    return const [
      _SheetMessage(
        icon: Icons.inbox_outlined,
        text: 'No hay histórico suficiente en los últimos 3 meses para calcular opciones de ahorro.',
      ),
    ];
  }

  final theme = Theme.of(context);
  return [
    Text(
      savingsSuggestionCoverageText(result.monthlyCoveredCents, progress.monthlyContributionCents),
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
  ];
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

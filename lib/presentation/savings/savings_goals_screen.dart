import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/common/clock.dart';
import '../../domain/savings/savings_goal.dart';
import '../../domain/savings/savings_goal_progress.dart';
import '../common/firestore_error_messages.dart';
import '../common/motion.dart';
import '../common/staggered_entrance.dart';
import '../help/help_sheet.dart';
import '../help/help_topic.dart';
import '../theme/app_theme.dart';
import '../transactions/formatters.dart';
import 'savings_goal_form_screen.dart';
import 'savings_goal_providers.dart';
import 'savings_suggestions_sheet.dart';
import 'update_saved_amount_dialog.dart';

/// List of the user's savings goals, with their progress computed in
/// code (see `calculateSavingsGoalProgress`, docs/design.md). Works
/// without AI: doesn't depend on `effectiveEnableAi` anywhere.
///
/// [clock] is injectable (defaulting to [SystemClock]) only so tests
/// can fix "now" when computing progress — same pattern as
/// `BuildMonthlyReport`/`BuildMonthEndForecast`, here at the screen
/// level because the calculation is a pure domain function, with no
/// use case in between (see `SavingsGoalsScreen` in docs/design.md).
class SavingsGoalsScreen extends ConsumerWidget {
  const SavingsGoalsScreen({super.key, required this.userId, this.clock = const SystemClock()});

  final String userId;
  final Clock clock;

  Future<void> _openForm(BuildContext context, {SavingsGoal? goal}) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SavingsGoalFormScreen(userId: userId, goal: goal)),
    );
  }

  Future<void> _updateSavedAmount(BuildContext context, WidgetRef ref, SavingsGoal goal) async {
    final newSavedCents = await showUpdateSavedAmountDialog(context, goal);
    if (newSavedCents == null) return;
    try {
      await ref.read(updateSavedAmountProvider)(
        userId: userId,
        goal: goal,
        newSavedCents: newSavedCents,
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            firestoreErrorMessage(error, fallback: 'No se pudo actualizar lo ahorrado.'),
          ),
        ),
      );
    }
  }

  Future<void> _confirmAndDelete(BuildContext context, WidgetRef ref, SavingsGoal goal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar meta'),
        content: Text('¿Seguro que quieres eliminar "${goal.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(deleteSavingsGoalProvider)(userId: userId, goalId: goal.id);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(firestoreErrorMessage(error, fallback: 'No se pudo eliminar la meta.')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goalsAsync = ref.watch(savingsGoalsStreamProvider(userId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Metas de ahorro'),
        actions: const [HelpButton(topic: HelpTopic.savingsGoals)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        tooltip: 'Añadir una meta',
        onPressed: () => _openForm(context),
        icon: const Icon(Icons.add),
        label: const Text('Nueva meta'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: goalsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.m),
                child: Text(
                  firestoreErrorMessage(
                    error,
                    fallback: 'No se pudieron cargar las metas. Inténtalo de nuevo más tarde.',
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            data: (goals) {
              if (goals.isEmpty) {
                return _EmptyGoals(onCreate: () => _openForm(context));
              }
              final now = clock.now();
              var index = 0;
              return ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.m, AppSpacing.m, AppSpacing.m, 88),
                children: [
                  for (final goal in goals) ...[
                    StaggeredEntrance(
                      index: index++,
                      child: _SavingsGoalCard(
                        userId: userId,
                        goal: goal,
                        progress: calculateSavingsGoalProgress(goal, now: now),
                        onEdit: () => _openForm(context, goal: goal),
                        onUpdateSaved: () => _updateSavedAmount(context, ref, goal),
                        onDelete: () => _confirmAndDelete(context, ref, goal),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.m),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _EmptyGoals extends StatelessWidget {
  const _EmptyGoals({required this.onCreate});

  final VoidCallback onCreate;

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
                    Icon(Icons.savings_outlined, size: 56, color: theme.colorScheme.outline),
                    const SizedBox(height: AppSpacing.m),
                    Text(
                      'Todavía no tienes ninguna meta de ahorro',
                      style: theme.textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Crea una con el botón "Nueva meta" para empezar a seguir tu progreso.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.l),
                    FilledButton.tonalIcon(
                      onPressed: onCreate,
                      icon: const Icon(Icons.add),
                      label: const Text('Nueva meta'),
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

/// Icon, text, and color for [status] — never color alone: the text
/// already states the status explicitly, and each status also has
/// its own icon.
({IconData icon, String label, Color Function(BuildContext) color}) _statusStyle(
  SavingsGoalStatus status,
) {
  return switch (status) {
    SavingsGoalStatus.completed => (
      icon: Icons.check_circle_outline,
      label: 'Cumplida',
      color: (context) => Theme.of(context).extension<FinanceColors>()!.income,
    ),
    SavingsGoalStatus.onTrack => (
      icon: Icons.trending_up,
      label: 'En camino',
      color: (context) => Theme.of(context).extension<FinanceColors>()!.income,
    ),
    SavingsGoalStatus.behind => (
      icon: Icons.trending_down,
      label: 'Por detrás',
      color: (context) => Theme.of(context).extension<FinanceColors>()!.warning,
    ),
    SavingsGoalStatus.overdue => (
      icon: Icons.event_busy_outlined,
      label: 'Vencida',
      color: (context) => Theme.of(context).extension<FinanceColors>()!.expense,
    ),
  };
}

class _SavingsGoalCard extends StatefulWidget {
  const _SavingsGoalCard({
    required this.userId,
    required this.goal,
    required this.progress,
    required this.onEdit,
    required this.onUpdateSaved,
    required this.onDelete,
  });

  final String userId;
  final SavingsGoal goal;
  final SavingsGoalProgress progress;
  final VoidCallback onEdit;
  final VoidCallback onUpdateSaved;
  final VoidCallback onDelete;

  @override
  State<_SavingsGoalCard> createState() => _SavingsGoalCardState();
}

/// `Stateful` only for the celebration: the rest of the card stays as
/// "stateless" as before (it receives `progress` already computed,
/// it recomputes nothing). `didUpdateWidget` compares the previous
/// state with the new one to animate a single "bounce" of the status
/// icon right when the goal moves to "Cumplida" — never if it already
/// comes in completed (that isn't a transition) nor on any other
/// change.
class _SavingsGoalCardState extends State<_SavingsGoalCard> with SingleTickerProviderStateMixin {
  late final AnimationController _celebrationController;
  late final Animation<double> _celebrationScale;

  @override
  void initState() {
    super.initState();
    // Provisional duration: `MediaQuery.of` (via `AppMotion.of`)
    // can't be read yet in `initState` (Flutter explicitly forbids
    // it — throws if attempted); it's set for real in
    // `didChangeDependencies`, which runs right after and can.
    _celebrationController = AnimationController(vsync: this, duration: AppMotion.slow);
    _celebrationScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3).chain(CurveTween(curve: Curves.easeOut)), weight: 55),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0).chain(CurveTween(curve: Curves.easeIn)), weight: 45),
    ]).animate(_celebrationController);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _celebrationController.duration = AppMotion.of(context, AppMotion.slow);
  }

  @override
  void didUpdateWidget(covariant _SavingsGoalCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final justCompleted =
        oldWidget.progress.status != SavingsGoalStatus.completed &&
        widget.progress.status == SavingsGoalStatus.completed;
    if (justCompleted && _celebrationController.duration != Duration.zero) {
      _celebrationController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _celebrationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final goal = widget.goal;
    final progress = widget.progress;
    final userId = widget.userId;
    final onEdit = widget.onEdit;
    final onUpdateSaved = widget.onUpdateSaved;
    final onDelete = widget.onDelete;
    final style = _statusStyle(progress.status);
    final statusColor = style.color(context);
    final progressFraction = progress.percent / 100;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    goal.name,
                    style: theme.textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                Semantics(
                  label: 'Estado: ${style.label}',
                  child: ExcludeSemantics(
                    child: ScaleTransition(
                      scale: _celebrationScale,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(style.icon, size: 18, color: statusColor),
                          const SizedBox(width: AppSpacing.xs),
                          Text(style.label, style: theme.textTheme.bodySmall?.copyWith(color: statusColor)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: progressFraction.clamp(0, 1)),
                duration: AppMotion.of(context, AppMotion.base),
                curve: Curves.easeOut,
                builder: (context, value, child) => LinearProgressIndicator(
                  value: value,
                  minHeight: 12,
                  color: statusColor,
                  // Previously `surfaceContainerHighest`: against the
                  // card (`surfaceContainerLow`) it gave less than
                  // 1.1:1 contrast, almost invisible with an empty or
                  // just-created goal. `outline` gives ~3:1 against
                  // the card (WCAG's rough threshold for non-text
                  // components), and it's already used elsewhere in
                  // the theme for borders and secondary icons.
                  backgroundColor: theme.colorScheme.outline,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${progress.percent} % · ${formatCents(goal.savedCents)} de ${formatCents(goal.targetCents)}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              progress.status == SavingsGoalStatus.completed
                  ? 'Fecha límite: ${formatDate(goal.deadline)}'
                  : 'Fecha límite: ${formatDate(goal.deadline)} · aporta ${formatCents(progress.monthlyContributionCents)}/mes '
                        '(quedan ${progress.monthsRemaining} ${progress.monthsRemaining == 1 ? 'mes' : 'meses'})',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (progress.status == SavingsGoalStatus.onTrack || progress.status == SavingsGoalStatus.behind) ...[
              const SizedBox(height: AppSpacing.s),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => SavingsSuggestionsSheet.show(context, userId: userId, goal: goal, progress: progress),
                  icon: const Icon(Icons.lightbulb_outline),
                  label: const Text('¿De dónde puedo ahorrar?'),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.s),
            OverflowBar(
              spacing: AppSpacing.s,
              overflowSpacing: AppSpacing.xs,
              alignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: onUpdateSaved,
                  icon: const Icon(Icons.savings_outlined),
                  label: const Text('Actualizar ahorrado'),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(tooltip: 'Editar', onPressed: onEdit, icon: const Icon(Icons.edit_outlined)),
                    IconButton(
                      tooltip: 'Eliminar',
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

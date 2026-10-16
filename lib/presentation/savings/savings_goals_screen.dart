import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/common/clock.dart';
import '../../domain/savings/savings_goal.dart';
import '../../domain/savings/savings_goal_progress.dart';
import '../common/firestore_error_messages.dart';
import '../common/motion.dart';
import '../common/staggered_entrance.dart';
import '../theme/app_theme.dart';
import '../transactions/formatters.dart';
import 'savings_goal_form_screen.dart';
import 'savings_goal_providers.dart';
import 'savings_suggestions_sheet.dart';
import 'update_saved_amount_dialog.dart';

/// Lista de metas de ahorro del usuario, con su progreso calculado en
/// código (ver `calculateSavingsGoalProgress`, docs/design.md). Funciona
/// sin IA: no depende de `effectiveEnableAi` en ningún punto.
///
/// [clock] es inyectable (por defecto [SystemClock]) solo para que los
/// tests puedan fijar "ahora" al calcular el progreso — mismo patrón que
/// `BuildMonthlyReport`/`BuildMonthEndForecast`, aquí a nivel de pantalla
/// porque el cálculo es una función de dominio pura, sin ningún caso de
/// uso de por medio (ver `SavingsGoalsScreen` en docs/design.md).
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
      appBar: AppBar(title: const Text('Metas de ahorro')),
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

/// Icono, texto y color de [status] — nunca solo el color: el texto ya
/// dice el estado explícitamente, y cada estado tiene también su propio
/// icono.
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

/// `Stateful` solo para la celebración: el resto de la tarjeta sigue
/// siendo tan "sin estado propio" como antes (recibe `progress` ya
/// calculado, no vuelve a calcular nada). `didUpdateWidget` compara el
/// estado anterior con el nuevo para animar un único "rebote" del icono
/// de estado justo cuando la meta pasa a "Cumplida" — nunca si ya entra
/// completada (eso no es una transición) ni en ningún otro cambio.
class _SavingsGoalCardState extends State<_SavingsGoalCard> with SingleTickerProviderStateMixin {
  late final AnimationController _celebrationController;
  late final Animation<double> _celebrationScale;

  @override
  void initState() {
    super.initState();
    // Duración provisional: `MediaQuery.of` (vía `AppMotion.of`) no se
    // puede leer todavía en `initState` (Flutter lo prohíbe de forma
    // explícita — lanza si se intenta); se fija de verdad en
    // `didChangeDependencies`, que se ejecuta justo después y sí puede.
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
                  // Antes `surfaceContainerHighest`: contra la tarjeta
                  // (`surfaceContainerLow`) daba menos de 1,1:1 de contraste,
                  // casi invisible con la meta vacía o recién creada. `outline`
                  // da ~3:1 contra la tarjeta (umbral orientativo de WCAG para
                  // componentes no textuales), y ya se usa en el resto del
                  // tema para bordes e iconos secundarios.
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

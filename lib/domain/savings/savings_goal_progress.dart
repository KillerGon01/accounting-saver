import 'savings_goal.dart';

/// Estado de una meta de ahorro (ver [calculateSavingsGoalProgress]), por
/// orden de prioridad: [completed] siempre gana (aunque la fecha límite ya
/// haya pasado); si no se ha cumplido, [overdue] si la fecha ya pasó;
/// si no, [onTrack]/[behind] según si lo ahorrado alcanza la parte
/// proporcional esperada para hoy.
enum SavingsGoalStatus { completed, onTrack, behind, overdue }

/// Progreso de una meta, calculado en código (nunca a mano ni con IA): lo
/// que queda, el porcentaje, los meses que quedan y cuánto habría que
/// aportar cada mes para llegar a tiempo. Ver [calculateSavingsGoalProgress]
/// para la fórmula exacta de cada campo (documentada también en
/// docs/design.md, "Metas de ahorro").
class SavingsGoalProgress {
  const SavingsGoalProgress({
    required this.remainingCents,
    required this.percent,
    required this.monthsRemaining,
    required this.monthlyContributionCents,
    required this.status,
  });

  /// `max(0, targetCents - savedCents)`.
  final int remainingCents;

  /// Entero, 0-100: `savedCents / targetCents` redondeado al más cercano
  /// (mitad hacia arriba), con tope en 100.
  final int percent;

  /// Meses naturales completos que quedan hasta la fecha límite según el
  /// `Clock` inyectable (nunca negativo; 0 si la fecha límite es este
  /// mismo mes o ya ha pasado).
  final int monthsRemaining;

  /// Cuánto habría que ahorrar cada mes para llegar a [remainingCents] en
  /// [monthsRemaining] meses, redondeado hacia arriba. Con 0 meses, se
  /// divide por 1 (hay que aportar todo el resto ahora mismo). 0 si
  /// [remainingCents] ya es 0.
  final int monthlyContributionCents;

  final SavingsGoalStatus status;
}

/// Calcula el progreso de [goal] a fecha de [now] (siempre inyectado,
/// nunca `DateTime.now()` dentro de esta función: ver `Clock`). Función
/// pura, Dart puro, sin ningún `double`.
///
/// **Meses restantes.** Diferencia de año×12+mes entre [now] y
/// `goal.deadline`, restando 1 si el día de `goal.deadline` todavía no se
/// ha alcanzado este mes (p. ej., hoy 15 y la fecha límite es el día 20
/// de un mes posterior, cuenta como "no completo" ese último tramo);
/// nunca negativo (se recorta a 0).
///
/// **Aportación mensual necesaria.** `remainingCents` dividido entre
/// `max(1, monthsRemaining)`, con división entera **hacia arriba**
/// (`(remaining + divisor - 1) ~/ divisor`): sobraría dinero redondeando
/// hacia abajo, así que se redondea al alza. Con 0 meses, se divide por 1
/// (hay que aportar lo que falta ya, dentro de este mes).
///
/// **Porcentaje.** `savedCents * 100 / targetCents`, redondeado al entero
/// más cercano con media entera hacia arriba (`(saved*100 + target/2) ~/
/// target`), con tope en 100.
///
/// **Estado**, por prioridad (ver [SavingsGoalStatus]):
/// 1. [SavingsGoalStatus.completed] si `savedCents >= targetCents`,
///    siempre, aunque la fecha límite ya haya pasado.
/// 2. [SavingsGoalStatus.overdue] si no se ha cumplido y `now` es
///    posterior a `deadline`.
/// 3. En cualquier otro caso, se compara lo ahorrado con la parte
///    proporcional del objetivo esperada para hoy, según cuánto tiempo ha
///    pasado entre `createdAt` y `deadline` (en milisegundos): si
///    `savedCents` alcanza esa parte, [SavingsGoalStatus.onTrack]; si no,
///    [SavingsGoalStatus.behind].
///
/// **Límite documentado:** si `deadline` no es posterior a `createdAt`
/// (una meta degenerada, con la fecha límite en el pasado desde el
/// principio o igual a su creación), la parte proporcional esperada es
/// directamente el objetivo completo — equivale a exigir todo el ahorro
/// desde el primer día, en vez de dividir por una duración de cero o
/// negativa.
SavingsGoalProgress calculateSavingsGoalProgress(SavingsGoal goal, {required DateTime now}) {
  final remainingCents = goal.targetCents > goal.savedCents ? goal.targetCents - goal.savedCents : 0;

  var monthsRemaining = (goal.deadline.year - now.year) * 12 + (goal.deadline.month - now.month);
  if (goal.deadline.day < now.day) monthsRemaining -= 1;
  if (monthsRemaining < 0) monthsRemaining = 0;

  final divisor = monthsRemaining == 0 ? 1 : monthsRemaining;
  final monthlyContributionCents = remainingCents == 0 ? 0 : (remainingCents + divisor - 1) ~/ divisor;

  var percent = (goal.savedCents * 100 + goal.targetCents ~/ 2) ~/ goal.targetCents;
  if (percent > 100) percent = 100;
  if (percent < 0) percent = 0;

  final SavingsGoalStatus status;
  if (goal.savedCents >= goal.targetCents) {
    status = SavingsGoalStatus.completed;
  } else if (now.isAfter(goal.deadline)) {
    status = SavingsGoalStatus.overdue;
  } else {
    final totalMs = goal.deadline.difference(goal.createdAt).inMilliseconds;
    int expectedProportionalCents;
    if (totalMs <= 0) {
      expectedProportionalCents = goal.targetCents;
    } else {
      final elapsedMs = now.difference(goal.createdAt).inMilliseconds;
      final clampedElapsedMs = elapsedMs < 0 ? 0 : (elapsedMs > totalMs ? totalMs : elapsedMs);
      expectedProportionalCents = (goal.targetCents * clampedElapsedMs) ~/ totalMs;
    }
    status = goal.savedCents >= expectedProportionalCents
        ? SavingsGoalStatus.onTrack
        : SavingsGoalStatus.behind;
  }

  return SavingsGoalProgress(
    remainingCents: remainingCents,
    percent: percent,
    monthsRemaining: monthsRemaining,
    monthlyContributionCents: monthlyContributionCents,
    status: status,
  );
}

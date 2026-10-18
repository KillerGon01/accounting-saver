import 'savings_goal.dart';

/// Status of a savings goal (see [calculateSavingsGoalProgress]), in
/// priority order: [completed] always wins (even if the deadline has
/// already passed); if not met, [overdue] if the date has already
/// passed; otherwise, [onTrack]/[behind] depending on whether what's
/// saved reaches the proportional amount expected for today.
enum SavingsGoalStatus { completed, onTrack, behind, overdue }

/// A goal's progress, computed in code (never by hand or with AI):
/// what's left, the percentage, the months remaining, and how much
/// would need to be contributed each month to arrive on time. See
/// [calculateSavingsGoalProgress] for each field's exact formula (also
/// documented in docs/design.md, "Metas de ahorro").
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

  /// Integer, 0-100: `savedCents / targetCents` rounded to the nearest
  /// (half up), capped at 100.
  final int percent;

  /// Full calendar months remaining until the deadline, according to
  /// the injectable `Clock` (never negative; 0 if the deadline is this
  /// same month or has already passed).
  final int monthsRemaining;

  /// How much would need to be saved each month to reach
  /// [remainingCents] in [monthsRemaining] months, rounded up. With 0
  /// months, it's divided by 1 (the whole remainder has to be
  /// contributed right now). 0 if [remainingCents] is already 0.
  final int monthlyContributionCents;

  final SavingsGoalStatus status;
}

/// Computes [goal]'s progress as of [now] (always injected, never
/// `DateTime.now()` inside this function: see `Clock`). Pure function,
/// pure Dart, no `double` at all.
///
/// **Months remaining.** Year×12+month difference between [now] and
/// `goal.deadline`, subtracting 1 if `goal.deadline`'s day hasn't been
/// reached yet this month (e.g., today is the 15th and the deadline is
/// the 20th of a later month, that last stretch counts as "not
/// complete"); never negative (clamped to 0).
///
/// **Monthly contribution needed.** `remainingCents` divided by
/// `max(1, monthsRemaining)`, with integer division **rounded up**
/// (`(remaining + divisor - 1) ~/ divisor`): rounding down would leave
/// money short, so it rounds up instead. With 0 months, it's divided
/// by 1 (what's missing has to be contributed right now).
///
/// **Percentage.** `savedCents * 100 / targetCents`, rounded to the
/// nearest integer with the half rounded up (`(saved*100 + target/2)
/// ~/ target`), capped at 100.
///
/// **Status**, by priority (see [SavingsGoalStatus]):
/// 1. [SavingsGoalStatus.completed] if `savedCents >= targetCents`,
///    always, even if the deadline has already passed.
/// 2. [SavingsGoalStatus.overdue] if not met and `now` is after
///    `deadline`.
/// 3. Otherwise, what's saved is compared against the proportional
///    part of the target expected for today, based on how much time
///    has passed between `createdAt` and `deadline` (in
///    milliseconds): if `savedCents` reaches that part,
///    [SavingsGoalStatus.onTrack]; if not, [SavingsGoalStatus.behind].
///
/// **Documented limit:** if `deadline` isn't after `createdAt` (a
/// degenerate goal, with the deadline in the past from the start or
/// equal to its creation), the expected proportional part is directly
/// the full target — equivalent to demanding the whole saving from day
/// one, instead of dividing by a zero or negative duration.
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

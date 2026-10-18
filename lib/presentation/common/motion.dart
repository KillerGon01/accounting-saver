import 'package:flutter/material.dart';

/// Durations and single `MediaQuery.disableAnimations` check for all
/// of the app's animations: a single place that decides whether to
/// animate or jump straight to the final state, instead of repeating
/// the check in every widget.
abstract final class AppMotion {
  static const fast = Duration(milliseconds: 150);
  static const base = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 400);

  /// [duration] if animations are active; [Duration.zero] if
  /// `MediaQuery.of(context).disableAnimations` is `true` (the user
  /// has disabled them at the system level) — with zero, Flutter's
  /// implicit widgets (`TweenAnimationBuilder`, `AnimatedOpacity`...)
  /// jump to the final value on the next frame, with no visible
  /// effect.
  static Duration of(BuildContext context, Duration duration) {
    return MediaQuery.of(context).disableAnimations ? Duration.zero : duration;
  }
}

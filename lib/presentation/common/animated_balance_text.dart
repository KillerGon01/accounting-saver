import 'package:flutter/material.dart';

import '../transactions/formatters.dart';
import 'motion.dart';

/// Balance figure that counts from 0 to [cents] (e.g. when opening the
/// screen or changing month). Always ends exactly at
/// `formatCents(cents)` — the `Tween` has [cents] as its upper bound,
/// so the last frame matches the real value, never a different
/// rounded one. With `MediaQuery.disableAnimations`, the final value
/// is shown instantly, with no `TweenAnimationBuilder` involved.
class AnimatedBalanceText extends StatelessWidget {
  const AnimatedBalanceText({super.key, required this.cents, this.style});

  final int cents;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.of(context, AppMotion.slow);
    if (duration == Duration.zero) {
      return Text(formatCents(cents), style: style);
    }
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: cents),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Text(formatCents(value), style: style),
    );
  }
}

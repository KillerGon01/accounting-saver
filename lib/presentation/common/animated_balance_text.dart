import 'package:flutter/material.dart';

import '../transactions/formatters.dart';
import 'motion.dart';

/// Cifra de balance que cuenta desde 0 hasta [cents] (p. ej. al abrir la
/// pantalla o al cambiar de mes). Termina siempre exactamente en
/// `formatCents(cents)` — el `Tween` tiene [cents] como límite superior,
/// así que el último frame coincide con el valor real, nunca uno
/// redondeado distinto. Con `MediaQuery.disableAnimations`, se muestra
/// el valor final al instante, sin ningún `TweenAnimationBuilder` de por
/// medio.
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

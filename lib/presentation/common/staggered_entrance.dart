import 'dart:async';

import 'package:flutter/material.dart';

import 'motion.dart';

/// Entrada escalonada (fundido + deslizamiento corto) para una tarjeta o
/// fila dentro de una lista, sin `AnimationController` propio: un
/// temporizador retrasa el inicio según [index] y `AnimatedOpacity`/
/// `AnimatedSlide` (ambos de Flutter, implícitos) hacen la transición.
/// Mismo patrón de temporizador que ya usa `ChatScreen`/
/// `MonthlyReportScreen` para sus avisos de espera: no bloquea nada, se
/// cancela en `dispose` si el widget desaparece antes de disparar.
///
/// El retraso tiene un tope de [maxStaggeredIndex] elementos: a partir de
/// ahí, todos entran a la vez con el retraso máximo, para que una lista
/// larga no tarde cada vez más en terminar de aparecer.
class StaggeredEntrance extends StatefulWidget {
  const StaggeredEntrance({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  static const maxStaggeredIndex = 8;
  static const _stepDelay = Duration(milliseconds: 40);

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance> {
  bool _visible = false;
  Duration? _delay;
  Timer? _revealTimer;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    _delay = StaggeredEntrance._stepDelay * widget.index.clamp(0, StaggeredEntrance.maxStaggeredIndex);
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    super.dispose();
  }

  void _scheduleReveal(BuildContext context) {
    if (_visible || _scheduled) return;
    _scheduled = true;
    final delay = AppMotion.of(context, _delay!);
    if (delay == Duration.zero) {
      // Sin animación (disableAnimations o retraso nulo): visible ya en
      // este mismo frame, sin ningún temporizador que programar.
      _visible = true;
      return;
    }
    _revealTimer = Timer(delay, () {
      if (!mounted) return;
      setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    _scheduleReveal(context);
    final duration = AppMotion.of(context, AppMotion.base);

    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: duration,
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(0, 0.08),
        duration: duration,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

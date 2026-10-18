import 'dart:async';

import 'package:flutter/material.dart';

import 'motion.dart';

/// Staggered entrance (fade + short slide) for a card or row inside a
/// list, with no `AnimationController` of its own: a timer delays
/// the start based on [index] and `AnimatedOpacity`/`AnimatedSlide`
/// (both Flutter's own, implicit) do the transition. Same timer
/// pattern already used by `ChatScreen`/`MonthlyReportScreen` for
/// their wait notices: it blocks nothing, it's cancelled in
/// `dispose` if the widget disappears before firing.
///
/// The delay is capped at [maxStaggeredIndex] elements: from there
/// on, all of them enter at once with the maximum delay, so a long
/// list doesn't take longer and longer to finish appearing.
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
      // No animation (disableAnimations or zero delay): already
      // visible in this same frame, with no timer to schedule.
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

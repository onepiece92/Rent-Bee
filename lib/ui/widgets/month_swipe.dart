import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Steps through periods with a horizontal swipe, the way Calendar does:
/// swipe left for the next month, right for the previous one.
///
/// A swipe counts when it is flung (faster than [_minVelocity]) or dragged
/// past a quarter of the width; anything smaller — a wobbly vertical scroll —
/// changes nothing. Vertical scrolling is unaffected: the gesture arena
/// gives each drag to the axis it moves along first. A horizontal scroller
/// inside [child] (the sponsor carousel) keeps its own swipes.
///
/// The ‹ › buttons stay as the visible, labelled control; this is a shortcut.
class MonthSwipe extends StatefulWidget {
  final Widget child;
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  const MonthSwipe({
    super.key,
    required this.child,
    required this.onNext,
    required this.onPrevious,
  });

  @override
  State<MonthSwipe> createState() => _MonthSwipeState();
}

class _MonthSwipeState extends State<MonthSwipe> {
  static const _minVelocity = 300.0; // logical px per second
  static const _minShare = 0.25; // of the width, for a slow drag

  double _dx = 0;

  void _onEnd(DragEndDetails d, double width) {
    final v = d.primaryVelocity ?? 0;
    final dx = _dx;
    _dx = 0;
    final flung = v.abs() >= _minVelocity && v.sign == dx.sign;
    final dragged = dx.abs() >= width * _minShare;
    if (dx == 0 || !(flung || dragged)) return;
    HapticFeedback.selectionClick();
    // Content follows the finger: pulling it left brings the next month in.
    dx < 0 ? widget.onNext() : widget.onPrevious();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: (_) => _dx = 0,
        onHorizontalDragUpdate: (d) => _dx += d.primaryDelta ?? 0,
        onHorizontalDragEnd: (d) => _onEnd(d, box.maxWidth),
        onHorizontalDragCancel: () => _dx = 0,
        child: widget.child,
      ),
    );
  }
}

/// Slides [child] in from the side whenever [position] changes — from the
/// right when it moved forward, from the left when it moved back — so a
/// period change reads as a page turn whichever control caused it (swipe,
/// arrows, the today chip). [position] is any ordinal of the period, e.g.
/// `year * 12 + month`. Nothing moves under Reduce Motion.
class SlideOnChange extends StatefulWidget {
  final int position;
  final Widget child;
  const SlideOnChange({super.key, required this.position, required this.child});

  @override
  State<SlideOnChange> createState() => _SlideOnChangeState();
}

class _SlideOnChangeState extends State<SlideOnChange>
    with SingleTickerProviderStateMixin {
  static const _distance = 40.0;
  late final _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: 1,
  );
  late final _curve = CurvedAnimation(
    parent: _ctrl,
    curve: const Cubic(0.32, 0.72, 0, 1),
  );
  double _from = 0; // +1: enters from the right, -1: from the left

  @override
  void didUpdateWidget(SlideOnChange old) {
    super.didUpdateWidget(old);
    if (old.position == widget.position) return;
    if (MediaQuery.disableAnimationsOf(context)) return;
    _from = widget.position > old.position ? 1 : -1;
    _ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    _curve.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) {
        final t = _curve.value;
        if (t >= 1) return child!;
        return Transform.translate(
          offset: Offset(_from * (1 - t) * _distance, 0),
          child: Opacity(opacity: 0.4 + 0.6 * t, child: child),
        );
      },
    );
  }
}

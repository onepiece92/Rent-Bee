import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'glass.dart';

/// A brief, top-of-screen toast (a glass capsule, like a system HUD) shown in
/// the root overlay — so it floats above the tab bar, sheets, and dialogs.
/// Use [showToast] from a live context, or [showToastOn] with an
/// [OverlayState] captured before an `await`.
void showToast(BuildContext context, String message, {bool error = false}) =>
    showToastOn(Overlay.of(context, rootOverlay: true), message, error: error);

OverlayEntry? _active;

void showToastOn(OverlayState overlay, String message, {bool error = false}) {
  // Only one toast at a time — replace any currently showing.
  _active?.remove();
  _active = null;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _Toast(
      message: message,
      error: error,
      onDismissed: () {
        if (entry.mounted) entry.remove();
        if (identical(_active, entry)) _active = null;
      },
    ),
  );
  _active = entry;
  overlay.insert(entry);
}

class _Toast extends StatefulWidget {
  final String message;
  final bool error;
  final VoidCallback onDismissed;
  const _Toast(
      {required this.message, required this.error, required this.onDismissed});

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 220));
  late final Animation<double> _fade =
      CurvedAnimation(parent: _c, curve: Motion.fade);
  late final Animation<Offset> _slide =
      Tween(begin: const Offset(0, -0.4), end: Offset.zero)
          .animate(CurvedAnimation(parent: _c, curve: Motion.move));
  bool _shown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Under Reduce Motion the toast appears and leaves in place (a zero
    // duration completes the controller instantly).
    _c.duration = Motion.duration(context, const Duration(milliseconds: 220));
    if (_shown) return;
    _shown = true;
    _c.forward();
    // Hold, then animate out and remove.
    Future.delayed(const Duration(milliseconds: 2600), () async {
      if (!mounted) return;
      await _c.reverse();
      widget.onDismissed();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Align(
            alignment: Alignment.topCenter,
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _slide,
                child: Semantics(
                  liveRegion: true,
                  child: Glass(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 11),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                              widget.error
                                  ? Icons.error_outline
                                  : Icons.check_circle_outline,
                              size: 18,
                              color:
                                  widget.error ? sys.redText : sys.greenText),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(widget.message,
                                style: Type.footnote.semibold
                                    .colored(sys.label)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

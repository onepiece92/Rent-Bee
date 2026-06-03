import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// A brief, top-of-screen toast shown in the root overlay — so it floats above
/// the footer nav bar, bottom sheets, and dialogs. Use [showToast] from a live
/// context, or [showToastOn] with an [OverlayState] captured before an `await`.
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
      CurvedAnimation(parent: _c, curve: Curves.easeOut);
  late final Animation<Offset> _slide =
      Tween(begin: const Offset(0, -0.4), end: Offset.zero).animate(_fade);

  @override
  void initState() {
    super.initState();
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
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 460),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xF21A2546),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: widget.error
                              ? Colors.redAccent.withValues(alpha: 0.6)
                              : Brand.glassBorder),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0x66060618),
                            blurRadius: 24,
                            offset: Offset(0, 8)),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                            widget.error
                                ? Icons.error_outline
                                : Icons.check_circle_outline,
                            size: 17,
                            color: widget.error
                                ? Colors.redAccent
                                : Brand.paidText),
                        const SizedBox(width: 9),
                        Flexible(
                          child: Text(widget.message,
                              style: const TextStyle(
                                  color: Brand.text,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
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
    );
  }
}

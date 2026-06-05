import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Presents a [GlassDialog]. The modal barrier is transparent — the dialog
/// paints its own soft full-screen frost so the background gradient + orbs stay
/// visible (blurred) behind the popup.
Future<T?> showGlassDialog<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierColor: Colors.transparent,
    barrierDismissible: barrierDismissible,
    // The dialog frosts the full screen itself — don't inset it from the safe
    // area, or the notch/home-indicator strips would stay unfrosted.
    useSafeArea: false,
    builder: builder,
  );
}

/// A flat, borderless dialog action — the airy popup style leans on type, not
/// button chrome. [primary] tints it orange, [destructive] tints it red, and a
/// null [onPressed] renders it disabled.
class GlassDialogAction {
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final bool destructive;
  const GlassDialogAction(
    this.label, {
    this.onPressed,
    this.primary = false,
    this.destructive = false,
  });
}

/// A minimal, airy glassmorphic popup: a large Fraunces title, generous
/// whitespace, a very subtle frosted panel, and flat text actions.
///
/// Drop-in for `AlertDialog`: keep the surrounding
/// `showDialog(context: ..., builder: (ctx) => GlassDialog(...))` so action
/// callbacks can still `Navigator.pop(ctx, ...)`.
class GlassDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final List<GlassDialogAction> actions;
  const GlassDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets;
    return Stack(
      children: [
        // Soft full-screen frost — keeps the gradient/orbs visible but blurred.
        // IgnorePointer lets an outside tap fall through to the modal barrier.
        Positioned.fill(
          child: IgnorePointer(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: const ColoredBox(color: Color(0x330A0819)),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(
            left: 30,
            right: 30,
            top: 24 + insets.top,
            bottom: 24 + insets.bottom,
          ),
          child: Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {}, // absorb taps so the card doesn't dismiss
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: _Card(title: title, content: content, actions: actions),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final Widget content;
  final List<GlassDialogAction> actions;
  const _Card({
    required this.title,
    required this.content,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(30));
    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(color: Color(0x59060618), blurRadius: 44, offset: Offset(0, 20)),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              // Very subtle white frost — airy, lets the blur read through.
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.12),
                  Colors.white.withValues(alpha: 0.04),
                ],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 30, 28, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: display(
                            fontSize: 25,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.4)),
                    const SizedBox(height: 20),
                    Flexible(
                      child: SingleChildScrollView(
                        child: DefaultTextStyle.merge(
                          style: const TextStyle(
                              color: Brand.muted, fontSize: 14, height: 1.45),
                          child: content,
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        for (var i = 0; i < actions.length; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          _ActionButton(action: actions[i]),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final GlassDialogAction action;
  const _ActionButton({required this.action});

  @override
  Widget build(BuildContext context) {
    final enabled = action.onPressed != null;
    final Color color;
    if (!enabled) {
      color = Brand.muted.withValues(alpha: 0.35);
    } else if (action.destructive) {
      color = const Color(0xFFFF6B6B);
    } else if (action.primary) {
      color = Brand.orange;
    } else {
      color = Brand.muted;
    }
    return TextButton(
      onPressed: action.onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: TextStyle(
          fontSize: 14.5,
          fontWeight: action.primary || action.destructive
              ? FontWeight.w700
              : FontWeight.w600,
        ),
      ),
      child: Text(action.label),
    );
  }
}

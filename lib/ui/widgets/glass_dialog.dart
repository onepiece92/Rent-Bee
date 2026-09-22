import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'glass.dart';

/// Presents a [GlassDialog] (an alert) over a dimmed page.
Future<T?> showGlassDialog<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.3),
    barrierDismissible: barrierDismissible,
    builder: builder,
  );
}

/// An alert action. [primary] renders it semibold in the tint, [destructive]
/// in red, and a null [onPressed] renders it disabled.
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

/// An alert on regular Liquid Glass (HIG, Materials: glass for anything with
/// a lot of text): a centred headline title, the content beneath it, and the
/// actions as full-width rows separated by hairlines — side by side for two,
/// stacked for more, like a system alert.
///
/// Drop-in for `AlertDialog`: keep the surrounding
/// `showGlassDialog(context, (ctx) => GlassDialog(...))` so action callbacks
/// can still `Navigator.pop(ctx, ...)`.
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
    final sys = Sys.of(context);
    final insets = MediaQuery.viewInsetsOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + insets.bottom),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Glass(
            borderRadius: BorderRadius.circular(Sys.radiusCard),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(title,
                            textAlign: TextAlign.center,
                            style: Type.headline.colored(sys.label)),
                        const SizedBox(height: 10),
                        Flexible(
                          child: SingleChildScrollView(
                            child: DefaultTextStyle.merge(
                              style: Type.footnote.colored(sys.secondaryLabel),
                              child: content,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  if (actions.length == 2)
                    IntrinsicHeight(
                      child: Row(
                        children: [
                          Expanded(child: _ActionButton(action: actions[0])),
                          const VerticalDivider(width: 0.5, thickness: 0.5),
                          Expanded(child: _ActionButton(action: actions[1])),
                        ],
                      ),
                    )
                  else
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const Divider(),
                      _ActionButton(action: actions[i]),
                    ],
                ],
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
    final sys = Sys.of(context);
    final enabled = action.onPressed != null;
    final Color color;
    if (!enabled) {
      color = sys.tertiaryLabel;
    } else if (action.destructive) {
      color = sys.redText;
    } else {
      color = sys.tintText;
    }
    final weight = action.primary || action.destructive
        ? FontWeight.w600
        : FontWeight.w400;
    return TextButton(
      onPressed: action.onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        disabledForegroundColor: color,
        minimumSize: const Size.fromHeight(Sys.minTapTarget),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        shape: const RoundedRectangleBorder(),
        textStyle: Type.body.copyWith(fontWeight: weight),
      ),
      child: Text(action.label,
          maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

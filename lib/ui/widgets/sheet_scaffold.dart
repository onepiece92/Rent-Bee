import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Presents a sheet (HIG, Sheets): anchored to the bottom, 22 pt top radii,
/// a 36 × 5 grabber, the elevated card background, drag to dismiss, and
/// keyboard-aware. Rises above the shell's tab bar so the bar never overlaps
/// the sheet's lower content.
Future<T?> showSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (ctx) => _Sheet(child: Builder(builder: builder)),
  );
}

/// Old name, kept so call sites migrate one at a time.
Future<T?> showGlassSheet<T>(BuildContext context, WidgetBuilder builder) =>
    showSheet<T>(context, builder);

class _Sheet extends StatelessWidget {
  final Widget child;
  const _Sheet({required this.child});

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxH = MediaQuery.sizeOf(context).height * 0.88;
    const radius = BorderRadius.vertical(top: Radius.circular(Sys.radiusCard));
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Material(
        color: sys.card,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                  Sys.gutter, 8, Sys.gutter, Sys.gutter + 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Grabber (kit: 36 × 5).
                  Container(
                    width: 36,
                    height: 5,
                    margin: const EdgeInsets.only(top: 2, bottom: 14),
                    decoration: BoxDecoration(
                      color: sys.fill,
                      borderRadius:
                          BorderRadius.circular(Sys.radiusCapsule),
                    ),
                  ),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

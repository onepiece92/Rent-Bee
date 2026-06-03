import 'dart:ui';

import 'package:flutter/material.dart';

/// Presents a bottom sheet styled like the prototype `Sheet`:
/// translucent navy glass, top border, grabber, slide-up, keyboard-aware.
Future<T?> showGlassSheet<T>(
  BuildContext context,
  WidgetBuilder builder,
) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    // Present above the shell's footer nav bar so the sheet (and its barrier)
    // cover it, instead of the nav bar overlapping the sheet's lower content.
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x800A0819), // rgba(10,8,25,.5)
    builder: (ctx) => _GlassSheet(child: Builder(builder: builder)),
  );
}

class _GlassSheet extends StatelessWidget {
  final Widget child;
  const _GlassSheet({required this.child});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final maxH = MediaQuery.of(context).size.height * 0.85;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            constraints: BoxConstraints(maxHeight: maxH),
            decoration: BoxDecoration(
              color: const Color(0xC7141E3A), // rgba(20,30,58,.78)
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 10, 22, 26),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 38,
                      height: 4,
                      margin: const EdgeInsets.only(top: 4, bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    child,
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

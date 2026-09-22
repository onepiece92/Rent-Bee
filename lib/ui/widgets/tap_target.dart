import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Gives a small custom control the HIG's minimum 44 × 44 pt hit area without
/// changing how it looks: [child] keeps its own size, centred inside a fixed
/// square that owns the tap surface (an [InkWell], so the press state comes
/// with it). Use it for icon buttons and chips drawn smaller than 44 pt —
/// Material's own buttons already pad themselves.
class TapTarget extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final double size;

  const TapTarget({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius,
    this.size = Sys.minTapTarget,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius ?? BorderRadius.circular(size / 2),
        child: SizedBox.square(
          dimension: size,
          child: Center(child: child),
        ),
      ),
    );
  }
}

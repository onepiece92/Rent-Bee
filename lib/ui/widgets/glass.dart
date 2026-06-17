import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// The navy gradient background with four soft drifting orbs + a fine grain
/// overlay (ported from the prototype's `bg` / `orb` / `grain` styles).
class BrandBackground extends StatelessWidget {
  final Widget child;
  const BrandBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(-0.7, -1),
          end: Alignment(0.7, 1),
          colors: [Brand.bgTop, Brand.bgMid, Brand.bgBottom],
          stops: [0, 0.45, 1],
        ),
      ),
      child: Stack(
        children: [
          const Positioned.fill(child: _OrbField()),
          const Positioned.fill(child: _Grain()),
          child,
        ],
      ),
    );
  }
}

class _OrbField extends StatefulWidget {
  const _OrbField();
  @override
  State<_OrbField> createState() => _OrbFieldState();
}

class _OrbFieldState extends State<_OrbField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // (color, size, top, left, right, bottom, phase)
    const orbs = [
      (Brand.orange, 260.0, -60.0, -50.0, null, null, 0.0),
      (Brand.orbBlue, 220.0, 120.0, null, -70.0, null, -4 / 14),
      (Brand.orangeWarm, 240.0, null, -60.0, null, 80.0, -8 / 14),
      (Brand.navy, 200.0, null, null, -30.0, -50.0, -2 / 14),
    ];
    return ClipRect(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return Stack(
            children: [
              for (final o in orbs)
                _DriftingOrb(
                  t: (_c.value + o.$7) % 1.0,
                  color: o.$1,
                  size: o.$2,
                  top: o.$3,
                  left: o.$4,
                  right: o.$5,
                  bottom: o.$6,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DriftingOrb extends StatelessWidget {
  final double t; // 0..1 cycle
  final Color color;
  final double size;
  final double? top, left, right, bottom;

  const _DriftingOrb({
    required this.t,
    required this.color,
    required this.size,
    this.top,
    this.left,
    this.right,
    this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    // drift: midpoint of cycle offsets by (18,-22) and scales 1.08
    final phase = (0.5 - (t - 0.5).abs()) * 2; // 0→1→0 triangle
    final dx = 18 * phase;
    final dy = -22 * phase;
    final scale = 1 + 0.08 * phase;
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      child: Transform.translate(
        offset: Offset(dx, dy),
        child: Transform.scale(
          scale: scale,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Grain extends StatelessWidget {
  const _Grain();
  @override
  Widget build(BuildContext context) {
    // RepaintBoundary isolates the static grain into its own layer so the
    // animated orb sibling's repaints don't re-run _GrainPainter's ~35k circles.
    return IgnorePointer(
      child: RepaintBoundary(
        child: Opacity(
          opacity: 0.25,
          child: CustomPaint(painter: _GrainPainter()),
        ),
      ),
    );
  }
}

class _GrainPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.10);
    const step = 3.0;
    for (double y = 0; y < size.height; y += step) {
      for (double x = 0; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 0.5, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A frosted glass panel: dark tint + backdrop blur + border + top sheen +
/// outer drop shadow (matching the prototype `glass` style).
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;
  final bool sheen;

  /// Live backdrop blur. The translucent navy fill reads as glass on its own, so
  /// list tiles pass `blur: false` — a live [BackdropFilter] per row is a major
  /// scroll-jank source (N blur layers). Keep it on for hero/standalone panels.
  final bool blur;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius,
    this.onTap,
    this.sheen = false,
    this.blur = true,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(22);

    final inner = DecoratedBox(
      decoration: BoxDecoration(
        color: Brand.glassBg,
        borderRadius: radius,
        border: Border.all(color: Brand.glassBorder),
      ),
      child: Stack(
        children: [
          if (sheen)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: FractionallySizedBox(
                widthFactor: 1,
                child: Container(
                  height: 90,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.16),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: radius,
              child: Padding(padding: padding, child: child),
            ),
          ),
        ],
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x66060618), // 0 8px 32px rgba(6,6,24,.4)
            blurRadius: 32,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: blur
            ? BackdropFilter(
                filter: ImageFilter.blur(
                    sigmaX: Brand.glassBlur, sigmaY: Brand.glassBlur),
                child: inner,
              )
            : inner,
      ),
    );
  }
}

/// Unit code avatar — rounded square, green tint when paid (prototype `avatar`).
class CodeAvatar extends StatelessWidget {
  final String code;
  final bool paid;
  final double size;
  const CodeAvatar({
    super.key,
    required this.code,
    required this.paid,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: paid ? Brand.paidPillBg : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(size * 0.29),
        border: Border.all(
            color: paid ? Brand.paidPillBorder : Brand.glassBorder),
      ),
      child: Text(
        code,
        style: display(
          fontSize: size > 48 ? 15 : 13,
          fontWeight: FontWeight.w600,
          color: paid ? Brand.paidText : Colors.white,
        ),
      ),
    );
  }
}

/// Paid / pending status pill (green vs translucent orange).
class StatusPill extends StatelessWidget {
  final bool paid;
  const StatusPill({super.key, required this.paid});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: paid ? Brand.paidPillBg : Brand.pillBg,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
            color: paid ? Brand.paidPillBorder : Brand.pillBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (paid) ...[
            const Icon(Icons.check, size: 12, color: Brand.paidText),
            const SizedBox(width: 4),
          ],
          Text(paid ? 'Paid' : 'Pending',
              style: TextStyle(
                color: paid ? Brand.paidText : Brand.orangeSoft,
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
              )),
        ],
      ),
    );
  }
}

/// Rounded progress bar with orange gradient fill + glow (prototype `barFill`).
class BrandProgressBar extends StatelessWidget {
  final double value; // 0..1
  const BrandProgressBar({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: Container(
        height: 8,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: value.clamp(0, 1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              decoration: BoxDecoration(
                gradient: Brand.orangeGradient,
                borderRadius: BorderRadius.circular(99),
                boxShadow: [
                  BoxShadow(
                    color: Brand.orange.withValues(alpha: 0.55),
                    blurRadius: 14,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

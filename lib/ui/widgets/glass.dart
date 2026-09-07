import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// The navy gradient background with four soft orbs + a fine grain overlay
/// (ported from the prototype's `bg` / `orb` / `grain` styles).
///
/// This sits under every screen, so it is deliberately static and cheap: the
/// orbs are radial-gradient discs (not live blurs) and no longer drift. A
/// moving background forced every [BackdropFilter] above it to re-sample each
/// frame — the app's single largest steady-state GPU cost; now the whole layer
/// is composited once and left alone until something real changes.
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

/// The four orbs, laid out once inside their own repaint boundary.
class _OrbField extends StatelessWidget {
  const _OrbField();

  @override
  Widget build(BuildContext context) {
    // (color, size, top, left, right, bottom)
    const orbs = [
      (Brand.orange, 260.0, -60.0, -50.0, null, null),
      (Brand.orbBlue, 220.0, 120.0, null, -70.0, null),
      (Brand.orangeWarm, 240.0, null, -60.0, null, 80.0),
      (Brand.navy, 200.0, null, null, -30.0, -50.0),
    ];
    return ClipRect(
      child: RepaintBoundary(
        child: Stack(
          children: [
            for (final o in orbs)
              _Orb(
                color: o.$1,
                size: o.$2,
                top: o.$3,
                left: o.$4,
                right: o.$5,
                bottom: o.$6,
              ),
          ],
        ),
      ),
    );
  }
}

class _Orb extends StatelessWidget {
  final Color color;
  final double size;
  final double? top, left, right, bottom;

  const _Orb({
    required this.color,
    required this.size,
    this.top,
    this.left,
    this.right,
    this.bottom,
  });

  /// How far the soft edge extends past the disc — stands in for the ~σ=60
  /// blur halo the prototype had, so the orbs keep their size and placement.
  static const _halo = 60.0;

  @override
  Widget build(BuildContext context) {
    // The gradient box is the disc plus its halo, so pull each anchored edge
    // back by the halo to keep the visible centre where the blurred disc was.
    return Positioned(
      top: top == null ? null : top! - _halo,
      left: left == null ? null : left! - _halo,
      right: right == null ? null : right! - _halo,
      bottom: bottom == null ? null : bottom! - _halo,
      child: Container(
        width: size + 2 * _halo,
        height: size + 2 * _halo,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: 0.5),
              color.withValues(alpha: 0.28),
              color.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.45, 1.0],
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
    // RepaintBoundary isolates the static grain into its own layer so a repaint
    // anywhere else never re-runs _GrainPainter's ~35k circles.
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

  /// Outer drop shadow. It's a 32px Gaussian blur of the panel's outline, so
  /// like [blur] it costs a blur pass per panel per frame — list tiles pass
  /// `shadow: false` (it's barely visible on the navy background anyway).
  final bool shadow;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius,
    this.onTap,
    this.sheen = false,
    this.blur = true,
    this.shadow = true,
  });

  /// The cheap variant for list rows and small repeated tiles: no backdrop
  /// blur and no drop shadow, so a screen full of them costs no blur passes.
  const GlassPanel.tile({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius,
    this.onTap,
  })  : sheen = false,
        blur = false,
        shadow = false;

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
        boxShadow: shadow
            ? const [
                BoxShadow(
                  color: Color(0x66060618), // 0 8px 32px rgba(6,6,24,.4)
                  blurRadius: 32,
                  offset: Offset(0, 8),
                ),
              ]
            : null,
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

import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// The app's surfaces and controls, built to the Apple brand kit's layer
/// model (HIG, Materials):
///
///   • **Content layer** — [PageBackground], [GroupedCard], [ListRow],
///     [Hairline], [SectionTitle], [StatusBadge], [CodeAvatar], [ProgressBar].
///     Solid grouped backgrounds. Never Liquid Glass.
///   • **Control layer** — [Glass], [GlassIconButton], [SegmentedControl],
///     [AppButton] (its `glass` kind), [ScrollEdge]. Floats above content;
///     content scrolls underneath. Glass is used sparingly, on the most
///     important functional elements only.

// ---------------------------------------------------------------------------
// Content layer
// ---------------------------------------------------------------------------

/// The page: systemGroupedBackground, nothing else.
class PageBackground extends StatelessWidget {
  final Widget child;
  const PageBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: Sys.of(context).bg, child: child);
}

/// A grouped card (kit): secondarySystemGroupedBackground on the page colour,
/// no border, 22 pt radius, 16 pt padding. Tappable when [onTap] is set, with
/// the ink clipped to the card. `.tile` is the same look — kept as a named
/// constructor so list-row call sites read as intended.
class GroupedCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;

  const GroupedCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Sys.gutter),
    this.borderRadius,
    this.onTap,
  });

  const GroupedCard.tile({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Sys.gutter),
    this.borderRadius,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    final radius = borderRadius ?? BorderRadius.circular(Sys.radiusCard);
    return Material(
      color: sys.card,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// A well inside a card: tertiarySystemGroupedBackground, 14 pt radius —
/// concentric with the card's 22 pt corners at 16 pt padding (kit).
class Well extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  const Well({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    return Material(
      color: sys.well,
      borderRadius: BorderRadius.circular(Sys.radiusWell),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Card / section header: Title 3 semibold, sentence case, never uppercase
/// (kit). [trailing] is for a small action next to the heading.
class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  const SectionTitle(
    this.text, {
    super.key,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(Sys.gutter, 0, Sys.gutter, 8),
  });

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.title3.semibold.colored(sys.label)),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A row inside a grouped card (kit): 44 pt minimum height on touch, the
/// title in `label`, the detail in secondary text, a trailing accessory
/// (chevron, value, button). Separate rows with [Hairline].
class ListRow extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool chevron;
  final bool destructive;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  const ListRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.chevron = false,
    this.destructive = false,
    this.onTap,
    this.padding =
        const EdgeInsets.symmetric(horizontal: Sys.gutter, vertical: 10),
  });

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Sys.minTapTarget),
        child: Padding(
          padding: padding,
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 12)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        style: Type.body.colored(
                            destructive ? sys.redText : sys.label)),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(subtitle!,
                          style: Type.footnote.colored(sys.secondaryLabel)),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
              if (chevron) ...[
                const SizedBox(width: 6),
                Icon(Icons.chevron_right, size: 20, color: sys.tertiaryLabel),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Hairline separator between rows, inset from the leading edge like iOS.
class Hairline extends StatelessWidget {
  final double inset;
  const Hairline({super.key, this.inset = Sys.gutter});

  @override
  Widget build(BuildContext context) =>
      Padding(padding: EdgeInsets.only(left: inset), child: const Divider());
}

/// iOS Settings icon tile: a 28 pt rounded square in a colour with a white
/// glyph, at the leading edge of a [ListRow].
class IconTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const IconTile({
    super.key,
    required this.icon,
    required this.color,
    this.size = 28,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.25),
      ),
      child: Icon(icon, size: size * 0.6, color: Colors.white),
    );
  }
}

/// Status badge (kit): a capsule filled with the status colour at 15%, a 6 pt
/// dot in the full colour and a text-safe label — never colour alone.
class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;
  final IconData? icon;
  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    required this.textColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Sys.wash(color),
        borderRadius: BorderRadius.circular(Sys.radiusCapsule),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: 12, color: textColor)
          else
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          const SizedBox(width: 6),
          Text(label,
              style: Type.caption1.semibold.colored(textColor).tabular),
        ],
      ),
    );
  }
}

/// Paid / pending status as a [StatusBadge].
class StatusPill extends StatelessWidget {
  final bool paid;
  const StatusPill({super.key, required this.paid});

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    return paid
        ? StatusBadge(
            label: 'Paid',
            color: sys.green,
            textColor: sys.greenText,
            icon: Icons.check)
        : StatusBadge(
            label: 'Pending', color: sys.orange, textColor: sys.orangeText);
  }
}

/// Unit-code avatar: a rounded-square tile in the tint (green once paid) with
/// the code in tabular figures.
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
    final sys = Sys.of(context);
    final color = paid ? sys.green : sys.tint;
    final text = paid ? sys.greenText : sys.tintText;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Sys.wash(color),
        borderRadius: BorderRadius.circular(size * 0.25),
      ),
      child: Text(
        code,
        maxLines: 1,
        style: (size > 48 ? Type.subhead : Type.footnote)
            .semibold
            .colored(text)
            .tabular,
      ),
    );
  }
}

/// Progress (kit): a 6 pt capsule track in systemFill; the fill in the tint,
/// green once complete. Animates through [Motion] (instant under Reduce
/// Motion).
class ProgressBar extends StatelessWidget {
  final double value; // 0..1
  final Color? color;
  const ProgressBar({super.key, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    final v = value.clamp(0.0, 1.0).toDouble();
    final fill = v >= 1 ? sys.green : (color ?? sys.tint);
    return ClipRRect(
      borderRadius: BorderRadius.circular(Sys.radiusCapsule),
      child: SizedBox(
        height: 6,
        child: DecoratedBox(
          decoration: BoxDecoration(color: sys.fill),
          child: AnimatedFractionallySizedBox(
            duration: Motion.duration(context, Motion.moveDuration),
            curve: Motion.move,
            alignment: Alignment.centerLeft,
            widthFactor: v,
            heightFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(Sys.radiusCapsule),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Control layer
// ---------------------------------------------------------------------------

/// Liquid Glass, web-translation recipe: backdrop blur + saturation, a tint,
/// a thin light rim along the top, a hairline edge and a soft shadow.
/// Regular glass for controls and anything with text; [tinted] is the
/// "stained glass" for one primary action — the tint on the *background*,
/// white label. Increase Contrast raises the tint to ~94% (kit).
///
/// Control layer only: tab bar, toolbar buttons, segmented controls, menus,
/// alerts, toasts. Never on cards or list rows (HIG, Materials).
class Glass extends StatelessWidget {
  final Widget child;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry padding;
  final bool tinted;
  final bool shadow;

  const Glass({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding = EdgeInsets.zero,
    this.tinted = false,
    this.shadow = true,
  });

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    final radius = borderRadius ?? BorderRadius.circular(Sys.radiusCapsule);
    final highContrast = MediaQuery.highContrastOf(context);
    final Color fill;
    if (tinted) {
      fill = sys.tint.withValues(alpha: highContrast ? 0.98 : 0.88);
    } else if (highContrast) {
      fill = sys.glassTint.withValues(alpha: 0.94);
    } else {
      fill = sys.glassTint;
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: shadow
            ? [
                BoxShadow(
                    color: sys.glassShadow,
                    blurRadius: 28,
                    offset: const Offset(0, 8)),
                BoxShadow(
                    color: sys.glassShadow.withValues(
                        alpha: sys.isDark ? 0.3 : 0.06),
                    blurRadius: 3,
                    offset: const Offset(0, 1)),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: Sys.glassFilter(),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: radius,
              border: Border.all(
                  color: highContrast
                      ? sys.glassEdge.withValues(alpha: 0.5)
                      : sys.glassEdge,
                  width: 0.5),
            ),
            child: Stack(
              children: [
                // Top rim highlight (inset 0 0.5px 0 rim), clipped by the
                // rounded corners.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 0.5,
                  child: ColoredBox(color: tinted ? Colors.white54 : sys.glassRim),
                ),
                Padding(padding: padding, child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A 44 pt glass circle with an icon — toolbar buttons, back buttons.
/// [prominent] makes it the tinted primary action.
class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool prominent;
  final String? semanticLabel;
  final double size;

  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.prominent = false,
    this.semanticLabel,
    this.size = Sys.minTapTarget,
  });

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Pressable(
        child: Glass(
          tinted: prominent,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              customBorder: const StadiumBorder(),
              child: SizedBox.square(
                dimension: size,
                child: Icon(icon,
                    size: 20, color: prominent ? sys.onTint : sys.label),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Button styles (kit): style signals priority, not size. One or two
/// prominent buttons per view; a destructive action is never prominent.
/// [prominentGlass] is the toolbar's primary action: tinted ("stained")
/// glass with a white label.
enum ButtonKind { prominent, tinted, gray, destructive, plain, glass, prominentGlass }

/// A capsule button with a semibold label, an optional leading icon, a press
/// state, and a [busy] mode that shows an activity indicator inside the button
/// (pass the changed label yourself, e.g. "Saving…").
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final ButtonKind kind;
  final IconData? icon;
  final bool busy;
  final bool expand;
  final bool compact;

  const AppButton({
    super.key,
    required this.label,
    required this.onTap,
    this.kind = ButtonKind.prominent,
    this.icon,
    this.busy = false,
    this.expand = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    final (Color bg, Color fg) = switch (kind) {
      ButtonKind.prominent => (sys.tint, sys.onTint),
      ButtonKind.tinted => (Sys.wash(sys.tint), sys.tintText),
      ButtonKind.gray => (sys.tertiaryFill, sys.label),
      ButtonKind.destructive => (Sys.wash(sys.red, 0.12), sys.redText),
      ButtonKind.plain => (Colors.transparent, sys.tintText),
      ButtonKind.glass => (Colors.transparent, sys.label),
      ButtonKind.prominentGlass => (Colors.transparent, sys.onTint),
    };
    final enabled = onTap != null && !busy;
    final style = (compact ? Type.subhead : Type.body).semibold.colored(fg);
    Widget content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy) ...[
          SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          ),
          const SizedBox(width: 8),
        ] else if (icon != null) ...[
          Icon(icon, size: compact ? 16 : 18, color: fg),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(label,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
        ),
      ],
    );
    content = Padding(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 14 : 20, vertical: compact ? 9 : 12),
      child: content,
    );
    // The capsule is the artwork; a compact one is 34 pt tall. The hit area
    // around it is always ≥ 44 pt (HIG: the target, not the artwork).
    final capsule = ConstrainedBox(
      constraints:
          BoxConstraints(minHeight: compact ? 34 : Sys.minTapTarget),
      child: DecoratedBox(
        decoration: ShapeDecoration(color: bg, shape: const StadiumBorder()),
        child: content,
      ),
    );
    final artwork = switch (kind) {
      ButtonKind.glass => Glass(child: capsule),
      ButtonKind.prominentGlass => Glass(tinted: true, child: capsule),
      _ => capsule,
    };
    return Opacity(
      opacity: enabled || busy ? 1 : 0.4,
      child: Pressable(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            customBorder: const StadiumBorder(),
            // iOS buttons dim and scale rather than ripple (see Pressable).
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: Sys.minTapTarget),
              child: Center(widthFactor: 1, heightFactor: 1, child: artwork),
            ),
          ),
        ),
      ),
    );
  }
}

/// Segmented control (kit): a capsule track — glass on the toolbar, or
/// tertiarySystemFill inside a card — with the selected segment as a solid
/// capsule carrying a small shadow.
class SegmentedControl<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onChanged;
  final bool glass;

  const SegmentedControl({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    required this.onChanged,
    this.glass = false,
  });

  @override
  Widget build(BuildContext context) {
    final sys = Sys.of(context);
    final knob = sys.isDark ? const Color(0xFF636366) : Colors.white;
    final track = Padding(
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          for (final v in values)
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onChanged(v),
                  customBorder: const StadiumBorder(),
                  child: AnimatedContainer(
                    duration: Motion.duration(context, Motion.quick),
                    curve: Motion.fade,
                    constraints: const BoxConstraints(
                        minHeight: Sys.minTapTarget - 6),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: v == selected ? knob : Colors.transparent,
                      borderRadius: BorderRadius.circular(Sys.radiusCapsule),
                      boxShadow: v == selected
                          ? [
                              BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.12),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2)),
                            ]
                          : null,
                    ),
                    child: Text(
                      label(v),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Type.footnote.semibold.colored(
                          v == selected ? sys.label : sys.secondaryLabel),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    if (glass) return Glass(child: track);
    return Material(
      color: sys.tertiaryFill,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: track,
    );
  }
}

/// Scroll edge effect (HIG, Layout): a fade from the page colour under a
/// floating bar, instead of a solid bar background. Place behind the tab bar
/// (`bottom`) or a floating toolbar (`top`), ignoring pointers.
class ScrollEdge extends StatelessWidget {
  final bool bottom;
  final double height;
  const ScrollEdge.bottom({super.key, this.height = 110}) : bottom = true;
  const ScrollEdge.top({super.key, this.height = 90}) : bottom = false;

  @override
  Widget build(BuildContext context) {
    final bg = Sys.of(context).bg;
    return IgnorePointer(
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: bottom ? Alignment.bottomCenter : Alignment.topCenter,
            end: bottom ? Alignment.topCenter : Alignment.bottomCenter,
            colors: [bg, bg.withValues(alpha: 0.7), bg.withValues(alpha: 0)],
            stops: const [0, 0.45, 1],
          ),
        ),
      ),
    );
  }
}

/// Press state for custom controls (HIG, Buttons): dims to 75% and scales to
/// 0.96 while pressed. Under Reduce Motion only the dim remains — a state
/// change, not movement.
class Pressable extends StatefulWidget {
  final Widget child;
  const Pressable({super.key, required this.child});

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final reduced = Motion.reduced(context);
    return Listener(
      onPointerDown: (_) => setState(() => _down = true),
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: AnimatedOpacity(
        opacity: _down ? 0.75 : 1,
        duration: Motion.duration(context, Motion.quick),
        curve: Motion.fade,
        child: AnimatedScale(
          scale: _down && !reduced ? Motion.pressScale : 1,
          duration: Motion.duration(context, Motion.quick),
          curve: Motion.fade,
          child: widget.child,
        ),
      ),
    );
  }
}

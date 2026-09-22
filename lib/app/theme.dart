import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Rent Bee's theme, built to the Apple brand kit (HIG baseline iOS 27, kit
/// v1.1.0, applied 2026-09-22): Apple's system palette in both appearances,
/// the SF Dynamic Type scale on the platform's system font, Liquid Glass
/// only on the control layer (tab bar, toolbar, segmented controls, menus,
/// alerts, toasts), and solid grouped cards for content.
///
/// Three things live here:
///   • [Sys]    — the resolved colour palette for the current appearance,
///                fetched once per build with `Sys.of(context)`.
///   • [Type]   — the Dynamic Type scale as const text styles (size, leading,
///                tracking); colour comes from the theme or `Sys`.
///   • [Motion] — durations and curves, Reduce-Motion aware.
///
/// Statements marked HIG are Apple's rules; the rest are this kit's
/// translation and may be tuned.

// ---------------------------------------------------------------------------
// Colour
// ---------------------------------------------------------------------------

/// Apple's system colours (HIG, Color > Specifications, iOS/iPadOS, values as
/// of the kit's 2026-09-15 review) plus the UIKit background/label/fill roles,
/// resolved for one appearance. Apple says not to hard-code these natively
/// because they can change between releases; there is no way to read them
/// from Flutter, so they are hard-coded here and reviewed with the kit.
///
/// Text rule (HIG, Accessibility): 4.5:1 for text, 3:1 for bold or 18 pt+.
/// Measured on white / #1C1C1E, the kit's answer is: default values for fills,
/// dots, tracks and prominent-button backgrounds; the *increased-contrast*
/// value for coloured text in light mode (`tintText`, `greenText`, …); and
/// systemGray-IC (108 108 112) instead of secondaryLabel for secondary text in
/// light mode. Dark mode keeps Apple's defaults, which all pass.
class Sys {
  final Brightness brightness;

  // Backgrounds (grouped style: cards on a gray page in light mode; in dark
  // mode the page is black and cards use the *elevated* set so layering reads
  // as depth — HIG, Dark Mode).
  /// systemGroupedBackground — the page behind the cards.
  final Color bg;

  /// secondarySystemGroupedBackground — cards, sheets, popovers.
  final Color card;

  /// tertiarySystemGroupedBackground — wells inside cards.
  final Color well;

  // Text
  final Color label;
  final Color secondaryLabel;

  /// Disabled text and placeholders only (HIG exempts it from the 4.5:1 rule).
  final Color tertiaryLabel;

  /// Hairlines.
  final Color separator;

  // Fills
  /// systemFill — thin fills, progress tracks.
  final Color fill;

  /// tertiarySystemFill — input fields, gray buttons, hover.
  final Color tertiaryFill;

  // Tint (the app accent — system blue, as the kit's component tables assume)
  /// For fills, dots, selection and prominent-button backgrounds.
  final Color tint;

  /// For coloured *text* (increased-contrast value in light mode).
  final Color tintText;

  // Status colours, same fill/text split.
  final Color green, greenText;
  final Color orange, orangeText;
  final Color red, redText;

  // Liquid Glass (web translation): tint + rim + edge + shadow around a blur.
  final Color glassTint, glassRim, glassEdge, glassShadow;

  const Sys._({
    required this.brightness,
    required this.bg,
    required this.card,
    required this.well,
    required this.label,
    required this.secondaryLabel,
    required this.tertiaryLabel,
    required this.separator,
    required this.fill,
    required this.tertiaryFill,
    required this.tint,
    required this.tintText,
    required this.green,
    required this.greenText,
    required this.orange,
    required this.orangeText,
    required this.red,
    required this.redText,
    required this.glassTint,
    required this.glassRim,
    required this.glassEdge,
    required this.glassShadow,
  });

  static const light = Sys._(
    brightness: Brightness.light,
    bg: Color(0xFFF2F2F7),
    card: Color(0xFFFFFFFF),
    well: Color(0xFFF2F2F7),
    label: Color(0xFF000000),
    secondaryLabel: Color(0xFF6C6C70), // systemGray, increased contrast
    tertiaryLabel: Color(0x4D3C3C43), // 60 60 67 / 30%
    separator: Color(0x4A3C3C43), // 60 60 67 / 29%
    fill: Color(0x33787880), // 120 120 128 / 20%
    tertiaryFill: Color(0x1F767680), // 118 118 128 / 12%
    tint: Color(0xFF0088FF), // blue 0 136 255
    tintText: Color(0xFF1E6EF4), // blue IC 30 110 244 (4.57:1 on white)
    green: Color(0xFF34C759),
    greenText: Color(0xFF008932), // green IC
    orange: Color(0xFFFF8D28),
    orangeText: Color(0xFFC55300), // orange IC
    red: Color(0xFFFF383C),
    redText: Color(0xFFE9152D), // red IC
    glassTint: Color(0x9EFFFFFF), // white / .62
    glassRim: Color(0xB3FFFFFF), // white / .7
    glassEdge: Color(0x0F000000), // black / .06
    glassShadow: Color(0x1A000000), // black / .10
  );

  static const dark = Sys._(
    brightness: Brightness.dark,
    bg: Color(0xFF000000),
    card: Color(0xFF1C1C1E), // elevated
    well: Color(0xFF2C2C2E),
    label: Color(0xFFFFFFFF),
    secondaryLabel: Color(0x99EBEBF5), // 235 235 245 / 60%
    tertiaryLabel: Color(0x4DEBEBF5), // 235 235 245 / 30%
    separator: Color(0x99545458), // 84 84 88 / 60%
    fill: Color(0x5C787880), // 120 120 128 / 36%
    tertiaryFill: Color(0x3D767680), // 118 118 128 / 24%
    tint: Color(0xFF0091FF), // blue 0 145 255
    tintText: Color(0xFF0091FF), // 5.26:1 on #1C1C1E
    green: Color(0xFF30D158),
    greenText: Color(0xFF30D158),
    orange: Color(0xFFFF9230),
    orangeText: Color(0xFFFF9230),
    red: Color(0xFFFF4245),
    redText: Color(0xFFFF4245),
    glassTint: Color(0x942C2C2E), // 44 44 46 / .58
    glassRim: Color(0x24FFFFFF), // white / .14
    glassEdge: Color(0x66000000), // black / .4
    glassShadow: Color(0x73000000), // black / .45
  );

  /// The palette for the appearance the surrounding theme is in.
  static Sys of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  bool get isDark => brightness == Brightness.dark;

  /// Label colour on a [tint]-filled surface. White on system blue reads
  /// 3.5:1 (light) / 3.2:1 (dark), which passes only at bold or 18 pt+ — so
  /// prominent-button labels are always semibold (HIG allowance, kit §3.3).
  Color get onTint => Colors.white;

  /// A status colour at the kit's badge/tinted-button opacity.
  static Color wash(Color c, [double alpha = 0.15]) => c.withValues(alpha: alpha);

  // --- layout (HIG, Accessibility / Buttons / Typography / Toolbars) --------

  /// Minimum hit area for anything tappable, 44 × 44 pt. A control may *look*
  /// smaller — wrap its tap surface in `TapTarget` to pad the hit area.
  static const double minTapTarget = 44;

  /// Smallest text the HIG allows on iOS/iPadOS.
  static const double minFontSize = 11;

  /// Radius scale (kit): cards and menus 22, wells 14, small insets 10,
  /// every control a capsule. Inner radii stay concentric with their
  /// container: inner = outer − padding.
  static const double radiusCard = 22;
  static const double radiusWell = 14;
  static const double radiusInset = 10;
  static const double radiusCapsule = 9999;

  /// Page gutter and card padding.
  static const double gutter = 16;

  // --- glass ----------------------------------------------------------------

  /// Backdrop blur radius for regular glass.
  static const double glassBlur = 22;

  /// The kit's `blur(22px) saturate(180%)`: a saturation boost composed with
  /// the blur, so colour behind the glass reads richer rather than washed out.
  static ImageFilter glassFilter() => ImageFilter.compose(
        outer: ImageFilter.blur(sigmaX: glassBlur, sigmaY: glassBlur),
        inner: const ColorFilter.matrix(_saturate180),
      );

  // 5×4 colour matrix for saturate(1.8) with Rec.601 luma weights.
  static const List<double> _saturate180 = [
    1.6296, -0.5720, -0.0576, 0, 0, //
    -0.1704, 1.2280, -0.0576, 0, 0, //
    -0.1704, -0.5720, 1.7424, 0, 0, //
    0, 0, 0, 1, 0, //
  ];
}

// ---------------------------------------------------------------------------
// Typography
// ---------------------------------------------------------------------------

/// The SF Dynamic Type scale, iOS/iPadOS "Large (default)" (HIG, Typography >
/// Specifications), as const styles carrying size, leading and tracking only.
/// The typeface is the platform's system font — SF on Apple devices, which
/// Flutter renders when no family is set (Apple licenses SF for apps on its
/// platforms only, so nothing is bundled). Weights: Regular, Medium, Semibold,
/// Bold — the HIG says avoid the thin ones.
///
/// Sizes are logical pixels, which Flutter scales by the person's text-size
/// setting (Dynamic Type) unless a widget opts out; nothing here does.
class Type {
  Type._();

  /// 34 / 41, bold — navigation large titles use the emphasized weight.
  static const largeTitle = TextStyle(
      fontSize: 34, height: 41 / 34, fontWeight: FontWeight.w700, letterSpacing: 0.4);
  static const title1 = TextStyle(fontSize: 28, height: 34 / 28, letterSpacing: 0.38);
  static const title2 = TextStyle(fontSize: 22, height: 28 / 22, letterSpacing: -0.26);
  static const title3 = TextStyle(fontSize: 20, height: 25 / 20, letterSpacing: -0.45);
  static const headline = TextStyle(
      fontSize: 17, height: 22 / 17, fontWeight: FontWeight.w600, letterSpacing: -0.43);
  static const body = TextStyle(fontSize: 17, height: 22 / 17, letterSpacing: -0.43);
  static const callout = TextStyle(fontSize: 16, height: 21 / 16, letterSpacing: -0.31);
  static const subhead = TextStyle(fontSize: 15, height: 20 / 15, letterSpacing: -0.23);
  static const footnote = TextStyle(fontSize: 13, height: 18 / 13, letterSpacing: -0.08);
  static const caption1 = TextStyle(fontSize: 12, height: 16 / 12);
  static const caption2 = TextStyle(fontSize: 11, height: 13 / 11, letterSpacing: 0.06);
}

/// Ergonomics for composing a [Type] style with a weight, colour or figures.
extension TypeStyle on TextStyle {
  TextStyle get medium => copyWith(fontWeight: FontWeight.w500);
  TextStyle get semibold => copyWith(fontWeight: FontWeight.w600);
  TextStyle get bold => copyWith(fontWeight: FontWeight.w700);

  /// Tabular figures — every money and count column.
  TextStyle get tabular => copyWith(fontFeatures: tabularNums);

  TextStyle colored(Color color) => copyWith(color: color);
}

/// tabular-nums feature for money display.
const tabularNums = [FontFeature.tabularFigures()];

/// A numeric display style (big totals, unit codes): the system font at
/// [fontSize] with tabular figures. Kept for call sites that predate [Type];
/// prefer `Type.largeTitle.tabular` and friends in new code.
TextStyle display({
  double? fontSize,
  FontWeight fontWeight = FontWeight.w600,
  Color? color,
  double? letterSpacing,
  List<FontFeature>? fontFeatures,
}) =>
    TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      fontFeatures: fontFeatures ?? tabularNums,
    );

// ---------------------------------------------------------------------------
// Theme
// ---------------------------------------------------------------------------

/// Material theme for one appearance. Built twice (light + dark) and handed
/// to `MaterialApp.theme` / `darkTheme`; `themeMode` follows the Appearance
/// setting (Automatic / Light / Dark).
///
/// [fontFamily] is null in the app (the platform's system font — SF on Apple
/// devices). Screenshot tests pass a family they loaded with `FontLoader`,
/// because `flutter test` renders every unloaded family as the blank test
/// font.
ThemeData buildTheme(Brightness brightness, {String? fontFamily}) {
  final sys = brightness == Brightness.dark ? Sys.dark : Sys.light;
  final base = ThemeData(
      useMaterial3: true, brightness: brightness, fontFamily: fontFamily);
  return base.copyWith(
    scaffoldBackgroundColor: sys.bg,
    canvasColor: sys.bg,
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: sys.tint,
      onPrimary: sys.onTint,
      secondary: sys.tint,
      onSecondary: sys.onTint,
      error: sys.red,
      onError: Colors.white,
      surface: sys.card,
      onSurface: sys.label,
      onSurfaceVariant: sys.secondaryLabel,
      outline: sys.separator,
      outlineVariant: sys.separator,
      surfaceContainerHighest: sys.well,
    ),
    // Body text in the label colour at the Dynamic Type body size; the system
    // font is the platform default, so no family is set.
    textTheme: base.textTheme
        .apply(bodyColor: sys.label, displayColor: sys.label)
        .copyWith(
            bodyMedium:
                Type.body.colored(sys.label).copyWith(fontFamily: fontFamily)),
    iconTheme: IconThemeData(color: sys.label),
    dividerTheme: DividerThemeData(
        color: sys.separator, thickness: 0.5, space: 0),
    splashFactory: InkRipple.splashFactory,
    // Material controls pad their hit area to 48 px; custom InkWells don't,
    // which is what `TapTarget` is for.
    materialTapTargetSize: MaterialTapTargetSize.padded,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: sys.tint,
      selectionColor: sys.tint.withValues(alpha: 0.28),
      selectionHandleColor: sys.tint,
    ),
    // Text fields (kit): tertiarySystemFill, no border, 14 px radius, 16 px+
    // text, a 2 px tint focus ring at 40%.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: sys.tertiaryFill,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: Type.body.colored(sys.tertiaryLabel),
      labelStyle: Type.subhead.colored(sys.secondaryLabel),
      floatingLabelStyle: Type.footnote.colored(sys.tintText),
      prefixStyle: Type.body.colored(sys.secondaryLabel),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Sys.radiusWell),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Sys.radiusWell),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Sys.radiusWell),
        borderSide:
            BorderSide(color: sys.tint.withValues(alpha: 0.4), width: 2),
      ),
    ),
    // Any stray Material dialog (e.g. the date picker) on the card surface.
    dialogTheme: DialogThemeData(
      backgroundColor: sys.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Sys.radiusCard)),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: sys.card,
      surfaceTintColor: Colors.transparent,
      headerForegroundColor: sys.label,
    ),
    // ChoiceChips (the escalation preset chips) as capsule badges.
    chipTheme: ChipThemeData(
      backgroundColor: sys.tertiaryFill,
      selectedColor: sys.tint,
      side: BorderSide.none,
      labelStyle: Type.footnote.semibold.colored(sys.label),
      secondaryLabelStyle: Type.footnote.semibold.colored(sys.onTint),
      shape: const StadiumBorder(),
      showCheckmark: false,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? sys.green : sys.fill),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: sys.tint),
    // Material buttons as kit capsules, so a stray FilledButton/TextButton
    // matches AppButton: prominent = tint + white semibold; text = tint text.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: sys.tint,
        foregroundColor: sys.onTint,
        disabledBackgroundColor: sys.tint.withValues(alpha: 0.4),
        disabledForegroundColor: sys.onTint.withValues(alpha: 0.7),
        minimumSize: const Size(Sys.minTapTarget, Sys.minTapTarget),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: const StadiumBorder(),
        textStyle: Type.body.semibold,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: sys.tint,
        foregroundColor: sys.onTint,
        elevation: 0,
        minimumSize: const Size(Sys.minTapTarget, Sys.minTapTarget),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: const StadiumBorder(),
        textStyle: Type.body.semibold,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: sys.tintText,
        minimumSize: const Size(Sys.minTapTarget, Sys.minTapTarget),
        shape: const StadiumBorder(),
        textStyle: Type.body.semibold,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: sys.tintText,
        backgroundColor: Sys.wash(sys.tint),
        side: BorderSide.none,
        minimumSize: const Size(Sys.minTapTarget, Sys.minTapTarget),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: const StadiumBorder(),
        textStyle: Type.body.semibold,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent, surfaceTintColor: Colors.transparent),
  );
}

// ---------------------------------------------------------------------------
// Motion
// ---------------------------------------------------------------------------

/// Motion tokens (HIG, Motion + Accessibility). The curves are the brand kit's
/// approximations of Apple's springs; the durations are its 200–350 ms band.
///
/// Every animated widget takes its duration through [duration], so iOS
/// **Reduce Motion** — which Flutter surfaces as `MediaQuery.disableAnimations`
/// — collapses movement into an instant state change. That is the HIG rule
/// verbatim: remove movement and bounce, keep state changes.
class Motion {
  Motion._();

  /// For things that move (slides, size and position changes).
  static const move = Cubic(0.32, 0.72, 0, 1);

  /// For colour and opacity changes.
  static const fade = Cubic(0.2, 0, 0, 1);

  static const moveDuration = Duration(milliseconds: 300);
  static const fadeDuration = Duration(milliseconds: 200);
  static const quick = Duration(milliseconds: 150);

  /// Press state for custom controls: scale to 0.96 (kit).
  static const pressScale = 0.96;

  /// True when the person has asked for reduced motion.
  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);

  /// [base], or zero under Reduce Motion. Flutter's animation controllers and
  /// implicitly animated widgets treat a zero duration as "jump to the end".
  static Duration duration(BuildContext context, Duration base) =>
      reduced(context) ? Duration.zero : base;
}

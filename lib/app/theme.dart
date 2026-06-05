import 'package:flutter/material.dart';

/// Brand design tokens (ported verbatim from the prototype `rent glass.jsx`).
/// Glassmorphic, navy + orange.
class Brand {
  // brand
  static const orange = Color(0xFFFF6600);
  static const orangeSoft = Color(0xFFFF9A52);
  static const orangeWarm = Color(0xFFFF8A3D); // pct + clock chip accent
  static const orangeGradEnd = Color(0xFFFF9A4D); // gradient fill end
  static const navy = Color(0xFF274074);

  // surface / text
  static const text = Color(0xFFF5F6FF);
  static const muted = Color(0xD1E2E6FF); // rgba(226,230,255,.82)

  // state
  static const paid = Color(0xFF34D399); // green — paid/success
  static const paidText = Color(0xFF4EE0A8);

  // glass
  static const glassBg = Color(0x8C182444); // rgba(24,36,68,.55)
  static const glassBorder = Color(0x29FFFFFF); // rgba(255,255,255,.16)
  static const double glassBlur = 20;
  // Footer nav: lighter tint + stronger blur so page content reads through
  // the bar as frosted glass, while icons/labels stay legible.
  static const navGlassBg = Color(0x59182444); // rgba(24,36,68,.35)

  // "mark paid" list pill = dimmed translucent orange
  static const pillBg = Color(0x33FF6600); // rgba(255,102,0,.2)
  static const pillBorder = Color(0x61FF6600); // rgba(255,102,0,.38)

  // paid pill / avatar tints
  static const paidPillBg = Color(0x2E34D399); // rgba(52,211,153,.18)
  static const paidPillBorder = Color(0x7334D399); // rgba(52,211,153,.45)

  // background gradient stops (160deg #22365f → #192a4f → #0e1830)
  static const bgTop = Color(0xFF22365F);
  static const bgMid = Color(0xFF192A4F);
  static const bgBottom = Color(0xFF0E1830);

  // orb colors
  static const orbBlue = Color(0xFF2F5AA0);

  // brand gradients
  static const orangeGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [orange, orangeGradEnd],
  );
}

/// Display font: Fraunces (big numbers, headings, unit codes).
/// UI/body font: Hanken Grotesk. Both bundled in assets/fonts.
const String displayFamily = 'Fraunces';
const String bodyFamily = 'HankenGrotesk';

TextStyle display({
  double? fontSize,
  FontWeight fontWeight = FontWeight.w600,
  Color? color,
  double? letterSpacing,
  List<FontFeature>? fontFeatures,
}) =>
    TextStyle(
      fontFamily: displayFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? Brand.text,
      letterSpacing: letterSpacing,
      fontFeatures: fontFeatures,
    );

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: Colors.transparent,
    colorScheme: const ColorScheme.dark(
      primary: Brand.orange,
      secondary: Brand.orangeSoft,
      surface: Brand.navy,
      onPrimary: Colors.white,
      onSurface: Brand.text,
    ),
    textTheme: base.textTheme.apply(
      fontFamily: bodyFamily,
      bodyColor: Brand.text,
      displayColor: Brand.text,
    ),
    splashFactory: InkRipple.splashFactory,
    // Keep stray Material dialogs (e.g. the date picker) on the navy surface.
    dialogTheme: DialogThemeData(
      backgroundColor: Brand.navy,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    // Airy underline fields for any TextField that doesn't override it —
    // mainly the inputs inside the minimal dialogs.
    inputDecorationTheme: const InputDecorationTheme(
      isDense: true,
      filled: false,
      hintStyle: TextStyle(color: Color(0x66FFFFFF)),
      labelStyle: TextStyle(color: Brand.muted),
      floatingLabelStyle: TextStyle(color: Brand.orange),
      contentPadding: EdgeInsets.symmetric(vertical: 9),
      enabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: Brand.glassBorder),
      ),
      focusedBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: Brand.orange, width: 2),
      ),
    ),
    // Brand pills for ChoiceChip (the lease-escalation preset chips).
    chipTheme: ChipThemeData(
      backgroundColor: Brand.glassBg,
      selectedColor: Brand.orange,
      side: const BorderSide(color: Brand.glassBorder),
      labelStyle: const TextStyle(
          color: Brand.text, fontWeight: FontWeight.w600, fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
      showCheckmark: false,
    ),
  );
}

/// tabular-nums feature for money display.
const tabularNums = [FontFeature.tabularFigures()];

import 'package:flutter/material.dart';

/// Lumen · Night — hallmark's "hand-engineered apparatus" catalog theme,
/// ported from its OKLCH web tokens to Flutter. A late-night instrument
/// register: dark violet paper, a molten-brass signal accent used sparingly,
/// and calibrated readouts rather than decoration.
///
/// Headlines use a Japanese-capable serif (Shippori Mincho) instead of
/// hallmark's Instrument Serif — Instrument Serif has no CJK glyphs, and
/// SRL LoL's UI copy is Japanese, so the "lowercase display serif" signature
/// is carried by size/tracking instead of letter case (Japanese has none).
/// Mono (JetBrains Mono) is reserved for the Latin/numeric readout labels
/// where hallmark's UPPERCASE convention still applies directly.
///
/// Fonts are bundled as local assets (see pubspec.yaml `fonts:`) rather than
/// fetched at runtime via google_fonts — this app talks only to a localhost
/// backend and the macOS target has no network-client entitlement, so a
/// network-dependent font would silently fall back to the system font.
class LumenFonts {
  LumenFonts._();

  static const headline = 'ShipporiMincho';
  static const body = 'NotoSansJP';
  static const mono = 'JetBrainsMono';
}

class LumenColors {
  LumenColors._();

  static const paper = Color(0xFF05070D); // oklch(13% 0.014 265)
  static const paperMuted = Color(0xFF0E1219); // oklch(18% 0.016 265)
  static const paperRaised = Color(0xFF161B23); // oklch(22% 0.018 265)
  static const ink = Color(0xFFF0F2F6); // oklch(96% 0.006 262)
  static const brass = Color(0xFFFF8C3F); // oklch(76% 0.17 50) — molten brass
  static const brassDim = Color(0xFFA85A28); // oklch(55% 0.12 50)
  static const coral = Color(0xFFEA6972); // oklch(68% 0.16 18) — coral chord

  static final hairline = ink.withValues(alpha: 0.08);
  static final inkMuted = ink.withValues(alpha: 0.64);
  static final glow = brass.withValues(alpha: 0.35);
}

final _monoLabelStyle = TextStyle(
  fontFamily: LumenFonts.mono,
  fontSize: 11,
  letterSpacing: 1.1,
  color: LumenColors.inkMuted,
);

ThemeData buildLumenNightTheme() {
  final textTheme = TextTheme(
    displayLarge: TextStyle(fontFamily: LumenFonts.headline, fontSize: 57),
    displayMedium: TextStyle(fontFamily: LumenFonts.headline, fontSize: 45),
    displaySmall: TextStyle(fontFamily: LumenFonts.headline, fontSize: 36),
    headlineLarge: TextStyle(
      fontFamily: LumenFonts.headline,
      fontSize: 32,
      letterSpacing: 0.2,
    ),
    headlineMedium: TextStyle(
      fontFamily: LumenFonts.headline,
      fontSize: 28,
      letterSpacing: 0.2,
    ),
    headlineSmall: TextStyle(
      fontFamily: LumenFonts.headline,
      fontSize: 24,
      letterSpacing: 0.2,
    ),
    titleLarge: TextStyle(
      fontFamily: LumenFonts.headline,
      fontSize: 22,
      letterSpacing: 0.2,
    ),
    titleMedium: TextStyle(
      fontFamily: LumenFonts.body,
      fontSize: 16,
      fontWeight: FontWeight.w500,
    ),
    titleSmall: TextStyle(
      fontFamily: LumenFonts.body,
      fontSize: 14,
      fontWeight: FontWeight.w500,
    ),
    bodyLarge: TextStyle(fontFamily: LumenFonts.body, fontSize: 16),
    bodyMedium: TextStyle(fontFamily: LumenFonts.body, fontSize: 14),
    bodySmall: TextStyle(fontFamily: LumenFonts.body, fontSize: 12),
    labelLarge: TextStyle(
      fontFamily: LumenFonts.body,
      fontSize: 14,
      fontWeight: FontWeight.w500,
    ),
    labelSmall: _monoLabelStyle,
  ).apply(bodyColor: LumenColors.ink, displayColor: LumenColors.ink);

  final colorScheme = ColorScheme.fromSeed(
    seedColor: LumenColors.brass,
    brightness: Brightness.dark,
    primary: LumenColors.brass,
    onPrimary: LumenColors.paper,
    secondary: LumenColors.coral,
    onSecondary: LumenColors.paper,
    surface: LumenColors.paper,
    onSurface: LumenColors.ink,
    surfaceContainerHighest: LumenColors.paperMuted,
    outline: LumenColors.hairline,
    error: const Color(0xFFEF4444),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: LumenColors.paper,
    colorScheme: colorScheme,
    textTheme: textTheme,
    fontFamily: LumenFonts.body,
    appBarTheme: const AppBarTheme(
      backgroundColor: LumenColors.paper,
      foregroundColor: LumenColors.ink,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: LumenFonts.headline,
        fontSize: 22,
        letterSpacing: 0.2,
        color: LumenColors.ink,
      ),
    ),
    cardTheme: CardThemeData(
      color: LumenColors.paperMuted,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: LumenColors.hairline),
      ),
    ),
    dividerTheme: DividerThemeData(color: LumenColors.hairline, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: LumenColors.paperMuted,
      labelStyle: TextStyle(
        fontFamily: LumenFonts.mono,
        fontSize: 12,
        color: LumenColors.inkMuted,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: LumenColors.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: LumenColors.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: LumenColors.brass, width: 1.4),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: LumenColors.brass,
        foregroundColor: LumenColors.paper,
        disabledBackgroundColor: LumenColors.brassDim,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(
          fontFamily: LumenFonts.mono,
          fontSize: 13,
          letterSpacing: 1.0,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: LumenColors.brass),
    ),
    iconTheme: const IconThemeData(color: LumenColors.ink),
    chipTheme: ChipThemeData(
      backgroundColor: LumenColors.paperRaised,
      selectedColor: LumenColors.brass.withValues(alpha: 0.18),
      side: BorderSide(color: LumenColors.hairline),
      labelStyle: const TextStyle(
        fontFamily: LumenFonts.body,
        fontSize: 12,
        color: LumenColors.ink,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: LumenColors.brass,
      inactiveTrackColor: LumenColors.hairline,
      thumbColor: LumenColors.brass,
      overlayColor: LumenColors.glow,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: LumenColors.brass,
      linearTrackColor: LumenColors.paperRaised,
    ),
    listTileTheme: ListTileThemeData(
      textColor: LumenColors.ink,
      iconColor: LumenColors.ink,
      subtitleTextStyle: TextStyle(
        fontFamily: LumenFonts.body,
        fontSize: 14,
        color: LumenColors.inkMuted,
      ),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: LumenColors.paperMuted,
      selectedItemColor: LumenColors.brass,
      unselectedItemColor: LumenColors.inkMuted,
      type: BottomNavigationBarType.fixed,
      selectedLabelStyle: const TextStyle(
        fontFamily: LumenFonts.mono,
        fontSize: 10,
        letterSpacing: 0.8,
      ),
      unselectedLabelStyle: const TextStyle(
        fontFamily: LumenFonts.mono,
        fontSize: 10,
        letterSpacing: 0.8,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: LumenColors.paperMuted,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: LumenColors.hairline),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: LumenColors.paperRaised,
      contentTextStyle: const TextStyle(
        fontFamily: LumenFonts.body,
        fontSize: 14,
        color: LumenColors.ink,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: LumenColors.hairline),
      ),
    ),
  );
}

/// A small uppercase mono "eyebrow" label — hallmark's UPPERCASE
/// mono-micro-type convention, used only where the label text is itself
/// Latin/numeric so the case transform is meaningful.
class LumenLabel extends StatelessWidget {
  final String text;
  final Color? color;

  const LumenLabel(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontFamily: LumenFonts.mono,
        fontSize: 11,
        letterSpacing: 1.4,
        color: color ?? LumenColors.brass,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// The apparatus "readout" — a calibrated-instrument treatment for a single
/// measured value (e.g. impulse-control-failure ratio, death count). Mono
/// numerals with a brass glow, a Japanese caption underneath. This is
/// Lumen's "the apparatus is the only thing that emits" idea applied to
/// SRL LoL's actual video-analysis metrics.
class LumenReadout extends StatelessWidget {
  final String value;
  final String caption;
  final IconData? icon;

  const LumenReadout({
    super.key,
    required this.value,
    required this.caption,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: LumenColors.paperRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: LumenColors.hairline),
        boxShadow: [
          BoxShadow(color: LumenColors.glow, blurRadius: 18, spreadRadius: -6),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: LumenColors.brass),
            const SizedBox(width: 8),
          ],
          Text(
            value,
            style: const TextStyle(
              fontFamily: LumenFonts.mono,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: LumenColors.brass,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              caption,
              style: TextStyle(fontSize: 13, color: LumenColors.inkMuted),
            ),
          ),
        ],
      ),
    );
  }
}

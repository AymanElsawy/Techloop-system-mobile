import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colors from md-files/shared/03-design-tokens.md (light: air-force-blue / bright-teal-blue / cornflower-ocean / red,
/// dark: ink-black / deep-space-blue / blue-slate / eggshell). Status colors: warning (apricot / light-bronze), danger (coral / rosewood).
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.muted,
    required this.border,
    required this.danger,
    required this.warningBg,
    required this.warningFg,
    required this.highlight,
    required this.onHighlight,
    required this.chartSales,
    required this.chartCollected,
    required this.subtle,
    required this.successBg,
    required this.successFg,
    required this.dangerBg,
    required this.dangerFg,
    required this.infoBg,
    required this.infoFg,
    required this.neutralBg,
    required this.neutralFg,
  });

  final Color muted; // secondary text
  final Color border;
  final Color danger; // debt, errors
  final Color warningBg;
  final Color warningFg;
  final Color highlight; // treasury / cash box card
  final Color onHighlight;
  final Color chartSales;
  final Color chartCollected;
  final Color subtle; // light panel inside a card (summaries)
  // Badge / banner pairs, same as the web status classes.
  final Color successBg; // approved, completed, in the treasury
  final Color successFg;
  final Color dangerBg; // rejected, cancelled
  final Color dangerFg;
  final Color infoBg; // in progress
  final Color infoFg;
  final Color neutralBg;
  final Color neutralFg;

  static const light = AppColors(
    muted: Color(0xFF045D95),
    border: Color(0xFFCFEDFC),
    danger: Color(0xFFCC0000),
    warningBg: Color(0xFFFFF0E3),
    warningFg: Color(0xFFAD5503),
    highlight: Color(0xFF233843),
    onHighlight: Colors.white,
    chartSales: Color(0xFF233843),
    chartCollected: Color(0xFF045D95),
    subtle: Color(0xFFEEF4F6),
    successBg: Color(0xFFDDE8EE),
    successFg: Color(0xFF233843),
    dangerBg: Color(0xFFFFE5E5),
    dangerFg: Color(0xFFCC0000),
    infoBg: Color(0xFFCFEDFC),
    infoFg: Color(0xFF045D95),
    neutralBg: Color(0xFFEEF4F6),
    neutralFg: Color(0xFF111C22),
  );

  static const dark = AppColors(
    muted: Color(0xFFABB9CD),
    border: Color(0xFF31495E),
    danger: Color(0xFFC38391),
    warningBg: Color(0xFF7E3B17),
    warningFg: Color(0xFFF4D3C2),
    highlight: Color(0xFF31495E),
    onHighlight: Color(0xFFF0EBD8),
    chartSales: Color(0xFFF0EBD8),
    chartCollected: Color(0xFF7D9EBA),
    subtle: Color(0xFF0D1321),
    successBg: Color(0xFF3E5C76),
    successFg: Color(0xFFC5D3E6),
    dangerBg: Color(0xFF261217),
    dangerFg: Color(0xFFD2A1AB),
    infoBg: Color(0xFF31495E),
    infoFg: Color(0xFFABB9CD),
    neutralBg: Color(0xFF0D1321),
    neutralFg: Color(0xFFF0EBD8),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) =>
      t < 0.5 ? this : (other as AppColors? ?? this);
}

extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF233843),
        brightness: brightness,
      ).copyWith(
        primary: dark ? const Color(0xFFF0EBD8) : const Color(0xFF045D95),
        onPrimary: dark ? Colors.black : Colors.white,
        // Tonal buttons and selected chips (M3 uses the containers, not primary).
        primaryContainer: dark
            ? const Color(0xFF3E5C76)
            : const Color(0xFFCFEDFC),
        onPrimaryContainer: dark
            ? const Color(0xFFF0EBD8)
            : const Color(0xFF033E63),
        secondaryContainer: dark
            ? const Color(0xFF3E5C76)
            : const Color(0xFFDDE8EE),
        onSecondaryContainer: dark
            ? const Color(0xFFF0EBD8)
            : const Color(0xFF233843),
        surface: dark ? const Color(0xFF1D2D44) : Colors.white,
        onSurface: dark ? const Color(0xFFF0EBD8) : const Color(0xFF111C22),
        error: dark ? const Color(0xFFC38391) : const Color(0xFFCC0000),
      );
  final colors = dark ? AppColors.dark : AppColors.light;
  final base = ThemeData(
    colorScheme: scheme,
    brightness: brightness,
    useMaterial3: true,
  );

  return base.copyWith(
    scaffoldBackgroundColor: dark
        ? const Color(0xFF0D1321)
        : const Color(0xFFEEF4F6),
    textTheme: GoogleFonts.cairoTextTheme(base.textTheme).apply(
      bodyColor: scheme.onSurface,
      displayColor: dark ? const Color(0xFFF0EBD8) : const Color(0xFF233843),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xFF080B14) : const Color(0xFF233843),
      foregroundColor: Colors.white,
      centerTitle: false,
      titleTextStyle: GoogleFonts.cairo(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: scheme.surface,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colors.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 46),
        foregroundColor: scheme.primary,
        side: BorderSide(color: scheme.primary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: GoogleFonts.cairo(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 2,
      highlightElevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      extendedTextStyle: GoogleFonts.cairo(
        fontWeight: FontWeight.w700,
        fontSize: 15,
      ),
    ),
    extensions: [colors],
  );
}

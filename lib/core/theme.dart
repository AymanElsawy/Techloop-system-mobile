import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colors from md-files/shared/03-design-tokens.md (light: yale-blue / stormy-teal / alabaster-grey,
/// dark: prussian-blue / orange). Status colors: warning (apricot / orange), danger (coral / orange).
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
    muted: Color(0xFF3C6E71),
    border: Color(0xFFD3E7E8),
    danger: Color(0xFFEA3528),
    warningBg: Color(0xFFFFF0E3),
    warningFg: Color(0xFFAD5503),
    highlight: Color(0xFF284B63),
    onHighlight: Colors.white,
    chartSales: Color(0xFF284B63),
    chartCollected: Color(0xFF3C6E71),
    subtle: Color(0xFFF0F0F0),
    successBg: Color(0xFFCADDE9),
    successFg: Color(0xFF284B63),
    dangerBg: Color(0xFFFCE2E0),
    dangerFg: Color(0xFFBB1E12),
    infoBg: Color(0xFFD3E7E8),
    infoFg: Color(0xFF3C6E71),
    neutralBg: Color(0xFFF0F0F0),
    neutralFg: Color(0xFF2B2B2B),
  );

  static const dark = AppColors(
    muted: Color(0xFFB8B8B8),
    border: Color(0xFF1F3158),
    danger: Color(0xFFFDB541),
    warningBg: Color(0xFF6B4201),
    warningFg: Color(0xFFFEDAA0),
    highlight: Color(0xFF101B31),
    onHighlight: Color(0xFFE5E5E5),
    chartSales: Color(0xFFE5E5E5),
    chartCollected: Color(0xFFFCA311),
    subtle: Color(0xFF0C1425),
    successBg: Color(0xFF101B31),
    successFg: Color(0xFFBECCEA),
    dangerBg: Color(0xFF362101),
    dangerFg: Color(0xFFFEC871),
    infoBg: Color(0xFF1F3158),
    infoFg: Color(0xFFB8B8B8),
    neutralBg: Color(0xFF0C1425),
    neutralFg: Color(0xFFFAFAFA),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) => t < 0.5 ? this : (other as AppColors? ?? this);
}

extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF284B63), brightness: brightness).copyWith(
    primary: dark ? const Color(0xFFFCA311) : const Color(0xFF3C6E71),
    onPrimary: dark ? Colors.black : Colors.white,
    surface: dark ? const Color(0xFF14213D) : Colors.white,
    onSurface: dark ? const Color(0xFFE5E5E5) : const Color(0xFF353535),
    error: dark ? const Color(0xFFFDB541) : const Color(0xFFEA3528),
  );
  final colors = dark ? AppColors.dark : AppColors.light;
  final base = ThemeData(colorScheme: scheme, brightness: brightness, useMaterial3: true);

  return base.copyWith(
    scaffoldBackgroundColor: dark ? const Color(0xFF0C1425) : const Color(0xFFF0F0F0),
    textTheme: GoogleFonts.cairoTextTheme(
      base.textTheme,
    ).apply(bodyColor: scheme.onSurface, displayColor: dark ? const Color(0xFFE5E5E5) : const Color(0xFF284B63)),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xFF080D19) : const Color(0xFF284B63),
      foregroundColor: Colors.white,
      centerTitle: false,
      titleTextStyle: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
    ),
    drawerTheme: DrawerThemeData(backgroundColor: dark ? const Color(0xFF080D19) : const Color(0xFF284B63)),
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
        side: BorderSide(color: colors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: GoogleFonts.cairo(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
    ),
    extensions: [colors],
  );
}

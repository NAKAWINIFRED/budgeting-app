import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The Tidewise palette. Use these everywhere instead of raw hex values.
class AppColors {
  AppColors._();

  static const deepWater = Color(0xFF12303F); // headings, key numbers
  static const tide = Color(0xFF1C7C7D); // main actions, income, on track
  static const shallows = Color(0xFFDCEFEA); // soft highlight backgrounds
  static const foam = Color(0xFFF4F8F8); // app background
  static const amber = Color(0xFFE8A33D); // gentle warnings
  static const buoyRed = Color(0xFFD6453D); // overspending only
  static const mist = Color(0xFF5B7280); // secondary text
  static const line = Color(0xFFE1E9EA); // dividers, empty progress bars
}

class AppText {
  AppText._();

  /// Style for money amounts. Tabular figures keep digits the same width,
  /// so numbers line up neatly in lists.
  static TextStyle amount(
    double size, {
    Color color = AppColors.deepWater,
    FontWeight weight = FontWeight.w700,
  }) {
    return GoogleFonts.manrope(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: 1.1,
      letterSpacing: size >= 28 ? -1.0 : -0.2,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }
}

ThemeData buildAppTheme() {
  final colorScheme = ColorScheme.fromSeed(seedColor: AppColors.tide).copyWith(
    primary: AppColors.tide,
    onPrimary: Colors.white,
    secondary: AppColors.deepWater,
    onSecondary: Colors.white,
    surface: AppColors.foam,
    onSurface: AppColors.deepWater,
    error: AppColors.buoyRed,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: colorScheme);
  final textTheme = GoogleFonts.manropeTextTheme(base.textTheme).apply(
    bodyColor: AppColors.deepWater,
    displayColor: AppColors.deepWater,
  );

  Color navColor(Set<WidgetState> states) => states.contains(WidgetState.selected)
      ? AppColors.deepWater
      : AppColors.mist;

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.foam,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.foam,
      foregroundColor: AppColors.deepWater,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle:
          textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.shallows,
      elevation: 0,
      height: 68,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(color: navColor(states)),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => textTheme.labelMedium?.copyWith(
          color: navColor(states),
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
        ),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.deepWater,
      foregroundColor: Colors.white,
      elevation: 2,
      shape: CircleBorder(),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.line,
      thickness: 1,
      space: 1,
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.tide,
        textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
  );
}

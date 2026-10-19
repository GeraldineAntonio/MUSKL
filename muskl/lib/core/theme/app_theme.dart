import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static const radius = 14.0;

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    final text = GoogleFonts.nunitoSansTextTheme(base.textTheme).apply(
      bodyColor: AppColors.white,
      displayColor: AppColors.white,
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.red,
        secondary: AppColors.accent,
        surface: AppColors.surface,
        error: AppColors.red,
      ),
      textTheme: text.copyWith(
        // Tipografía redondeada y legible para acercarnos al estilo Nu Sans.
        headlineLarge: text.headlineLarge?.copyWith(
          fontWeight: FontWeight.w900,
          fontSize: 38,
          height: 1.04,
          letterSpacing: -0.8,
        ),
        headlineMedium: text.headlineMedium?.copyWith(
          fontWeight: FontWeight.w900,
          fontSize: 27,
          height: 1.08,
          letterSpacing: -0.35,
        ),
        titleLarge: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          fontSize: 21,
          letterSpacing: -0.2,
        ),
        titleMedium: text.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 17,
        ),
        bodyLarge: text.bodyLarge?.copyWith(fontSize: 16, height: 1.35),
        bodyMedium: text.bodyMedium?.copyWith(fontSize: 15, height: 1.35),
        bodySmall: text.bodySmall?.copyWith(fontSize: 13, height: 1.3),
        labelSmall: text.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 12,
          letterSpacing: 1.2,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceHigh,
        contentTextStyle: GoogleFonts.nunitoSans(
          color: AppColors.white,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

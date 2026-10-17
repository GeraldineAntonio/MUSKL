import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static const radius = 14.0;

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    final text = GoogleFonts.barlowCondensedTextTheme(base.textTheme).apply(
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
        // Títulos de pantalla: condensada, mayúsculas, muy gruesa.
        headlineLarge: text.headlineLarge?.copyWith(
          fontWeight: FontWeight.w800,
          fontSize: 40,
          height: 1.0,
        ),
        headlineMedium: text.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
          fontSize: 28,
          height: 1.05,
        ),
        titleMedium: text.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
        bodyMedium: text.bodyMedium?.copyWith(fontSize: 15),
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
        contentTextStyle: GoogleFonts.barlowCondensed(
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

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
          fontSize: 34,
          height: 1.15,
          letterSpacing: -0.8,
        ),
        headlineMedium: text.headlineMedium?.copyWith(
          fontWeight: FontWeight.w900,
          fontSize: 27,
          height: 1.2,
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
        centerTitle: false,
        titleSpacing: 20,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceRaised,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: text.bodyMedium?.copyWith(color: AppColors.textMuted),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius + 2),
          borderSide: const BorderSide(color: AppColors.surfaceHigh),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius + 2),
          borderSide: const BorderSide(color: AppColors.red, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius + 2),
          borderSide: const BorderSide(color: AppColors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius + 2),
          borderSide: const BorderSide(color: AppColors.red, width: 1.5),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.surfaceRaised,
        selectedColor: AppColors.red,
        side: const BorderSide(color: AppColors.surfaceHigh),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        labelStyle: text.bodySmall?.copyWith(fontWeight: FontWeight.w700),
        secondaryLabelStyle: text.bodySmall?.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w800,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: AppColors.surfaceHigh),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.white,
          minimumSize: const Size(48, 48),
          side: const BorderSide(color: AppColors.surfaceHigh),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius + 2),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.red,
          foregroundColor: AppColors.white,
          minimumSize: const Size(48, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius + 2),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
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

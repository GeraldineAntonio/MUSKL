import 'package:flutter/material.dart';

/// Paleta MUSKL, tomada de las pantallas de Figma.
class AppColors {
  AppColors._();

  static bool isLightMode = false;

  static Color get bg =>
      isLightMode ? const Color(0xFFF3F4F6) : const Color(0xFF101115);
  static Color get bgDeep =>
      isLightMode ? const Color(0xFFFFFFFF) : const Color(0xFF090A0D);
  static Color get surface =>
      isLightMode ? const Color(0xFFFFFFFF) : const Color(0xFF191B21);
  static Color get surfaceHigh =>
      isLightMode ? const Color(0xFFD9DCE2) : const Color(0xFF30323A);
  static Color get surfaceRaised =>
      isLightMode ? const Color(0xFFF8F8FA) : const Color(0xFF202229);
  static const red = Color(0xFFFF3348);
  static const redLight = Color(0xFFFF5263);
  static Color get accent =>
      isLightMode ? const Color(0xFFB51F35) : const Color(0xFFFFA6B0);
  static Color get white =>
      isLightMode ? const Color(0xFF191B21) : const Color(0xFFFFFFFF);
  static Color get textMuted =>
      isLightMode ? const Color(0xFF666B75) : const Color(0xFFB8B8C0);
  static Color get success =>
      isLightMode ? const Color(0xFF16804D) : const Color(0xFF3DDC84);
  static const buttonForeground = Color(0xFFFFFFFF);
}

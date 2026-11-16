import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Fondo oscuro con reflejos difusos para dar profundidad a las superficies de
/// cristal de MUSKL.
class MusklAmbientBackground extends StatelessWidget {
  const MusklAmbientBackground({super.key, required this.child});

  final Widget child;

  Widget _glow(Color color, double size) => IgnorePointer(
        child: SizedBox.square(
          dimension: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [color, color.withValues(alpha: 0)],
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF171219),
                  AppColors.bgDeep,
                  Color(0xFF0D1015)
                ],
              ),
            ),
          ),
          Positioned(
              top: -150, right: -130, child: _glow(AppColors.redGlow, 380)),
          Positioned(
            bottom: -210,
            left: -190,
            child: _glow(AppColors.accent.withValues(alpha: .075), 440),
          ),
          child,
        ],
      );
}

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Tarjeta redondeada. Con [selected] se resalta en rojo (planes, objetivos).
class MusklCard extends StatelessWidget {
  const MusklCard({
    super.key,
    required this.child,
    this.selected = false,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final bool selected;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppTheme.radius + 7);
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: AppColors.isLightMode
                      ? const [Color(0xFFFFE6EA), Color(0xFFFFF4F5)]
                      : const [Color(0xFF32191E), Color(0xFF21171B)],
                )
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.surfaceRaised, AppColors.surface],
                ),
          borderRadius: radius,
          border: Border.all(
            color: selected
                ? AppColors.red.withValues(alpha: .76)
                : AppColors.surfaceHigh.withValues(alpha: .76),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.bgDeep.withValues(alpha: .26),
              blurRadius: 16,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

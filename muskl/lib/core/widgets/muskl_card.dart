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
    return Material(
      color: selected ? AppColors.red : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius + 4),
        side: BorderSide(
          color: selected ? AppColors.red : AppColors.surfaceHigh,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius + 4),
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

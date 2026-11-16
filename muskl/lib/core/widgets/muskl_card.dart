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
    return ClipRRect(
      borderRadius: radius,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xD83A2028), Color(0xB31E171E)],
                  )
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.glassTop, AppColors.glassBottom],
                  ),
            borderRadius: radius,
            border: Border.all(
              color: selected
                  ? AppColors.red.withValues(alpha: .72)
                  : AppColors.glassBorder,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.bgDeep.withValues(alpha: .38),
                blurRadius: 22,
                offset: const Offset(0, 9),
              ),
              if (selected)
                BoxShadow(
                  color: AppColors.red.withValues(alpha: .13),
                  blurRadius: 22,
                  spreadRadius: -7,
                ),
            ],
          ),
          child: Stack(
            children: [
              const Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.center,
                        colors: [
                          AppColors.glassHighlight,
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              InkWell(
                borderRadius: radius,
                onTap: onTap,
                child: Padding(padding: padding, child: child),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

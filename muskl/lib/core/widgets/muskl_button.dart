import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

enum MusklButtonStyle { primary, secondary, light, accent, ghost }

/// Botón principal de MUSKL.
class MusklButton extends StatelessWidget {
  const MusklButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.style = MusklButtonStyle.primary,
    this.icon,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final MusklButtonStyle style;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (style) {
      MusklButtonStyle.primary => (AppColors.red, AppColors.buttonForeground),
      MusklButtonStyle.secondary => (AppColors.surfaceRaised, AppColors.white),
      MusklButtonStyle.light => (AppColors.white, AppColors.bgDeep),
      MusklButtonStyle.accent => (AppColors.accent, AppColors.buttonForeground),
      MusklButtonStyle.ghost => (Colors.transparent, AppColors.textMuted),
    };
    final enabled = onPressed != null && !loading;

    return Semantics(
      button: true,
      enabled: enabled,
      onTap: enabled ? onPressed : null,
      label: loading ? '$label. Cargando' : label,
      excludeSemantics: true,
      child: SizedBox(
        width: double.infinity,
        child: Material(
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              color: enabled ? bg : bg.withValues(alpha: .45),
              gradient: enabled && style == MusklButtonStyle.primary
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.redLight, AppColors.red],
                    )
                  : null,
              borderRadius: BorderRadius.circular(AppTheme.radius + 3),
              border: style == MusklButtonStyle.secondary
                  ? Border.all(color: AppColors.surfaceHigh)
                  : null,
              boxShadow: enabled && style == MusklButtonStyle.primary
                  ? [
                      BoxShadow(
                        color: AppColors.red.withValues(alpha: .2),
                        blurRadius: 18,
                        offset: const Offset(0, 7),
                      ),
                    ]
                  : null,
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radius + 3),
              onTap: enabled ? onPressed : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Center(
                    heightFactor: 1,
                    child: loading
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: fg),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (icon != null) ...[
                                Icon(icon, size: 20, color: fg),
                                const SizedBox(width: 8),
                              ],
                              Flexible(
                                child: Text(
                                  label,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: fg,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.25,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

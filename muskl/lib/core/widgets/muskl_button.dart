import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
      MusklButtonStyle.primary => (AppColors.red, AppColors.white),
      MusklButtonStyle.secondary => (AppColors.surface, AppColors.white),
      MusklButtonStyle.light => (AppColors.white, AppColors.bgDeep),
      MusklButtonStyle.accent => (AppColors.accent, AppColors.bgDeep),
      MusklButtonStyle.ghost => (Colors.transparent, AppColors.textMuted),
    };
    final enabled = onPressed != null && !loading;

    return Semantics(
      button: true,
      enabled: enabled,
      onTap: enabled ? onPressed : null,
      label: loading ? '$label. Cargando' : label,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 54),
        child: SizedBox(
          width: double.infinity,
          child: Material(
            color: enabled ? bg : bg.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(AppTheme.radius),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radius),
              onTap: enabled ? onPressed : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Center(
                  heightFactor: 1,
                  child: loading
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child:
                              CircularProgressIndicator(strokeWidth: 2.5, color: fg),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (icon != null) ...[
                              Icon(icon, size: 20, color: fg),
                              const SizedBox(width: 8),
                            ],
                            Flexible(child: Text(
                              label.toUpperCase(),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.nunitoSans(
                                color: fg,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.25,
                              ),
                            )),
                          ],
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

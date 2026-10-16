import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';

/// Estructura común de las pantallas de acceso: flecha atrás,
/// sobretítulo rojo, título en mayúsculas y contenido con scroll.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.children,
    this.kicker,
    this.subtitle,
    this.showBack = true,
    this.bottom,
  });

  final String title;
  final String? kicker;
  final String? subtitle;
  final bool showBack;
  final List<Widget> children;

  /// Zona fija al final (botón principal).
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showBack)
                      IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.surface,
                        ),
                        icon: const Icon(Icons.chevron_left,
                            color: AppColors.white),
                        onPressed: () => context.canPop()
                            ? context.pop()
                            : context.go('/login'),
                      )
                    else
                      const SizedBox(height: 48),
                    const SizedBox(height: 20),
                    if (kicker != null)
                      Text(
                        kicker!.toUpperCase(),
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: AppColors.red),
                      ),
                    Text(
                      title.toUpperCase(),
                      style: theme.textTheme.headlineLarge,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.textMuted, fontSize: 16),
                      ),
                    ],
                    const SizedBox(height: 28),
                    ...children,
                  ],
                ),
              ),
            ),
            if (bottom != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: bottom,
              ),
          ],
        ),
      ),
    );
  }
}

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
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showBack)
                          IconButton.filled(
                            tooltip: 'Volver',
                            style: IconButton.styleFrom(
                              backgroundColor: AppColors.surface,
                            ),
                            icon: Icon(Icons.chevron_left,
                                color: AppColors.white),
                            onPressed: () => context.canPop()
                                ? context.pop()
                                : context.go('/login'),
                          )
                        else
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Row(children: [
                              Icon(Icons.fitness_center,
                                  color: AppColors.red, size: 28),
                              SizedBox(width: 12),
                              Text('MUSKL',
                                  style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 2)),
                            ]),
                          ),
                        const SizedBox(height: 24),
                        if (kicker != null) ...[
                          Text(
                            kicker!,
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: AppColors.red),
                          ),
                          const SizedBox(height: 10),
                        ],
                        Text(
                          title,
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
        ),
      ),
    );
  }
}

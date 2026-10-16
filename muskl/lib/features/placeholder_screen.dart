import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/widgets/muskl_button.dart';
import '../main.dart';

/// Pantalla provisional para los destinos que aún no se programan
/// (onboarding, inicio de cliente, panel de entrenador y de admin).
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen(
      {super.key, required this.title, this.canSignOut = true});

  final String title;
  final bool canSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(title.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              const Text('Pantalla pendiente de programar',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 16)),
              if (canSignOut) ...[
                const SizedBox(height: 32),
                MusklButton(
                  label: 'Cerrar sesión',
                  style: MusklButtonStyle.secondary,
                  onPressed: authController.signOut,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Puntaje 0-4: longitud >= 8, mayúscula, número y símbolo.
int passwordScore(String p) {
  var s = 0;
  if (p.length >= 8) s++;
  if (RegExp(r'[A-Z]').hasMatch(p)) s++;
  if (RegExp(r'\d').hasMatch(p)) s++;
  if (RegExp(r'[^A-Za-z0-9]').hasMatch(p)) s++;
  return s;
}

/// Indicador de seguridad de cuatro barras.
class PasswordStrength extends StatelessWidget {
  const PasswordStrength({super.key, required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final score = passwordScore(password);
    final (label, color) = switch (score) {
      0 || 1 => ('Débil', AppColors.red),
      2 => ('Regular', AppColors.yellow),
      3 => ('Buena', AppColors.yellow),
      _ => ('Fuerte', AppColors.success),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < 4; i++)
              Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: i < 3 ? 6 : 0),
                  decoration: BoxDecoration(
                    color: password.isNotEmpty && i < score
                        ? color
                        : AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          password.isEmpty
              ? 'Mínimo 8 caracteres, con mayúscula, número y símbolo'
              : 'Seguridad: $label',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppColors.textMuted, fontSize: 14),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/muskl_button.dart';
import '../../core/widgets/muskl_card.dart';
import '../../main.dart';

String _fmt(DateTime? d) {
  if (d == null) return '—';
  const m = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic'
  ];
  return '${d.day.toString().padLeft(2, '0')} ${m[d.month - 1]} ${d.year}';
}

class _StatusLayout extends StatelessWidget {
  const _StatusLayout({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    this.details = const [],
    this.buttonLabel = 'Entendido',
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final List<(String, String)> details;
  final String buttonLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 44, color: iconColor),
              ),
              const SizedBox(height: 24),
              Text(title.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium),
              const SizedBox(height: 12),
              Text(message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.textMuted, fontSize: 16)),
              if (details.isNotEmpty) ...[
                const SizedBox(height: 24),
                MusklCard(
                  child: Column(
                    children: [
                      for (final (k, v) in details)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(k.toUpperCase(),
                                    style: theme.textTheme.labelSmall
                                        ?.copyWith(color: AppColors.textMuted)),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(v,
                                    textAlign: TextAlign.right,
                                    style: theme.textTheme.titleMedium),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const Spacer(),
              // "Entendido" cierra la sesión; el router vuelve al login.
              MusklButton(
                  label: buttonLabel, onPressed: authController.signOut),
            ],
          ),
        ),
      ),
    );
  }
}

/// Entrenador o admin esperando aprobación.
class PendingScreen extends StatelessWidget {
  const PendingScreen({super.key});
  @override
  Widget build(BuildContext context) => const _StatusLayout(
        icon: Icons.hourglass_top,
        iconColor: AppColors.yellow,
        title: 'Cuenta en revisión',
        message:
            'Tu solicitud está siendo revisada por el gimnasio. Te avisaremos por correo cuando sea aprobada.',
        buttonLabel: 'Cerrar sesión',
      );
}

/// Solicitud rechazada: muestra el motivo.
class RejectedScreen extends StatelessWidget {
  const RejectedScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = authController.session;
    return _StatusLayout(
      icon: Icons.block,
      iconColor: AppColors.red,
      title: 'Solicitud rechazada',
      message: 'El gimnasio no aprobó tu solicitud de cuenta.',
      details: [('Motivo', s?.reason ?? 'No especificado')],
    );
  }
}

/// Baja hecha por un admin. Sin "Contactar al gimnasio": solo informa.
class DeactivatedScreen extends StatelessWidget {
  const DeactivatedScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = authController.session;
    return _StatusLayout(
      icon: Icons.person_off_outlined,
      iconColor: AppColors.red,
      title: 'Tu cuenta fue dada de baja',
      message:
          'Ya no puedes acceder a tu rutina, asistencia ni progreso. Tus datos se conservan por 90 días.',
      details: [
        if (s?.memberNumber != null) ('Socio', s!.memberNumber!),
        ('Motivo', s?.reason ?? '—'),
        ('Fecha', _fmt(s?.deactivatedAt)),
        ('Dada por', s?.deactivatedBy ?? '—'),
        ('Reactivación disponible hasta', _fmt(s?.reactivationUntil)),
      ],
    );
  }
}

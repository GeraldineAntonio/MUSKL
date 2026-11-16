import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/widgets/muskl_button.dart';
import '../core/widgets/muskl_card.dart';

/// Presentation only: dashboard data still comes from the authenticated API.
class ClientHomeContent extends StatelessWidget {
  const ClientHomeContent({super.key, required this.data, required this.onNavigate});
  final Map<String, dynamic> data;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final name = (data['first_name'] ?? '').toString().trim();
    final routine = (data['routine_name'] ?? '').toString().trim();
    final trainer = (data['trainer_name'] ?? '').toString().trim();
    final pending = (data['pending_trainer_id'] ?? '').toString().isNotEmpty;
    final hasRoutine = routine.isNotEmpty;
    final nextRoute = hasRoutine || trainer.isNotEmpty
        ? '/home/routine' : '/home/trainers';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('TU ESPACIO MUSKL', style: text.labelSmall?.copyWith(color: AppColors.red)),
      const SizedBox(height: 8),
      Text(name.isEmpty ? 'Hola, ¿entrenamos?' : 'Hola, $name', style: text.headlineMedium),
      const SizedBox(height: 8),
      Text('Un paso más hacia tu objetivo.', style: text.bodyLarge?.copyWith(color: AppColors.textMuted)),
      const SizedBox(height: 28),
      MusklCard(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.red.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.fitness_center, color: AppColors.red),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text('Tu entrenamiento', style: text.titleMedium)),
          ]),
          const SizedBox(height: 20),
          Text(hasRoutine ? routine : pending ? 'Tu solicitud está en revisión' : trainer.isEmpty ? 'Empieza con un entrenador' : 'Tu rutina está por llegar', style: text.headlineMedium),
          const SizedBox(height: 10),
          Text(hasRoutine
              ? 'Consulta tus ejercicios y registra cada serie a tu ritmo.'
              : pending ? 'Tu entrenador debe aceptar la solicitud antes de asignarte una rutina.'
              : trainer.isEmpty ? 'Elige quién te acompañará y solicita tu primera rutina.'
              : '$trainer te asignará los ejercicios. Puedes revisar aquí el estado de tu rutina.',
              style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: 24),
          MusklButton(label: hasRoutine ? 'Ver mi rutina' : pending ? 'Ver solicitud' : trainer.isEmpty ? 'Elegir entrenador' : 'Ver estado de mi rutina',
            icon: Icons.arrow_forward_rounded, onPressed: () => onNavigate(nextRoute)),
        ]),
      ),
      if (data['new_phase_notification'] != null) ...[
        const SizedBox(height: 12),
        MusklButton(label: 'Revisar nueva fase', style: MusklButtonStyle.accent,
          icon: Icons.auto_awesome_outlined, onPressed: () => onNavigate('/home/phase-available')),
      ],
      const SizedBox(height: 28),
      Text('Tu constancia', style: text.titleLarge),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (context, constraints) {
        final narrow = constraints.maxWidth < 340 || MediaQuery.textScalerOf(context).scale(1) > 1.3;
        final cards = [
          _ProgressTile(value: '${data['gym_attendance_streak'] ?? 0}', label: 'Días de racha', icon: Icons.local_fire_department_outlined),
          _ProgressTile(value: '${data['attendance_total'] ?? 0}', label: 'Visitas registradas', icon: Icons.check_circle_outline),
        ];
        return narrow ? Column(children: [cards[0], const SizedBox(height: 12), cards[1]])
          : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: cards[0]), const SizedBox(width: 12), Expanded(child: cards[1])]);
      }),
      const SizedBox(height: 12),
      MusklCard(onTap: () => onNavigate('/home/attendance'), child: Row(children: [
        const Icon(Icons.calendar_month_outlined, color: AppColors.accent),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Registrar asistencia', style: text.titleMedium),
          const SizedBox(height: 4),
          Text('Consulta también tu calendario de visitas', style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
        ])),
        const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
      ])),
      const SizedBox(height: 28),
      Text('Tu equipo y tu plan', style: text.titleLarge),
      const SizedBox(height: 12),
      MusklCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(trainer.isEmpty ? 'Entrenador por asignar' : trainer, style: text.titleMedium),
        const SizedBox(height: 6),
        Text('Socio ${data['member_number'] ?? '—'} · ${data['plan_name'] ?? 'Sin plan asignado'}', style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
        if ((data['goal'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Objetivo: ${data['goal']}', style: text.bodyMedium),
        ],
        const SizedBox(height: 12),
        TextButton.icon(onPressed: () => onNavigate('/home/profile'), icon: const Icon(Icons.person_outline), label: const Text('Ver mi perfil')),
      ])),
    ]);
  }
}

class _ProgressTile extends StatelessWidget {
  const _ProgressTile({required this.value, required this.label, required this.icon});
  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => MusklCard(child: SizedBox(width: double.infinity,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: AppColors.accent, size: 22),
      const SizedBox(height: 12),
      Text(value, style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(color: AppColors.textMuted)),
    ])));
}

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/widgets/muskl_button.dart';
import '../core/widgets/muskl_card.dart';
import '../core/widgets/profile_photo_avatar.dart';

/// Presentación del inicio del socio con datos del dashboard autenticado.
class ClientHomeContent extends StatelessWidget {
  const ClientHomeContent({
    super.key,
    required this.data,
    required this.onNavigate,
  });

  final Map<String, dynamic> data;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final firstName = (data['first_name'] ?? '').toString().trim();
    final lastName = (data['last_name'] ?? '').toString().trim();
    final fullName = '$firstName $lastName'.trim();
    final trainer = (data['trainer_name'] ?? '').toString().trim();
    final routine = (data['routine_name'] ?? '').toString().trim();
    final hasRoutine = routine.isNotEmpty;
    final pending = (data['pending_trainer_id'] ?? '').toString().isNotEmpty;
    final photoUrl = (data['profile_photo_url'] ?? '').toString();
    final now =
        DateTime.tryParse(data['today']?.toString() ?? '') ?? DateTime.now();
    final membershipStarted =
        DateTime.tryParse(data['membership_started_on']?.toString() ?? '');
    final membershipDays = membershipStarted == null
        ? null
        : DateTime(now.year, now.month, now.day)
            .difference(DateTime(membershipStarted.year,
                membershipStarted.month, membershipStarted.day))
            .inDays
            .clamp(0, 99999);
    final weekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final attendedDates = Set<String>.from(
      data['attendance_7d_dates'] as List? ?? const [],
    );
    final todayLabel = [
      'LUNES',
      'MARTES',
      'MIÉRCOLES',
      'JUEVES',
      'VIERNES',
      'SÁBADO',
      'DOMINGO',
    ][now.weekday - 1];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ProfilePhotoAvatar(
              radius: 24,
              image: photoUrl.isEmpty ? null : NetworkImage(photoUrl),
              name: fullName,
              allowEdit: false,
              onEdit: () {},
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('BUEN DÍA',
                      style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1)),
                  Text(
                    firstName.isEmpty ? '¿Entrenamos?' : firstName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                    ),
                  ),
                ],
              ),
            ),
            Badge(
              isLabelVisible: data['new_phase_notification'] != null,
              backgroundColor: AppColors.red,
              child: IconButton.filledTonal(
                tooltip: 'Notificaciones',
                onPressed: () => onNavigate('/home/notifications'),
                icon: const Icon(Icons.notifications_none_outlined),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        MusklCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('SOCIO Nº',
                            style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 10,
                                letterSpacing: 1,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text(
                          (data['member_number'] ?? '—').toString(),
                          style: const TextStyle(
                            color: AppColors.red,
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if ((data['plan_name'] ?? '').toString().isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.red.withValues(alpha: .13),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        data['plan_name'].toString().toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.red,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .6),
                      ),
                    ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onNavigate(
                    trainer.isEmpty ? '/home/trainers' : '/home/profile'),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 17,
                      backgroundColor: AppColors.bg,
                      child: Icon(Icons.fitness_center,
                          size: 16, color: AppColors.red),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ENTRENADOR ASIGNADO',
                              style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: .7)),
                          const SizedBox(height: 2),
                          Text(
                            trainer.isNotEmpty
                                ? trainer
                                : pending
                                    ? 'Solicitud en revisión'
                                    : 'Elegir entrenador',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: AppColors.textMuted),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ActivityMetric(
                value: '${data['gym_attendance_streak'] ?? 0}',
                label: 'DÍAS DE RACHA',
                icon: Icons.local_fire_department,
                highlighted: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActivityMetric(
                value: '${membershipDays ?? data['attendance_total'] ?? 0}',
                label: membershipDays == null
                    ? 'VISITAS REGISTRADAS'
                    : 'DÍAS DESDE QUE EMPEZASTE',
                icon: Icons.calendar_month_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _sectionHeading(
          context,
          'Asistencia semanal',
          action: 'Ver mes',
          onAction: () => onNavigate('/home/attendance'),
        ),
        MusklCard(
          onTap: () => onNavigate('/home/attendance'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (index) {
              final date = weekStart.add(Duration(days: index));
              final dateKey =
                  '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
              final attended = attendedDates.contains(dateKey);
              const labels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(labels[index],
                      style:
                          TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  const SizedBox(height: 8),
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: attended ? AppColors.red : Colors.transparent,
                      border: dateKey ==
                              '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}'
                          ? Border.all(color: AppColors.accent)
                          : attended
                              ? null
                              : Border.all(color: AppColors.surfaceHigh),
                    ),
                    child: attended
                        ? Icon(Icons.check, size: 16, color: AppColors.white)
                        : Text('${date.day}',
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 10)),
                  ),
                ],
              );
            }),
          ),
        ),
        const SizedBox(height: 18),
        _sectionHeading(context, 'Tu rutina de hoy'),
        _RoutineHero(
          routine: routine,
          hasRoutine: hasRoutine,
          pendingTrainer: pending,
          trainer: trainer,
          todayLabel: todayLabel,
          phase: (data['phase_number'] ?? '').toString(),
          plan: (data['plan_name'] ?? '').toString(),
          onTap: () => onNavigate(hasRoutine || trainer.isNotEmpty
              ? '/home/routine'
              : '/home/trainers'),
        ),
        if (data['new_phase_notification'] != null) ...[
          const SizedBox(height: 12),
          MusklButton(
            label: 'Nueva fase disponible',
            style: MusklButtonStyle.accent,
            icon: Icons.auto_awesome_outlined,
            onPressed: () => onNavigate('/home/phase-available'),
          ),
        ],
      ],
    );
  }
}

Widget _sectionHeading(BuildContext context, String title,
        {String? action, VoidCallback? onAction}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Expanded(
            child: Text(title.toUpperCase(),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: .5,
                    )),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                  foregroundColor: AppColors.red,
                  visualDensity: VisualDensity.compact),
              child: Text(action),
            ),
        ],
      ),
    );

class _ActivityMetric extends StatelessWidget {
  const _ActivityMetric({
    required this.value,
    required this.label,
    required this.icon,
    this.highlighted = false,
  });

  final String value;
  final String label;
  final IconData icon;
  final bool highlighted;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 112),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: highlighted ? AppColors.accent : AppColors.surface,
          border: highlighted ? null : Border.all(color: AppColors.surfaceHigh),
          borderRadius: BorderRadius.circular(19),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                color: highlighted ? AppColors.bgDeep : AppColors.red,
                size: 20),
            const SizedBox(height: 5),
            Text(value,
                style: TextStyle(
                    color: highlighted ? AppColors.bgDeep : AppColors.white,
                    fontSize: 28,
                    height: 1,
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 5),
            Text(label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: highlighted ? AppColors.bgDeep : AppColors.textMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .5)),
          ],
        ),
      );
}

class _RoutineHero extends StatelessWidget {
  const _RoutineHero({
    required this.routine,
    required this.hasRoutine,
    required this.pendingTrainer,
    required this.trainer,
    required this.todayLabel,
    required this.phase,
    required this.plan,
    required this.onTap,
  });

  final String routine;
  final bool hasRoutine;
  final bool pendingTrainer;
  final String trainer;
  final String todayLabel;
  final String phase;
  final String plan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = hasRoutine
        ? routine
        : pendingTrainer
            ? 'Solicitud en revisión'
            : trainer.isEmpty
                ? 'Empieza con un entrenador'
                : 'Rutina por asignar';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 154,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.surfaceHigh),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset('assets/images/splash.jpg', fit: BoxFit.cover),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Color.fromRGBO(0, 0, 0, .88),
                    Color.fromRGBO(0, 0, 0, .65),
                    Color.fromRGBO(0, 0, 0, .25),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.red.withValues(alpha: .2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text('HOY · $todayLabel',
                              style: const TextStyle(
                                  color: AppColors.redLight,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: .7)),
                        ),
                        const Spacer(),
                        Text(title.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -.3)),
                        const SizedBox(height: 4),
                        Text(
                          hasRoutine
                              ? 'Fase ${phase.isEmpty ? '—' : phase} · ${plan.isEmpty ? 'Tu plan' : plan}'
                              : pendingTrainer
                                  ? 'Tu entrenador confirmará pronto.'
                                  : trainer.isEmpty
                                      ? 'Solicita apoyo para recibir tu primera rutina.'
                                      : '$trainer te asignará los ejercicios.',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.red,
                    child: Icon(Icons.play_arrow_rounded,
                        color: AppColors.white, size: 30),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

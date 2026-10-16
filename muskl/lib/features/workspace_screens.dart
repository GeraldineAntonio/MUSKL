import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_colors.dart';
import '../core/widgets/muskl_bottom_nav.dart';
import '../core/widgets/muskl_button.dart';
import '../core/widgets/muskl_card.dart';
import '../core/widgets/muskl_text_field.dart';
import 'auth/auth_models.dart';
import '../main.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    await authController.restoreSession();
    if (mounted && authController.session == null) context.go('/welcome');
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 28),
            child: Column(
              children: [
                const Spacer(),
                Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    color: AppColors.red,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.fitness_center,
                      size: 34, color: AppColors.white),
                ),
                const SizedBox(height: 14),
                Text('MUSKL', style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 8),
                Text('ENTRENA · REGISTRA · SUPERA',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.textMuted,
                          letterSpacing: 2,
                        )),
                const Spacer(),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: const LinearProgressIndicator(
                    minHeight: 3,
                    backgroundColor: AppColors.surfaceHigh,
                    valueColor: AlwaysStoppedAnimation(AppColors.red),
                  ),
                ),
                const SizedBox(height: 12),
                Text('SISTEMA DE RUTINAS Y PROGRESO FÍSICO',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.textMuted,
                          letterSpacing: 1.4,
                        )),
              ],
            ),
          ),
        ),
      );
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: Stack(children: [
        Positioned.fill(
          child: Image.asset('assets/images/splash.jpg', fit: BoxFit.cover),
        ),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.fromRGBO(0, 0, 0, 0.28),
                  Color.fromRGBO(0, 0, 0, 0.38),
                  Color.fromRGBO(0, 0, 0, 0.76),
                ],
                stops: [0, 0.48, 1],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Spacer(),
                    const Icon(Icons.fitness_center,
                        color: AppColors.red, size: 46),
                    const SizedBox(height: 14),
                    const Text('MUSKL',
                        style: TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.w900,
                            color: AppColors.white)),
                    const Text('ENTRENA. REGISTRA. SUPERA.',
                        style: TextStyle(
                            letterSpacing: 2, color: AppColors.white)),
                    const SizedBox(height: 35),
                    const Text('TU MEJOR\nVERSIÓN\nEMPIEZA HOY',
                        style: TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.w900,
                            height: 0.96,
                            color: AppColors.white)),
                    const Spacer(),
                    MusklButton(
                        label: 'Iniciar sesión',
                        icon: Icons.arrow_forward,
                        onPressed: () => context.go('/login')),
                    const SizedBox(height: 10),
                    MusklButton(
                        label: 'Registrarme',
                        style: MusklButtonStyle.secondary,
                        onPressed: () => context.go('/register')),
                    const SizedBox(height: 20),
                    const Center(
                        child: Text('SISTEMA DE RUTINAS Y PROGRESO FÍSICO',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.white,
                                letterSpacing: 1.1))),
                    const Spacer(),
                  ])),
        ),
      ]));
}

class WorkspacePage extends StatelessWidget {
  const WorkspacePage(
      {super.key,
      required this.title,
      required this.child,
      required this.items,
      required this.selected,
      this.kicker});
  final String title;
  final Widget child;
  final List<(String, IconData, String)> items;
  final int selected;
  final String? kicker;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (kicker != null)
                  Text(kicker!.toUpperCase(),
                      style: const TextStyle(
                          color: AppColors.red,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2)),
                Text(title.toUpperCase(),
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900)),
              ],
            ),
            actions: [
              IconButton(
                  tooltip: 'Notificaciones',
                  onPressed: () {
                    final route = switch (authController.session?.role) {
                      UserRole.client => '/home/phase-available',
                      UserRole.trainer => '/trainer',
                      UserRole.admin => '/admin/requests',
                      null => '/',
                    };
                    context.push(route);
                  },
                  icon: const Icon(Icons.notifications_none)),
            ]),
        body: SafeArea(
            child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [child])),
        bottomNavigationBar: MusklBottomNav(
          items: items.map((e) => MusklNavItem(e.$1, e.$2)).toList(),
          currentIndex: selected,
          onTap: (i) => context.go(items[i].$3),
        ),
      );
}

const _clientNav = [
  ('Inicio', Icons.home_outlined, '/home'),
  ('Rutina', Icons.fitness_center, '/home/routine'),
  ('Asistencia', Icons.calendar_month_outlined, '/home/attendance'),
  ('Perfil', Icons.person_outline, '/home/profile'),
];
const _trainerNav = [
  ('Clientes', Icons.people_outline, '/trainer'),
  ('Rutinas', Icons.fitness_center, '/trainer/routines'),
  ('Crear', Icons.add_circle_outline, '/trainer/routine/new'),
  ('Ajustes', Icons.settings_outlined, '/trainer/settings'),
];
const _adminNav = [
  ('Panel', Icons.dashboard_outlined, '/admin'),
  ('Usuarios', Icons.people_outline, '/admin/users'),
  ('Rutinas', Icons.fitness_center, '/admin/routines'),
  ('Ajustes', Icons.settings_outlined, '/admin/settings'),
];

Widget _section(String title, {String? action, VoidCallback? onAction}) =>
    Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Row(children: [
        Expanded(
            child: Text(title.toUpperCase(),
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1))),
        if (action != null)
          TextButton(
              onPressed: onAction,
              child: Text(action, style: const TextStyle(color: AppColors.red)))
      ]),
    );

Widget _metric(String value, String label,
        {Color color = AppColors.white,
        Color background = AppColors.surface}) =>
    Expanded(
      child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.surfaceHigh)),
          child: Column(children: [
            Text(value,
                style: TextStyle(
                    fontSize: 25, fontWeight: FontWeight.w900, color: color)),
            const SizedBox(height: 4),
            Text(label.toUpperCase(),
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 11))
          ])),
    );

Widget _record(String title, String subtitle,
        {IconData icon = Icons.fitness_center,
        String? badge,
        VoidCallback? onTap}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: MusklCard(
              child: Row(children: [
            CircleAvatar(
                backgroundColor: AppColors.bg,
                child: Icon(icon, color: AppColors.red, size: 20)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 13))
                ])),
            if (badge != null)
              Text(badge,
                  style: const TextStyle(
                      color: AppColors.yellow, fontWeight: FontWeight.bold)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ]))),
    );

class ClientDashboardScreen extends StatefulWidget {
  const ClientDashboardScreen({super.key});
  @override
  State<ClientDashboardScreen> createState() => _ClientDashboardScreenState();
}

class _ClientDashboardScreenState extends State<ClientDashboardScreen> {
  late Future<Map<String, dynamic>> _dashboard;

  @override
  void initState() {
    super.initState();
    _dashboard = authController.clientDashboard();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
      future: _dashboard,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return Scaffold(
              body: Center(
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                          'No se pudo cargar tu información: ${snapshot.error}',
                          style: const TextStyle(color: AppColors.red)))));
        }
        final data = snapshot.data ?? {};
        final dates =
            Set<String>.from(data['attendance_7d_dates'] as List? ?? []);
        final now = DateTime.tryParse(data['today']?.toString() ?? '') ??
            DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final week =
            List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));
        return WorkspacePage(
            title: 'Hola, ${data['first_name'] ?? ''}',
            kicker: 'MUSKL · SOCIO ACTIVO',
            items: _clientNav,
            selected: 0,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              MusklCard(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Row(children: [
                      const Text('SOCIO Nº',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textMuted)),
                      const Spacer(),
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                              color: AppColors.red.withValues(alpha: .16),
                              borderRadius: BorderRadius.circular(20)),
                          child: Text(
                              (data['goal'] ?? 'TU OBJETIVO')
                                  .toString()
                                  .toUpperCase(),
                              style: TextStyle(
                                  color: AppColors.red,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800)))
                    ]),
                    const SizedBox(height: 3),
                    Text('${data['member_number'] ?? '—'}',
                        style: TextStyle(
                            fontSize: 29,
                            fontWeight: FontWeight.w900,
                            color: AppColors.red)),
                    const Divider(height: 20, color: AppColors.surfaceHigh),
                    Row(children: [
                      const Icon(Icons.person, size: 15),
                      const SizedBox(width: 6),
                      Text(
                          'Entrenador: ${data['trainer_name'] ?? 'Sin asignar'}'),
                      const Spacer(),
                      TextButton(
                          onPressed: () => context.go('/home/profile'),
                          child: const Text('Mi perfil'))
                    ])
                  ])),
              _section('Tu actividad'),
              Row(children: [
                _metric('${data['workouts_7d'] ?? 0}', 'Rutinas · 7 días',
                    color: AppColors.bgDeep, background: AppColors.yellow),
                const SizedBox(width: 8),
                _metric(
                    '${data['attendance_total'] ?? 0}', 'Asistencias totales')
              ]),
              _section('Asistencia semanal',
                  action: 'Ver mes',
                  onAction: () => context.go('/home/attendance')),
              MusklCard(
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(7, (i) {
                        final date = week[i];
                        final attended = dates.contains(
                            '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}');
                        return Column(children: [
                          Text(
                              [
                                'L',
                                'M',
                                'M',
                                'J',
                                'V',
                                'S',
                                'D'
                              ][date.weekday - 1],
                              style:
                                  const TextStyle(color: AppColors.textMuted)),
                          const SizedBox(height: 8),
                          Icon(
                              attended
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                              color: attended
                                  ? AppColors.red
                                  : AppColors.textMuted,
                              size: 23)
                        ]);
                      }))),
              _section('Tu rutina de hoy'),
              InkWell(
                  onTap: () => context.go('/home/routine'),
                  child: Container(
                      height: 126,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.surfaceHigh),
                          gradient: const LinearGradient(
                              colors: [AppColors.surface, Color(0xFF272126)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight)),
                      child: Row(children: [
                        const Icon(Icons.fitness_center,
                            size: 40, color: AppColors.textMuted),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                      color:
                                          AppColors.red.withValues(alpha: .2),
                                      borderRadius: BorderRadius.circular(20)),
                                  child: Text(
                                      'HOY · ${[
                                        'LUN',
                                        'MAR',
                                        'MIÉ',
                                        'JUE',
                                        'VIE',
                                        'SÁB',
                                        'DOM'
                                      ][now.weekday - 1]}',
                                      style: TextStyle(
                                          color: AppColors.red,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800))),
                              const Spacer(),
                              Text(
                                  '${data['routine_name'] ?? 'SIN RUTINA ASIGNADA'}',
                                  style: TextStyle(
                                      fontSize: 23,
                                      fontWeight: FontWeight.w900)),
                              Text(
                                  'Fase ${data['phase_number'] ?? '—'} · ${data['plan_name'] ?? 'Sin plan'}',
                                  style: TextStyle(color: AppColors.textMuted)),
                            ])),
                        const CircleAvatar(
                            backgroundColor: AppColors.red,
                            child:
                                Icon(Icons.play_arrow, color: AppColors.white)),
                      ]))),
              const SizedBox(height: 12),
              if (data['new_phase_notification'] != null)
                MusklButton(
                    label: 'Nueva fase disponible',
                    style: MusklButtonStyle.accent,
                    onPressed: () => context.push('/home/phase-available')),
            ]));
      });
}

class ClientRoutineScreen extends StatefulWidget {
  const ClientRoutineScreen({super.key});
  @override
  State<ClientRoutineScreen> createState() => _ClientRoutineScreenState();
}

class _ClientRoutineScreenState extends State<ClientRoutineScreen> {
  late int _day;
  late Future<Map<String, dynamic>> _routine;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _day = DateTime.now().weekday;
    _load();
  }

  void _load() => _routine = authController.clientRoutine(day: _day);

  Future<void> _complete() async {
    setState(() => _saving = true);
    try {
      final completion = await authController.completeClientWorkout();
      if (mounted) {
        context.push(Uri(path: '/home/complete', queryParameters: {
          'exercise_count': completion['exercise_count'].toString(),
          if (completion['duration_seconds'] != null)
            'duration_seconds': completion['duration_seconds'].toString(),
          'date': completion['date']?.toString() ?? '',
        }).toString());
      }
      if (mounted) setState(_load);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo completar la rutina: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => WorkspacePage(
      title: 'Mi rutina',
      items: _clientNav,
      selected: 1,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: InkWell(
                  onTap: () => setState(() {
                    _day = i + 1;
                    _load();
                  }),
                  child: MusklCard(
                    selected: _day == i + 1,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Text(
                        ['LUN', 'MAR', 'MIÉ', 'JUE', 'VIE', 'SÁB', 'DOM'][i],
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12)),
                  ),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        FutureBuilder<Map<String, dynamic>>(
          future: _routine,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting)
              return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError)
              return Text('No se pudo cargar tu rutina: ${snapshot.error}',
                  style: const TextStyle(color: AppColors.red));
            final data = snapshot.data ?? {};
            if (data['assigned'] != true)
              return const MusklCard(
                  child: Text(
                      'Tu entrenador todavía no te ha asignado una rutina.'));
            final exercises = (data['exercises'] as List? ?? [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MusklCard(
                      child: Row(children: [
                    const Icon(Icons.local_fire_department,
                        color: AppColors.yellow),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(
                            '${data['routine_name']} · ${data['phase_name']} · ${data['goal']}')),
                  ])),
                  _section('Ejercicios del día · ${exercises.length}'),
                  for (final exercise in exercises)
                    _record(exercise['name'].toString(),
                        '${exercise['sets']} series · ${exercise['reps']} repeticiones · ${exercise['rest_seconds']} s descanso',
                        badge: '${exercise['position'] ?? ''}',
                        onTap: () => context
                            .push('/home/exercise?id=${exercise['id']}')),
                  if (exercises.isEmpty)
                    const Text('No hay ejercicios programados para este día.'),
                  MusklButton(
                      label: data['completed_today'] == true
                          ? 'Rutina completada'
                          : 'Marcar rutina completada',
                      icon: Icons.check,
                      loading: _saving,
                      onPressed: exercises.isEmpty ||
                              data['completed_today'] == true ||
                              _day != DateTime.now().weekday
                          ? null
                          : _complete),
                ]);
          },
        ),
      ]));
}

class ExerciseDetailScreen extends StatelessWidget {
  const ExerciseDetailScreen({super.key, this.id = '1'});
  final String id;
  @override
  Widget build(BuildContext context) => WorkspacePage(
      title: 'Detalle de ejercicio',
      items: _clientNav,
      selected: 1,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            height: 190,
            decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20)),
            child: const Center(
                child: Icon(Icons.play_circle_fill,
                    size: 70, color: AppColors.red))),
        _section('Cardio · Ejercicio $id'),
        Text(id == '1' ? 'SPRINT EN CINTA' : 'EJERCICIO DE RUTINA',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
        const SizedBox(height: 14),
        Row(children: [
          _metric('4', 'Series'),
          const SizedBox(width: 8),
          _metric('30 s', 'Trabajo'),
          const SizedBox(width: 8),
          _metric('60 s', 'Descanso')
        ]),
        _section('Cómo se hace'),
        const MusklCard(
            child: Text(
                'Ajusta la velocidad antes de comenzar. Mantén el torso firme y aumenta el ritmo durante el intervalo. Descansa caminando entre series.')),
        const SizedBox(height: 20),
        MusklButton(
            label: 'Terminar ejercicio',
            icon: Icons.check,
            onPressed: () => context.pop()),
      ]));
}

class RoutineCompleteScreen extends StatelessWidget {
  const RoutineCompleteScreen(
      {super.key,
      required this.exerciseCount,
      this.durationSeconds,
      this.date});
  final int exerciseCount;
  final int? durationSeconds;
  final String? date;

  String get durationLabel {
    if (durationSeconds == null) return 'Registrada';
    final minutes = durationSeconds! ~/ 60;
    final seconds = durationSeconds! % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => WorkspacePage(
      title: 'Rutina completada',
      items: _clientNav,
      selected: 1,
      child: Column(children: [
        const SizedBox(height: 20),
        const Icon(Icons.check_circle, size: 110, color: AppColors.red),
        const SizedBox(height: 14),
        const Text('¡LO LOGRASTE!',
            style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                color: AppColors.red)),
        _section(date == null || date!.isEmpty
            ? 'Resumen de hoy'
            : 'Resumen · $date'),
        Row(children: [
          _metric(durationLabel, 'Duración'),
          const SizedBox(width: 8),
          _metric('$exerciseCount', 'Ejercicios'),
          const SizedBox(width: 8),
          _metric('420', 'Calorías', color: AppColors.yellow)
        ]),
        const SizedBox(height: 16),
        const MusklCard(
            selected: true,
            child: Text('RACHA DE 8 DÍAS\nUn día más cumpliendo tu objetivo.',
                textAlign: TextAlign.center)),
        const SizedBox(height: 18),
        MusklButton(
            label: 'Ver asistencia',
            onPressed: () => context.go('/home/attendance')),
      ]));
}

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  late int _year, _month;
  late Future<Map<String, dynamic>> _attendance;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _year = today.year;
    _month = today.month;
    _load();
  }

  void _load() =>
      _attendance = authController.clientAttendance(year: _year, month: _month);

  void _shiftMonth(int delta) {
    final month = DateTime(_year, _month + delta, 1);
    setState(() {
      _year = month.year;
      _month = month.month;
      _load();
    });
  }

  @override
  Widget build(BuildContext context) => WorkspacePage(
      title: 'Mi asistencia',
      items: _clientNav,
      selected: 2,
      child: FutureBuilder<Map<String, dynamic>>(
        future: _attendance,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError)
            return Text('No se pudo cargar la asistencia: ${snapshot.error}',
                style: const TextStyle(color: AppColors.red));
          final data = snapshot.data ?? {};
          final rows = (data['days'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          final attended =
              rows.map((e) => DateTime.parse(e['date'].toString()).day).toSet();
          final offset = DateTime(_year, _month, 1).weekday - 1;
          final daysInMonth = DateTime(_year, _month + 1, 0).day;
          final cellCount = ((offset + daysInMonth + 6) ~/ 7) * 7;
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MusklCard(
                    child: Column(children: [
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                            onPressed: () => _shiftMonth(-1),
                            icon: const Icon(Icons.chevron_left)),
                        Text(
                            '${[
                              'ENERO',
                              'FEBRERO',
                              'MARZO',
                              'ABRIL',
                              'MAYO',
                              'JUNIO',
                              'JULIO',
                              'AGOSTO',
                              'SEPTIEMBRE',
                              'OCTUBRE',
                              'NOVIEMBRE',
                              'DICIEMBRE'
                            ][_month - 1]} $_year',
                            style: Theme.of(context).textTheme.titleMedium),
                        IconButton(
                            onPressed: () => _shiftMonth(1),
                            icon: const Icon(Icons.chevron_right)),
                      ]),
                  const SizedBox(height: 12),
                  const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Text('L'),
                        Text('M'),
                        Text('M'),
                        Text('J'),
                        Text('V'),
                        Text('S'),
                        Text('D')
                      ]),
                  const SizedBox(height: 12),
                  for (var row = 0; row < cellCount ~/ 7; row++)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: List.generate(7, (col) {
                              final day = row * 7 + col - offset + 1;
                              if (day < 1 || day > daysInMonth)
                                return const SizedBox(width: 30, height: 32);
                              final hasAttendance = attended.contains(day);
                              return Container(
                                  width: 30,
                                  height: 32,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: hasAttendance
                                          ? AppColors.red
                                          : Colors.transparent),
                                  child: Text('$day',
                                      style: TextStyle(
                                          color: hasAttendance
                                              ? AppColors.white
                                              : AppColors.textMuted,
                                          fontSize: 12)));
                            }))),
                ])),
                _section('Resumen del mes'),
                Row(children: [
                  _metric('${data['total'] ?? rows.length}', 'Asistencias'),
                  const SizedBox(width: 8),
                  _metric('${attended.length}', 'Días asistidos'),
                ]),
              ]);
        },
      ));
}

class ClientProfileWorkspaceScreen extends StatefulWidget {
  const ClientProfileWorkspaceScreen({super.key});
  @override
  State<ClientProfileWorkspaceScreen> createState() =>
      _ClientProfileWorkspaceScreenState();
}

class _ClientProfileWorkspaceScreenState
    extends State<ClientProfileWorkspaceScreen> {
  late Future<Map<String, dynamic>> _profile;

  @override
  void initState() {
    super.initState();
    _profile = authController.clientDashboard();
  }

  Future<void> _requestDeletion() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('SOLICITAR ELIMINACIÓN'),
              content: const Text(
                  'La solicitud se enviará al administrador del gimnasio.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancelar')),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Enviar')),
              ],
            ));
    if (confirmed != true) return;
    try {
      await authController.requestAccountDeletion();
      if (mounted) {
        setState(() => _profile = authController.clientDashboard());
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Solicitud enviada al gimnasio.')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No se pudo enviar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) => WorkspacePage(
      title: 'Mi perfil',
      items: _clientNav,
      selected: 3,
      child: FutureBuilder<Map<String, dynamic>>(
        future: _profile,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError)
            return Text('No se pudo cargar tu perfil: ${snapshot.error}',
                style: const TextStyle(color: AppColors.red));
          final data = snapshot.data ?? {};
          return Column(children: [
            MusklCard(
                child: Column(children: [
              const CircleAvatar(
                  radius: 38,
                  backgroundColor: AppColors.surfaceHigh,
                  child: Icon(Icons.person, size: 42, color: AppColors.yellow)),
              const SizedBox(height: 10),
              Text('${data['first_name']} ${data['last_name']}'.toUpperCase(),
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w900)),
              Text('${data['member_number'] ?? ''}',
                  style: const TextStyle(
                      color: AppColors.red, fontWeight: FontWeight.bold)),
              Text('${data['goal'] ?? 'OBJETIVO PENDIENTE'}',
                  style: const TextStyle(color: AppColors.textMuted)),
            ])),
            _section('Datos personales'),
            _record('Correo', (data['email'] ?? '').toString(),
                icon: Icons.mail_outline),
            _record('Teléfono', (data['phone'] ?? 'Sin teléfono').toString(),
                icon: Icons.phone_outlined),
            _record('Entrenador',
                (data['trainer_name'] ?? 'Sin asignar').toString(),
                icon: Icons.person_outline),
            _section('Membresía'),
            MusklCard(
                child: Row(children: [
              const Icon(Icons.card_membership, color: AppColors.yellow),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(
                        'PLAN ${(data['plan_name'] ?? 'PENDIENTE').toString().toUpperCase()}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('Vigente hasta ${data['membership_ends_on'] ?? '—'}',
                        style: const TextStyle(color: AppColors.textMuted)),
                  ])),
              const Text('ACTIVO', style: TextStyle(color: AppColors.red)),
            ])),
            if (data['deletion_request_status'] == 'pending')
              MusklCard(
                  child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.hourglass_top,
                          color: AppColors.yellow),
                      title: const Text('SOLICITUD DE BAJA PENDIENTE'),
                      subtitle: Text(
                          'Enviada ${data['deletion_requested_at'] ?? ''}. El gimnasio aún debe revisarla.'))),
            if (data['deletion_request_status'] == 'rejected')
              const MusklCard(
                  child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.info_outline, color: AppColors.red),
                      title: Text('SOLICITUD ANTERIOR RECHAZADA'),
                      subtitle: Text('Puedes enviar una nueva solicitud.'))),
            const SizedBox(height: 16),
            if (data['deletion_request_status'] != 'pending')
              MusklButton(
                  label: 'Solicitar eliminación de mi cuenta',
                  icon: Icons.delete_outline,
                  style: MusklButtonStyle.secondary,
                  onPressed: _requestDeletion),
            _setting('Cambiar contraseña', 'Actualiza tus credenciales',
                Icons.lock_outline,
                onTap: () => _changeAccountPassword(context)),
            const SizedBox(height: 8),
            MusklButton(
                label: 'Cerrar sesión',
                style: MusklButtonStyle.ghost,
                onPressed: authController.signOut),
          ]);
        },
      ));
}

class TrainerDashboardScreen extends StatefulWidget {
  const TrainerDashboardScreen({super.key});
  @override
  State<TrainerDashboardScreen> createState() => _TrainerDashboardScreenState();
}

class _TrainerDashboardScreenState extends State<TrainerDashboardScreen> {
  String search = '';
  late Future<List<Map<String, dynamic>>> _clients;
  late Future<List<Map<String, dynamic>>> _notifications;

  @override
  void initState() {
    super.initState();
    _loadClients();
    _notifications = authController.trainerNotifications();
  }

  void _loadClients() =>
      _clients = authController.trainerClients(search: search);

  @override
  Widget build(BuildContext context) => WorkspacePage(
      title: 'Mis clientes',
      kicker: 'ENTRENADOR',
      items: _trainerNav,
      selected: 0,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FutureBuilder<List<Map<String, dynamic>>>(
            future: _notifications,
            builder: (context, snapshot) {
              final notices = snapshot.data ?? [];
              if (notices.isEmpty) return const SizedBox.shrink();
              return Column(children: [
                _section('Notificaciones'),
                for (final notice in notices)
                  _record(notice['title'].toString(), notice['body'].toString(),
                      icon: Icons.notifications_active_outlined,
                      onTap: () async {
                    await authController.markTrainerNotificationRead(
                        notificationId: notice['id'].toString());
                    final payload = Map<String, dynamic>.from(
                        notice['payload'] as Map? ?? {});
                    if (!mounted) return;
                    setState(() {
                      _notifications = authController.trainerNotifications();
                    });
                    if (notice['kind'] == 'client_activity' &&
                        payload['client_id'] != null) {
                      context
                          .push(Uri(path: '/trainer/client', queryParameters: {
                        'id': payload['client_id'].toString(),
                        'name':
                            notice['body'].toString().split(' completó').first,
                      }).toString());
                    } else if (payload['routine_id'] != null) {
                      context.push(Uri(
                          path: '/trainer/phases',
                          queryParameters: {
                            'id': payload['routine_id'].toString()
                          }).toString());
                    }
                  }),
              ]);
            }),
        _section('Clientes asignados'),
        _SearchField(
            hint: 'Buscar cliente',
            onChanged: (v) => setState(() {
                  search = v;
                  _loadClients();
                })),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _clients,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting)
              return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()));
            if (snapshot.hasError)
              return Text(
                  'No se pudieron cargar tus clientes: ${snapshot.error}',
                  style: const TextStyle(color: AppColors.red));
            final clients = snapshot.data ?? [];
            final today = DateTime.now();
            final atRisk = clients.where((client) {
              final expiry = DateTime.tryParse(
                  client['membership_ends_on']?.toString() ?? '');
              return expiry != null && expiry.difference(today).inDays <= 7;
            }).length;
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    _metric('${clients.length}', 'Clientes'),
                    const SizedBox(width: 8),
                    _metric('${clients.length}', 'Activos',
                        color: AppColors.red),
                    const SizedBox(width: 8),
                    _metric('$atRisk', 'En riesgo', color: AppColors.yellow),
                  ]),
                  for (final client in clients)
                    _record('${client['first_name']} ${client['last_name']}',
                        '${client['routine_name'] ?? 'Sin rutina'} · ${client['membership_plan'] ?? 'Sin membresía'}',
                        icon: Icons.person_outline,
                        badge: '${client['attendance_7d'] ?? 0}',
                        onTap: () => context.push(
                                Uri(path: '/trainer/client', queryParameters: {
                              'name':
                                  '${client['first_name']} ${client['last_name']}',
                              'id': client['id'].toString(),
                              'member':
                                  (client['member_number'] ?? '').toString()
                            }).toString())),
                  if (clients.isEmpty)
                    const Text('Todavía no tienes clientes asignados.'),
                ]);
          },
        ),
      ]));
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.hint, this.onChanged});
  final String hint;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search),
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none)));
}

class TrainerClientDetailScreen extends StatefulWidget {
  const TrainerClientDetailScreen(
      {super.key, this.name = 'Cliente', required this.clientId});
  final String name;
  final String clientId;
  @override
  State<TrainerClientDetailScreen> createState() =>
      _TrainerClientDetailScreenState();
}

class _TrainerClientDetailScreenState extends State<TrainerClientDetailScreen> {
  late Future<Map<String, dynamic>> _client;

  @override
  void initState() {
    super.initState();
    _client = authController.trainerClient(clientId: widget.clientId);
  }

  @override
  Widget build(BuildContext context) => WorkspacePage(
      title: 'Detalle de cliente',
      items: _trainerNav,
      selected: 0,
      child: FutureBuilder<Map<String, dynamic>>(
          future: _client,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Text('No se pudo cargar el cliente: ${snapshot.error}',
                  style: const TextStyle(color: AppColors.red));
            }
            final client = snapshot.data ?? {};
            final dates = (client['attendance_7d_dates'] as List? ?? [])
                .map((date) => date.toString().substring(0, 10))
                .toSet();
            final labels = <String>[];
            final present = <bool>[];
            for (var offset = 6; offset >= 0; offset--) {
              final date = DateTime.now().subtract(Duration(days: offset));
              labels.add(['L', 'M', 'M', 'J', 'V', 'S', 'D'][date.weekday - 1]);
              present
                  .add(dates.contains(date.toIso8601String().substring(0, 10)));
            }
            final fullName = client['first_name'] == null
                ? widget.name
                : '${client['first_name']} ${client['last_name']}';
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MusklCard(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(fullName.toUpperCase(),
                            style: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.w900)),
                        Text(
                            'Socio ${client['member_number'] ?? ''} · ${client['goal'] ?? 'Objetivo pendiente'}'),
                        Text(
                            '${client['membership_plan'] ?? 'Sin membresía'} · vence ${client['membership_ends_on'] ?? 'sin fecha'}'),
                        const SizedBox(height: 12),
                        Row(children: [
                          _metric(
                              '${client['workouts_7d'] ?? 0}', 'Sesiones 7d',
                              color: AppColors.yellow),
                          const SizedBox(width: 8),
                          _metric('${client['attendance_total'] ?? 0}',
                              'Asistencias'),
                          const SizedBox(width: 8),
                          _metric('${client['workouts_total'] ?? 0}', 'Rutinas',
                              color: AppColors.yellow)
                        ])
                      ])),
                  _section('Asistencia semanal'),
                  MusklCard(
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                        for (var i = 0; i < 7; i++)
                          Column(children: [
                            Text(labels[i]),
                            Icon(
                                present[i]
                                    ? Icons.check_circle
                                    : Icons.circle_outlined,
                                color: present[i]
                                    ? AppColors.red
                                    : AppColors.textMuted),
                          ])
                      ])),
                  _section('Rutina activa'),
                  _record(
                      (client['routine_name'] ?? 'Sin rutina asignada')
                          .toString(),
                      client['phase_number'] == null
                          ? 'Sin fase publicada'
                          : 'Fase ${client['phase_number']} · ${client['routine_goal'] ?? client['goal'] ?? ''} · ${client['days_per_week'] ?? '—'} días',
                      onTap: () => context.push('/trainer/routines')),
                  MusklButton(
                      label: 'Asignar otra rutina',
                      icon: Icons.swap_horiz,
                      onPressed: () => context.push('/trainer/routines')),
                ]);
          }));
}

class TrainerRoutinesScreen extends StatefulWidget {
  const TrainerRoutinesScreen({super.key});
  @override
  State<TrainerRoutinesScreen> createState() => _TrainerRoutinesScreenState();
}

class _TrainerRoutinesScreenState extends State<TrainerRoutinesScreen> {
  late Future<List<Map<String, dynamic>>> _routines;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _routines = authController.trainerRoutines();

  Future<void> _publish(Map<String, dynamic> routine) async {
    try {
      await authController.publishTrainerRoutine(
          routineId: routine['id'].toString());
      if (mounted) {
        setState(_reload);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Rutina publicada para asignar.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No se pudo publicar: $e')));
      }
    }
  }

  Future<void> _assign(Map<String, dynamic> routine) async {
    try {
      final clients = await authController.trainerClients();
      if (!mounted) return;
      if (clients.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No tienes clientes activos para asignar.')));
        return;
      }
      final client = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('ASIGNAR A CLIENTE')),
              for (final item in clients)
                ListTile(
                  title: Text('${item['first_name']} ${item['last_name']}'),
                  subtitle: Text('Socio ${item['member_number'] ?? ''}'),
                  onTap: () => Navigator.pop(context, item),
                ),
            ],
          ),
        ),
      );
      if (client == null || !mounted) return;
      await authController.assignTrainerRoutine(
          routineId: routine['id'].toString(),
          phaseId: routine['phase_id'].toString(),
          clientId: client['id'].toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Rutina asignada a ${client['first_name']}.')));
        setState(_reload);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo asignar la rutina: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => WorkspacePage(
      title: 'Mis rutinas',
      items: _trainerNav,
      selected: 1,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _routines,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting)
              return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError)
              return Text(
                  'No se pudieron cargar las rutinas: ${snapshot.error}',
                  style: const TextStyle(color: AppColors.red));
            final routines = snapshot.data ?? [];
            return Column(children: [
              for (final routine in routines) ...[
                _record(routine['name'].toString(),
                    '${routine['goal']} · ${routine['days_per_week']} días · ${routine['assigned_clients']} socios',
                    icon: Icons.fitness_center,
                    onTap: () => context.push(
                            Uri(path: '/trainer/phases', queryParameters: {
                          'id': routine['id'].toString(),
                        }).toString())),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Wrap(spacing: 8, children: [
                    if (routine['phase_status'] != 'published')
                      OutlinedButton.icon(
                          onPressed: () => _publish(routine),
                          icon: const Icon(Icons.publish),
                          label: const Text('Publicar')),
                    if (routine['phase_status'] == 'published')
                      FilledButton.tonalIcon(
                          onPressed: () => _assign(routine),
                          icon: const Icon(Icons.person_add_alt_1),
                          label: const Text('Asignar a cliente')),
                  ]),
                ),
              ],
              if (routines.isEmpty)
                const Text('Todavía no has creado rutinas.'),
            ]);
          },
        ),
        MusklButton(
            label: 'Crear rutina',
            icon: Icons.add,
            onPressed: () => context.go('/trainer/routine/new')),
      ]));
}

class CreateRoutineScreen extends StatefulWidget {
  const CreateRoutineScreen({super.key});
  @override
  State<CreateRoutineScreen> createState() => _CreateRoutineScreenState();
}

class _CreateRoutineScreenState extends State<CreateRoutineScreen> {
  final name = TextEditingController();
  String goal = 'Masa muscular';
  final Set<String> selectedDays = {'LUN', 'MIÉ', 'VIE'};
  final exercises = <String>[];
  bool saving = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WorkspacePage(
      title: 'Nueva rutina',
      items: _trainerNav,
      selected: 2,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        MusklTextField(
            label: 'Nombre de la rutina', controller: name, icon: Icons.edit),
        _section('Objetivo'),
        Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              'Bajar de peso',
              'Masa muscular',
              'Resistencia',
              'Fuerza'
            ]
                .map((v) => ChoiceChip(
                    label: Text(v),
                    selected: goal == v,
                    onSelected: (_) => setState(() => goal = v)))
                .toList()),
        _section('Días por semana'),
        Wrap(
            spacing: 6,
            children: ['LUN', 'MAR', 'MIÉ', 'JUE', 'VIE', 'SÁB', 'DOM']
                .map((d) => FilterChip(
                    label: Text(d),
                    selected: selectedDays.contains(d),
                    onSelected: (selected) => setState(() {
                          if (selected) {
                            selectedDays.add(d);
                          } else {
                            selectedDays.remove(d);
                          }
                        })))
                .toList()),
        _section('Ejercicios',
            action: 'Agregar',
            onAction: () => setState(() => exercises.add(''))),
        for (var i = 0; i < exercises.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('routine-exercise-$i'),
                  initialValue: exercises[i],
                  decoration: InputDecoration(
                    labelText: 'Ejercicio ${i + 1}',
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onChanged: (value) => exercises[i] = value,
                ),
              ),
              IconButton(
                tooltip: 'Quitar ejercicio',
                onPressed:
                    saving ? null : () => setState(() => exercises.removeAt(i)),
                icon: const Icon(Icons.delete_outline, color: AppColors.red),
              ),
            ]),
          ),
        if (error != null)
          Text(error!, style: const TextStyle(color: AppColors.red)),
        MusklButton(
            label: 'Guardar rutina',
            icon: Icons.save_outlined,
            loading: saving,
            onPressed: selectedDays.length < 3 ||
                    exercises.isEmpty ||
                    exercises.any((exercise) => exercise.trim().isEmpty) ||
                    name.text.trim().isEmpty ||
                    saving
                ? null
                : () async {
                    setState(() {
                      saving = true;
                      error = null;
                    });
                    try {
                      const dayNumber = {
                        'LUN': 1,
                        'MAR': 2,
                        'MIÉ': 3,
                        'JUE': 4,
                        'VIE': 5,
                        'SÁB': 6,
                        'DOM': 7
                      };
                      await authController.createTrainerRoutine(
                        name: name.text.trim(),
                        goal: goal,
                        days:
                            selectedDays.map((day) => dayNumber[day]!).toList()
                              ..sort(),
                        exercises: exercises
                            .map((exercise) => exercise.trim())
                            .toList(),
                      );
                      if (mounted) context.go('/trainer/routines');
                    } catch (e) {
                      if (mounted)
                        setState(
                            () => error = 'No se pudo guardar la rutina: $e');
                    } finally {
                      if (mounted) setState(() => saving = false);
                    }
                  }),
      ]));
}

class _PrototypeSettings {
  static String gymName = '';
  static String gymAddress = '';
  static String gymPhone = '';
  static String hours = '';
}

class TrainerSettingsScreen extends StatefulWidget {
  const TrainerSettingsScreen({super.key});
  @override
  State<TrainerSettingsScreen> createState() => _TrainerSettingsScreenState();
}

class _TrainerSettingsScreenState extends State<TrainerSettingsScreen> {
  Map<String, dynamic> _profile = {};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await authController.trainerProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      _message('No se pudo cargar tu perfil: $e');
    }
  }

  String _value(String key) => (_profile[key] ?? '').toString();

  Map<String, bool> get _preferences => Map<String, bool>.from(
      _profile['notification_preferences'] as Map? ?? {});

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _save({
    String? firstName,
    String? lastName,
    String? email,
    String? phone,
    String? specialty,
    String? bio,
    Map<String, bool>? preferences,
  }) async {
    setState(() => _saving = true);
    try {
      final saved = await authController.updateTrainerProfile(
        firstName: firstName ?? _value('first_name'),
        lastName: lastName ?? _value('last_name'),
        email: email ?? _value('email'),
        phone: phone ?? _value('phone'),
        specialty: specialty ?? _value('specialty'),
        bio: bio ?? _value('bio'),
        notificationPreferences: preferences ?? _preferences,
      );
      if (mounted) setState(() => _profile = saved);
      _message('Cambios guardados.');
    } catch (e) {
      _message('No se pudieron guardar los cambios: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editPersonal() async {
    final result = await _editFields(context, 'DATOS PERSONALES', [
      'Nombre',
      'Apellidos',
      'Correo electrónico',
      'Teléfono'
    ], [
      _value('first_name'),
      _value('last_name'),
      _value('email'),
      _value('phone')
    ]);
    if (result == null) return;
    await _save(
        firstName: result[0],
        lastName: result[1],
        email: result[2],
        phone: result[3]);
  }

  Future<void> _editCredentials() async {
    final result = await _editFields(
        context,
        'PERFIL PROFESIONAL',
        ['Especialidad', 'Biografía profesional'],
        [_value('specialty'), _value('bio')],
        multiline: const {1});
    if (result == null) return;
    await _save(specialty: result[0], bio: result[1]);
  }

  Future<void> _changePassword() async {
    final result = await _editFields(
        context,
        'CAMBIAR CONTRASEÑA',
        ['Contraseña actual', 'Nueva contraseña', 'Confirmar contraseña'],
        ['', '', ''],
        obscure: true);
    if (!mounted) return;
    if (result == null) return;
    if (result[1].length < 8 || result[1] != result[2]) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Revisa que la nueva contraseña tenga 8 caracteres y coincida con su confirmación.')));
      return;
    }
    try {
      await authController.changePassword(
          currentPassword: result[0], newPassword: result[1]);
      _message('Contraseña actualizada. Las demás sesiones se cerraron.');
    } catch (e) {
      _message('No se pudo cambiar la contraseña: $e');
    }
  }

  Widget _preference(String label, String key, bool fallback) {
    final preferences = _preferences;
    return SwitchListTile(
      title: Text(label),
      value: preferences[key] ?? fallback,
      activeThumbColor: AppColors.red,
      onChanged: _saving
          ? null
          : (enabled) {
              final updated = {...preferences, key: enabled};
              setState(() => _profile['notification_preferences'] = updated);
              _save(preferences: updated);
            },
    );
  }

  @override
  Widget build(BuildContext context) => WorkspacePage(
      title: 'Ajustes',
      kicker: 'ENTRENADOR · ${_value('first_name').toUpperCase()}',
      items: _trainerNav,
      selected: 3,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              if (_saving) const LinearProgressIndicator(),
              MusklCard(
                  child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(
                          '${_value('first_name')} ${_value('last_name')}'),
                      subtitle: Text('Entrenador · ${_value('specialty')}'))),
              _setting(
                  'Datos personales',
                  '${_value('email')} · ${_value('phone')}',
                  Icons.person_outline,
                  onTap: _editPersonal),
              _setting(
                  'Perfil profesional',
                  '${_value('specialty')} · ${(_profile['certifications'] as List? ?? []).length} certificaciones registradas',
                  Icons.workspace_premium_outlined,
                  onTap: _editCredentials),
              for (final certificate
                  in (_profile['certifications'] as List? ?? []))
                _record(
                    (certificate as Map)['title'].toString(),
                    certificate['verified_at'] == null
                        ? 'Documento registrado · pendiente de verificación'
                        : 'Certificación verificada',
                    icon: Icons.verified_outlined),
              _setting('Cambiar contraseña',
                  'Actualiza tus credenciales de acceso', Icons.lock_outline,
                  onTap: _changePassword),
              _section('Notificaciones'),
              _preference('Actividad de clientes', 'client_activity', true),
              _preference('Rutinas por vencer', 'routine_expiry', true),
              _preference('Recordatorio diario', 'daily_reminder', false),
              const SizedBox(height: 14),
              MusklButton(
                  label: 'Cerrar sesión',
                  style: MusklButtonStyle.secondary,
                  onPressed: authController.signOut),
            ]));
}

Future<List<String>?> _editFields(BuildContext context, String title,
    List<String> labels, List<String> values,
    {bool obscure = false, Set<int> multiline = const {}}) async {
  final controllers = List.generate(
      values.length, (i) => TextEditingController(text: values[i]));
  try {
    return await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < labels.length; i++)
            Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                    controller: controllers[i],
                    obscureText: obscure,
                    minLines: multiline.contains(i) ? 3 : 1,
                    maxLines: multiline.contains(i) ? 6 : 1,
                    decoration: InputDecoration(
                        labelText: labels[i],
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none)))),
        ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext,
                  controllers.map((c) => c.text.trim()).toList()),
              child: const Text('Guardar'))
        ],
      ),
    );
  } finally {
    for (final controller in controllers) {
      controller.dispose();
    }
  }
}

Widget _setting(String title, String subtitle, IconData icon,
        {VoidCallback? onTap}) =>
    MusklCard(
        child: ListTile(
            onTap: onTap,
            contentPadding: EdgeInsets.zero,
            leading: Icon(icon, color: AppColors.yellow),
            title: Text(title),
            subtitle: Text(subtitle),
            trailing: const Icon(Icons.chevron_right)));

Future<void> _changeAccountPassword(BuildContext context) async {
  final values = await _editFields(
      context,
      'CAMBIAR CONTRASEÑA',
      [
        'Contraseña actual',
        'Nueva contraseña',
        'Confirmar contraseña',
      ],
      ['', '', ''],
      obscure: true);
  if (!context.mounted || values == null) return;
  if (values[1].length < 8 || values[1] != values[2]) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text('La nueva contraseña debe tener 8 caracteres y coincidir.')));
    return;
  }
  try {
    await authController.changePassword(
        currentPassword: values[0], newPassword: values[1]);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Contraseña actualizada. Las demás sesiones se cerraron.')));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo cambiar la contraseña: $e')));
    }
  }
}

class _SwitchSetting extends StatelessWidget {
  const _SwitchSetting(
      {required this.label,
      required this.value,
      required this.onChanged,
      this.enabled = true});
  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => SwitchListTile(
        title: Text(label),
        value: value,
        onChanged: enabled ? onChanged : null,
        activeThumbColor: AppColors.red,
      );
}

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late Future<Map<String, dynamic>> _stats;

  @override
  void initState() {
    super.initState();
    _stats = authController.adminDashboard();
  }

  @override
  Widget build(BuildContext context) => WorkspacePage(
        title: 'Panel admin',
        kicker: 'MUSKL GYM · VISTA GLOBAL',
        items: _adminNav,
        selected: 0,
        child: FutureBuilder<Map<String, dynamic>>(
          future: _stats,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Text('No se pudo cargar el resumen: ${snapshot.error}',
                  style: const TextStyle(color: AppColors.red));
            }
            final stats = snapshot.data ?? {};
            final week = (stats['attendance_week'] as List? ?? [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
            final maxAttendance = week.fold<int>(
                1,
                (m, day) => (day['total'] as num).toInt() > m
                    ? (day['total'] as num).toInt()
                    : m);
            final pending = (stats['pending_requests'] as num? ?? 0).toInt();
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (pending > 0)
                    InkWell(
                      onTap: () => context.go('/admin/requests'),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: const Color(0xFF2B2412),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF806414))),
                        child: Row(children: [
                          const CircleAvatar(
                              backgroundColor: AppColors.yellow,
                              child: Icon(Icons.person_add_alt,
                                  color: AppColors.bgDeep)),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text('$pending SOLICITUDES PENDIENTES',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900))),
                          const Icon(Icons.chevron_right,
                              color: AppColors.yellow),
                        ]),
                      ),
                    ),
                  _section('Resumen del gimnasio'),
                  Row(children: [
                    _metric('${stats['clients'] ?? 0}', 'Socios',
                        color: AppColors.bgDeep, background: AppColors.red),
                    const SizedBox(width: 8),
                    _metric('${stats['trainers'] ?? 0}', 'Entrenadores'),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    _metric('${stats['routines'] ?? 0}', 'Rutinas activas'),
                    const SizedBox(width: 8),
                    _metric(
                        '${stats['attendance_today'] ?? 0}', 'Asistencias hoy'),
                  ]),
                  _section('Asistencia · últimos 7 días'),
                  MusklCard(
                      child: SizedBox(
                          height: 115,
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                for (final day in week)
                                  Column(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Container(
                                            width: 21,
                                            height: ((day['total'] as num)
                                                        .toDouble() /
                                                    maxAttendance *
                                                    90)
                                                .clamp(5, 90),
                                            decoration: BoxDecoration(
                                                color: AppColors.red,
                                                borderRadius:
                                                    BorderRadius.circular(5))),
                                        const SizedBox(height: 5),
                                        Text(
                                            day['date'].toString().substring(8),
                                            style:
                                                const TextStyle(fontSize: 10)),
                                      ]),
                              ]))),
                  _section('Accesos rápidos'),
                  _record('Usuarios', 'Socios, entrenadores y administradores',
                      icon: Icons.people,
                      onTap: () => context.go('/admin/users')),
                  _record('Solicitudes', 'Aprobar o rechazar cuentas',
                      icon: Icons.fact_check_outlined,
                      badge: pending == 0 ? null : '$pending',
                      onTap: () => context.go('/admin/requests')),
                ]);
          },
        ),
      );
}

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});
  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  String filter = 'Todos';
  String search = '';
  late Future<List<Map<String, dynamic>>> _users;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final role = filter == 'Socios'
        ? 'client'
        : filter == 'Entrenadores'
            ? 'trainer'
            : null;
    final status = filter == 'Baja' ? 'deactivated' : null;
    _users =
        authController.adminUsers(search: search, role: role, status: status);
  }

  @override
  Widget build(BuildContext context) => WorkspacePage(
      title: 'Usuarios',
      items: _adminNav,
      selected: 1,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _SearchField(
            hint: 'Buscar por nombre o número de socio',
            onChanged: (v) => setState(() {
                  search = v;
                  _reload();
                })),
        Wrap(
            spacing: 6,
            children: ['Todos', 'Socios', 'Entrenadores', 'Baja']
                .map((v) => ChoiceChip(
                    label: Text(v),
                    selected: filter == v,
                    onSelected: (_) => setState(() {
                          filter = v;
                          _reload();
                        })))
                .toList()),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _users,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()));
            }
            if (snapshot.hasError) {
              return Text(
                  'No se pudieron cargar los usuarios: ${snapshot.error}',
                  style: const TextStyle(color: AppColors.red));
            }
            final rows = snapshot.data ?? [];
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _section('${rows.length} usuarios'),
                  if (rows.isEmpty)
                    const Text('No hay usuarios que coincidan.'),
                  for (final user in rows)
                    _record(
                      '${user['first_name']} ${user['last_name']}',
                      '${user['role'] == 'client' ? 'Socio' : user['role'] == 'trainer' ? 'Entrenador' : 'Admin'} · ${user['status'] == 'deactivated' ? 'Baja' : user['status'] == 'pending' ? 'En revisión' : user['status'] == 'rejected' ? 'Rechazado' : 'Activo'}${user['member_number'] == null ? '' : ' · ${user['member_number']}'}',
                      icon: Icons.person_outline,
                      onTap: () async {
                        final changed = await context.push<bool>(
                            Uri(path: '/admin/member', queryParameters: {
                          'id': user['id'].toString(),
                          'member': (user['member_number'] ?? '').toString(),
                          'name': '${user['first_name']} ${user['last_name']}',
                          'email': (user['email'] ?? '').toString(),
                          'phone': (user['phone'] ?? '').toString(),
                          'plan': (user['membership_plan'] ?? '').toString(),
                          'status': user['status'].toString(),
                          'role': user['role'].toString(),
                          'deactivated_by':
                              (user['deactivated_by'] ?? '').toString(),
                          'reactivation_until':
                              user['reactivation_until']?.toString() ?? '',
                        }).toString());
                        if (changed == true && mounted) setState(_reload);
                      },
                    ),
                ]);
          },
        ),
      ]));
}

class AdminRoutinesScreen extends StatefulWidget {
  const AdminRoutinesScreen({super.key});
  @override
  State<AdminRoutinesScreen> createState() => _AdminRoutinesScreenState();
}

class _AdminRoutinesScreenState extends State<AdminRoutinesScreen> {
  String filter = 'Todas';
  String search = '';
  late Future<List<Map<String, dynamic>>> _routines;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _routines = authController.adminRoutines(
      search: search, goal: filter == 'Todas' ? null : filter);

  @override
  Widget build(BuildContext context) => WorkspacePage(
      title: 'Rutinas',
      items: _adminNav,
      selected: 2,
      child: Column(children: [
        _SearchField(
            hint: 'Buscar rutina',
            onChanged: (v) => setState(() {
                  search = v;
                  _reload();
                })),
        Wrap(
            spacing: 6,
            children: [
              'Todas',
              'Bajar de peso',
              'Masa muscular',
              'Resistencia',
              'Fuerza'
            ]
                .map((v) => FilterChip(
                    label: Text(v),
                    selected: filter == v,
                    onSelected: (_) => setState(() {
                          filter = v;
                          _reload();
                        })))
                .toList()),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _routines,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()));
            }
            if (snapshot.hasError) {
              return Text(
                  'No se pudieron cargar las rutinas: ${snapshot.error}',
                  style: const TextStyle(color: AppColors.red));
            }
            final rows = snapshot.data ?? [];
            return Column(children: [
              if (rows.isEmpty) const Text('No hay rutinas registradas.'),
              for (final routine in rows)
                _record(routine['name'].toString(),
                    '${routine['goal']} · ${routine['assigned_clients']} socios · ${routine['trainer_name']}',
                    onTap: () => context
                            .push(Uri(path: '/admin/routine', queryParameters: {
                          'id': routine['id'].toString(),
                          'name': routine['name'].toString(),
                        }).toString())),
            ]);
          },
        ),
      ]));
}

class AdminRoutineDetailScreen extends StatefulWidget {
  const AdminRoutineDetailScreen(
      {super.key, this.name = 'Rutina', required this.routineId});
  final String name;
  final String routineId;
  @override
  State<AdminRoutineDetailScreen> createState() =>
      _AdminRoutineDetailScreenState();
}

class _AdminRoutineDetailScreenState extends State<AdminRoutineDetailScreen> {
  late Future<Map<String, dynamic>> _routine;

  @override
  void initState() {
    super.initState();
    _routine = authController.adminRoutine(routineId: widget.routineId);
  }

  @override
  Widget build(BuildContext context) => WorkspacePage(
      title: 'Detalle de rutina',
      items: _adminNav,
      selected: 2,
      child: FutureBuilder<Map<String, dynamic>>(
        future: _routine,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Text('No se pudo cargar la rutina: ${snapshot.error}',
                style: const TextStyle(color: AppColors.red));
          }
          final data = snapshot.data ?? {};
          final phases = (data['phases'] as List? ?? [])
              .map((phase) => Map<String, dynamic>.from(phase as Map));
          final clients = (data['clients'] as List? ?? [])
              .map((client) => Map<String, dynamic>.from(client as Map));
          final exercises = (data['exercises'] as List? ?? [])
              .map((exercise) => Map<String, dynamic>.from(exercise as Map));
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MusklCard(
                    selected: true,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              (data['name'] ?? widget.name)
                                  .toString()
                                  .toUpperCase(),
                              style: const TextStyle(
                                  fontSize: 24, fontWeight: FontWeight.w900)),
                          Text(
                              '${data['goal']} · ${data['days_per_week']} días por semana'),
                          const SizedBox(height: 8),
                          Text(
                              'Responsable: ${data['trainer_name']} · ${clients.length} socios asignados',
                              style:
                                  const TextStyle(color: AppColors.textMuted))
                        ])),
                _section('Fases'),
                for (final phase in phases)
                  _record('${phase['name']} · Fase ${phase['phase_number']}',
                      '${phase['status'] == 'published' ? 'Publicada' : 'Borrador'} · ${phase['duration_weeks']} semanas · ${phase['exercise_count']} ejercicios',
                      icon: phase['status'] == 'published'
                          ? Icons.check_circle_outline
                          : Icons.edit_outlined),
                _section('Ejercicios'),
                for (final exercise in exercises)
                  _record(exercise['name'].toString(),
                      'Fase ${exercise['phase_number']} · Día ${exercise['day_number']} · ${exercise['sets']} series · ${exercise['reps']} repeticiones · ${exercise['rest_seconds']} s'),
                _section('Clientes asignados'),
                for (final client in clients)
                  _record('${client['first_name']} ${client['last_name']}',
                      'Socio ${client['member_number']}'),
                if (clients.isEmpty) const Text('Sin clientes asignados.'),
              ]);
        },
      ));
}

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});
  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  List<Map<String, dynamic>> _plans = [];
  List<Map<String, dynamic>> _invites = [];
  List<Map<String, dynamic>> _admins = [];
  bool _newRequestNotifications = true;
  bool _savingPreferences = false;

  @override
  void initState() {
    super.initState();
    _loadGym();
    _loadAdminOptions();
    _loadAdminPreferences();
  }

  Future<void> _loadAdminPreferences() async {
    try {
      final preferences = await authController.adminPreferences();
      if (!mounted) return;
      setState(
          () => _newRequestNotifications = preferences['new_requests'] == true);
    } catch (e) {
      if (mounted) _showLocalMessage('No se cargaron las preferencias: $e');
    }
  }

  Future<void> _setNewRequestNotifications(bool enabled) async {
    if (_savingPreferences) return;
    setState(() => _savingPreferences = true);
    try {
      final saved =
          await authController.updateAdminPreferences(newRequests: enabled);
      if (!mounted) return;
      setState(() => _newRequestNotifications = saved['new_requests'] == true);
    } catch (e) {
      if (mounted) _showLocalMessage('No se guardó la preferencia: $e');
    } finally {
      if (mounted) setState(() => _savingPreferences = false);
    }
  }

  Future<void> _loadAdminOptions() async {
    try {
      final results = await Future.wait<List<Map<String, dynamic>>>([
        authController.adminPlans(),
        authController.adminInvites(),
        authController.adminUsers(role: 'admin', status: 'active'),
      ]);
      if (!mounted) return;
      setState(() {
        _plans = results[0];
        _invites = results[1];
        _admins = results[2];
      });
    } catch (e) {
      if (mounted)
        _showLocalMessage('No se pudieron cargar planes e invitaciones: $e');
    }
  }

  Future<void> _loadGym() async {
    try {
      final gym = await authController.adminGym();
      final hours =
          Map<String, dynamic>.from(gym['opening_hours'] as Map? ?? {});
      if (!mounted) return;
      setState(() {
        _PrototypeSettings.gymName = (gym['name'] ?? '').toString();
        _PrototypeSettings.gymAddress = (gym['address'] ?? '').toString();
        _PrototypeSettings.gymPhone = (gym['phone'] ?? '').toString();
        _PrototypeSettings.hours = (hours['display'] ?? '').toString();
      });
    } catch (e) {
      if (mounted)
        _showLocalMessage('No se pudieron cargar los datos del gimnasio: $e');
    }
  }

  Future<void> _editGym() async {
    final values = await _editFields(context, 'DATOS DEL GIMNASIO', [
      'Nombre del gimnasio',
      'Dirección',
      'Teléfono'
    ], [
      _PrototypeSettings.gymName,
      _PrototypeSettings.gymAddress,
      _PrototypeSettings.gymPhone
    ]);
    if (values == null) return;
    try {
      final saved = await authController.updateAdminGym(
          name: values[0],
          address: values[1],
          phone: values[2],
          openingHours: _PrototypeSettings.hours);
      if (!mounted) return;
      setState(() {
        _PrototypeSettings.gymName = saved['name'].toString();
        _PrototypeSettings.gymAddress = saved['address'].toString();
        _PrototypeSettings.gymPhone = saved['phone'].toString();
      });
    } catch (e) {
      _showLocalMessage('No se pudieron guardar los datos: $e');
    }
  }

  Future<void> _editHours() async {
    final values = await _editFields(context, 'HORARIOS DE APERTURA',
        ['Un día por línea'], [_PrototypeSettings.hours],
        multiline: const {0});
    if (values != null) {
      try {
        await authController.updateAdminGym(
            name: _PrototypeSettings.gymName,
            address: _PrototypeSettings.gymAddress,
            phone: _PrototypeSettings.gymPhone,
            openingHours: values[0]);
        if (mounted) setState(() => _PrototypeSettings.hours = values[0]);
      } catch (e) {
        _showLocalMessage('No se pudieron guardar los horarios: $e');
      }
    }
  }

  Future<void> _editPlans() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('PLANES DE MEMBRESÍA',
                style: TextStyle(fontWeight: FontWeight.w900)),
            for (final plan in _plans)
              ListTile(
                title: Text(plan['name'].toString()),
                subtitle: Text(
                    '\$${plan['price_mxn']} MXN · ${plan['duration_days']} días · ${plan['active'] == true ? 'Activo' : 'Inactivo'}'),
                trailing: IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () async {
                      Navigator.pop(sheetContext);
                      await _editPlan(plan);
                      if (mounted) await _loadAdminOptions();
                    }),
              ),
            ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Agregar plan'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await _editPlan(null);
                  if (mounted) await _loadAdminOptions();
                }),
          ]),
        ),
      ),
    );
  }

  Future<void> _editPlan(Map<String, dynamic>? plan) async {
    final values = await _editFields(
        context, plan == null ? 'NUEVO PLAN' : 'EDITAR PLAN', [
      'Nombre',
      'Precio en MXN',
      'Duración en días'
    ], [
      plan?['name']?.toString() ?? '',
      plan?['price_mxn']?.toString() ?? '',
      plan?['duration_days']?.toString() ?? '30'
    ]);
    if (values == null) return;
    final price = double.tryParse(values[1]);
    final duration = int.tryParse(values[2]);
    if (values[0].trim().isEmpty ||
        price == null ||
        price < 0 ||
        duration == null ||
        duration < 1) {
      _showLocalMessage('Revisa nombre, precio y duración del plan.');
      return;
    }
    try {
      await authController.saveAdminPlan(
          id: plan?['id']?.toString(),
          name: values[0].trim(),
          priceMxn: price,
          durationDays: duration,
          active: plan?['active'] != false);
      await _loadAdminOptions();
    } catch (e) {
      _showLocalMessage('No se pudo guardar el plan: $e');
    }
  }

  Future<void> _manageCodes() async {
    await showModalBottomSheet<void>(
        context: context,
        builder: (sheetContext) => SafeArea(
                child: ListView(
              shrinkWrap: true,
              children: [
                const ListTile(title: Text('INVITACIONES ADMIN')),
                ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('Crear token de invitación'),
                    onTap: () async {
                      try {
                        final created =
                            await authController.createAdminInvite();
                        if (!sheetContext.mounted) return;
                        Navigator.pop(sheetContext);
                        if (!mounted) return;
                        await showDialog<void>(
                            context: context,
                            builder: (dialogContext) => AlertDialog(
                                  title: const Text('TOKEN DE ADMIN CREADO'),
                                  content: SelectableText(
                                      '${created['token']}\n\nCópialo ahora. El servidor no guarda el token en texto visible.'),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(dialogContext),
                                        child: const Text('Entendido'))
                                  ],
                                ));
                        await _loadAdminOptions();
                      } catch (e) {
                        if (mounted)
                          _showLocalMessage('No se pudo crear el token: $e');
                      }
                    }),
                for (final invite in _invites)
                  ListTile(
                    title: Text(invite['revoked_at'] != null
                        ? 'Revocada'
                        : invite['used_at'] != null
                            ? 'Usada'
                            : 'Activa'),
                    subtitle: Text(
                        'Vence: ${invite['expires_at'] ?? 'Sin vencimiento'}'),
                    trailing: invite['revoked_at'] == null &&
                            invite['used_at'] == null
                        ? IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              await authController.revokeAdminInvite(
                                  inviteId: invite['id'].toString());
                              if (!sheetContext.mounted) return;
                              Navigator.pop(sheetContext);
                              if (mounted) await _loadAdminOptions();
                            })
                        : null,
                  ),
              ],
            )));
  }

  void _showLocalMessage(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => WorkspacePage(
      title: 'Ajustes admin',
      items: _adminNav,
      selected: 3,
      child: Column(children: [
        _SwitchSetting(
            label: 'Notificaciones de nuevas solicitudes',
            value: _newRequestNotifications,
            enabled: !_savingPreferences,
            onChanged: _setNewRequestNotifications),
        _setting(
            _PrototypeSettings.gymName,
            '${_PrototypeSettings.gymAddress} · ${_PrototypeSettings.gymPhone}',
            Icons.business_outlined,
            onTap: _editGym),
        _setting('Horarios de apertura',
            _PrototypeSettings.hours.replaceAll('\n', ' · '), Icons.schedule,
            onTap: _editHours),
        _setting('Planes de membresía',
            _plans.map((p) => p['name']).join(' · '), Icons.card_membership,
            onTap: _editPlans),
        _setting(
            'Administradores',
            '${_admins.length} cuenta(s) · ${_admins.map((u) => '${u['first_name']} ${u['last_name']}').join(', ')}',
            Icons.admin_panel_settings_outlined),
        _setting(
            'Códigos de invitación',
            '${_invites.where((i) => i['revoked_at'] == null && i['used_at'] == null).length} código(s) activo(s)',
            Icons.key_outlined,
            onTap: _manageCodes),
        _setting('Cambiar contraseña', 'Actualiza tus credenciales',
            Icons.lock_outline,
            onTap: () => _changeAccountPassword(context)),
        const SizedBox(height: 12),
        MusklButton(
            label: 'Cerrar sesión',
            style: MusklButtonStyle.secondary,
            onPressed: authController.signOut),
      ]));
}

class AdminRequestsScreen extends StatefulWidget {
  const AdminRequestsScreen({super.key});
  @override
  State<AdminRequestsScreen> createState() => _AdminRequestsScreenState();
}

class _AdminRequestsScreenState extends State<AdminRequestsScreen> {
  late Future<List<Map<String, dynamic>>> _requests;
  late Future<List<Map<String, dynamic>>> _deletionRequests;
  late Future<List<Map<String, dynamic>>> _notifications;
  bool _showDeletions = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _requests = authController.staffRequests();
    _deletionRequests = authController.accountDeletionRequests();
    _notifications = authController.adminNotifications();
  }

  Future<void> _markAdminNotificationRead(String notificationId) async {
    try {
      await authController.markAdminNotificationRead(
          notificationId: notificationId);
      if (mounted) setState(_reload);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo actualizar el aviso: $e')));
      }
    }
  }

  Future<void> _review(Map<String, dynamic> request, bool approved) async {
    try {
      await authController.reviewStaffRequest(
          userId: request['id'].toString(),
          approved: approved,
          reason: approved ? null : 'Solicitud rechazada por el gimnasio.');
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(approved ? 'Solicitud aprobada.' : 'Solicitud rechazada.')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No se pudo revisar: $e')));
      }
    }
  }

  Future<void> _reviewDeletion(
      Map<String, dynamic> request, bool approved) async {
    try {
      await authController.reviewAccountDeletionRequest(
          requestId: request['id'].toString(),
          approved: approved,
          note: approved
              ? 'Aprobada por el administrador.'
              : 'Rechazada por el administrador.');
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(approved
              ? 'Baja aprobada. La cuenta quedó desactivada por 90 días.'
              : 'Solicitud de baja rechazada.')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo revisar la baja: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => WorkspacePage(
      title: 'Solicitudes',
      items: _adminNav,
      selected: 0,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FutureBuilder<List<Map<String, dynamic>>>(
            future: _notifications,
            builder: (context, snapshot) {
              final notifications = snapshot.data ?? [];
              if (notifications.isEmpty) return const SizedBox.shrink();
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _section('Avisos nuevos'),
                    for (final notification in notifications)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: MusklCard(
                              child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                      Icons.notifications_active,
                                      color: AppColors.yellow),
                                  title: Text(notification['title'].toString()),
                                  subtitle:
                                      Text(notification['body'].toString()),
                                  trailing: IconButton(
                                      tooltip: 'Marcar como leído',
                                      onPressed: () =>
                                          _markAdminNotificationRead(
                                              notification['id'].toString()),
                                      icon: const Icon(Icons.done))))),
                  ]);
            }),
        Wrap(spacing: 8, children: [
          ChoiceChip(
              label: const Text('PERSONAL'),
              selected: !_showDeletions,
              onSelected: (_) => setState(() => _showDeletions = false)),
          ChoiceChip(
              label: const Text('BAJAS DE CLIENTES'),
              selected: _showDeletions,
              onSelected: (_) => setState(() => _showDeletions = true)),
        ]),
        const SizedBox(height: 16),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _showDeletions ? _deletionRequests : _requests,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Text(
                  'No se pudieron cargar las solicitudes: ${snapshot.error}',
                  style: const TextStyle(color: AppColors.red));
            }
            final requests = snapshot.data ?? [];
            if (requests.isEmpty)
              return Text(_showDeletions
                  ? 'No hay solicitudes de baja pendientes.'
                  : 'No hay solicitudes pendientes.');
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final request in requests)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: MusklCard(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(
                                '${request['first_name']} ${request['last_name']}'
                                    .toUpperCase(),
                                style: const TextStyle(
                                    fontSize: 19, fontWeight: FontWeight.bold)),
                            Text(_showDeletions
                                ? 'CLIENTE · ${request['email']} · Socio ${request['member_number'] ?? '—'}'
                                : '${request['role'] == 'trainer' ? 'Entrenador' : 'Administrador'} · ${request['email']}'),
                            if (_showDeletions &&
                                request['requested_at'] != null)
                              Text('Solicitada: ${request['requested_at']}',
                                  style: const TextStyle(
                                      color: AppColors.textMuted)),
                            if (_showDeletions &&
                                request['note'] != null &&
                                request['note'].toString().isNotEmpty)
                              Text('Motivo: ${request['note']}'),
                            if (!_showDeletions && request['specialty'] != null)
                              Text('Especialidad: ${request['specialty']}',
                                  style: const TextStyle(
                                      color: AppColors.textMuted)),
                            const SizedBox(height: 12),
                            Row(children: [
                              Expanded(
                                  child: MusklButton(
                                      label: 'Rechazar',
                                      style: MusklButtonStyle.secondary,
                                      onPressed: () => _showDeletions
                                          ? _reviewDeletion(request, false)
                                          : _review(request, false))),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: MusklButton(
                                      label: 'Aprobar',
                                      style: MusklButtonStyle.primary,
                                      onPressed: () => _showDeletions
                                          ? _reviewDeletion(request, true)
                                          : _review(request, true))),
                            ]),
                          ])),
                    ),
                ]);
          },
        )
      ]));
}

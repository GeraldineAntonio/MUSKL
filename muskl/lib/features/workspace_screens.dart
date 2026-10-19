import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfrx/pdfrx.dart';

import '../core/theme/app_colors.dart';
import '../core/widgets/muskl_bottom_nav.dart';
import '../core/widgets/muskl_button.dart';
import '../core/widgets/muskl_card.dart';
import '../core/widgets/muskl_text_field.dart';
import '../core/widgets/password_strength.dart';
import '../core/widgets/profile_photo_avatar.dart';
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
                        onPressed: () => context.push('/login')),
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

class _CalendarLegend extends StatelessWidget {
  const _CalendarLegend(
      {required this.color, required this.label, required this.filled});

  final Color color;
  final String label;
  final bool filled;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? color : Colors.transparent,
              border: filled ? null : Border.all(color: color),
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: AppColors.textMuted)),
        ],
      );
}

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
        bool editable = false,
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
                      color: AppColors.accent, fontWeight: FontWeight.bold)),
            const SizedBox(width: 4),
            Icon(editable ? Icons.edit_outlined : Icons.chevron_right,
                color: AppColors.textMuted),
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
        final photoData = data['profile_photo_data'];
        final photoBytes = photoData is String && photoData.isNotEmpty
            ? base64Decode(photoData)
            : null;
        final photoUrl = data['profile_photo_url']?.toString();
        final dates =
            Set<String>.from(data['attendance_7d_dates'] as List? ?? []);
        final now = DateTime.tryParse(data['today']?.toString() ?? '') ??
            DateTime.now();
        final hours = data['gym_opening_hours'];
        final hoursText = hours is Map
            ? (hours['display']?.toString() ??
                _formatGymHours(Map<String, dynamic>.from(hours)))
            : '';
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
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    ProfilePhotoAvatar(
                      radius: 27,
                      image: photoUrl != null && photoUrl.isNotEmpty
                          ? NetworkImage(photoUrl)
                          : photoBytes == null
                              ? null
                              : MemoryImage(photoBytes),
                      name: '${data['first_name']} ${data['last_name']}',
                      onEdit: () => context.go('/home/profile'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('SOCIO Nº',
                                style: TextStyle(
                                    fontSize: 11, color: AppColors.textMuted)),
                            Text('${data['member_number'] ?? '—'}',
                                style: const TextStyle(
                                    fontSize: 25,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.red)),
                            Text(
                                '${data['gym_name'] ?? 'Gimnasio'} · ${data['trainer_name'] ?? 'Sin entrenador'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.textMuted)),
                          ]),
                    ),
                    IconButton(
                      tooltip: 'Mi perfil',
                      onPressed: () => context.go('/home/profile'),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ])),
              if ((data['trainer_name'] ?? '').toString().isEmpty) ...[
                _section('Tu entrenador'),
                if (data['pending_trainer_id'] != null)
                  MusklCard(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(
                            'Tu solicitud está pendiente con ${data['pending_trainer_name'] ?? 'el entrenador'}. Cuando la acepte, podrá asignarte una rutina.'),
                        TextButton(
                            onPressed: () => context.push('/home/trainers'),
                            child: const Text('Cambiar solicitud')),
                      ]))
                else
                  MusklButton(
                      label: 'Elegir entrenador',
                      icon: Icons.fitness_center,
                      onPressed: () => context.push('/home/trainers')),
              ],
              if (((data['gym_address'] ?? '').toString().isNotEmpty ||
                  (data['gym_phone'] ?? '').toString().isNotEmpty ||
                  hoursText.isNotEmpty))
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 8),
                  child: Text(
                    [
                      data['gym_address'],
                      data['gym_phone'],
                      if (hoursText.isNotEmpty)
                        hoursText.replaceAll('\n', ' · ')
                    ]
                        .where((value) =>
                            value != null && value.toString().isNotEmpty)
                        .join('  ·  '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textMuted),
                  ),
                ),
              _section('Tu actividad'),
              Row(children: [
                _metric('${data['workouts_7d'] ?? 0}', 'Sesiones · 7 días',
                    color: AppColors.bgDeep, background: AppColors.accent),
                const SizedBox(width: 8),
                _metric(
                    '${data['attendance_total'] ?? 0}', 'Visitas al gimnasio')
              ]),
              const Padding(
                padding: EdgeInsets.only(top: 6, left: 8),
                child: Text(
                    'Las asistencias cuentan las visitas registradas al gimnasio.',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ),
              const SizedBox(height: 8),
              Row(children: [
                _metric('${data['app_login_streak'] ?? 0}', 'Racha de accesos'),
                const SizedBox(width: 8),
                _metric('${data['gym_attendance_streak'] ?? 0}',
                    'Racha de visitas'),
                const SizedBox(width: 8),
                _metric('${data['routine_completion_streak'] ?? 0}',
                    'Rutinas completas'),
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

class ClientTrainerSelectionScreen extends StatefulWidget {
  const ClientTrainerSelectionScreen({super.key});

  @override
  State<ClientTrainerSelectionScreen> createState() =>
      _ClientTrainerSelectionScreenState();
}

class _ClientTrainerSelectionScreenState
    extends State<ClientTrainerSelectionScreen> {
  late Future<Map<String, dynamic>> _data;
  String? _sendingId;

  @override
  void initState() {
    super.initState();
    _data = authController.clientTrainers();
  }

  Future<void> _request(String trainerId) async {
    setState(() => _sendingId = trainerId);
    try {
      await authController.requestClientTrainer(trainerId: trainerId);
      if (!mounted) return;
      setState(() => _data = authController.clientTrainers());
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Solicitud enviada. Espera a que el entrenador la acepte.')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo enviar la solicitud: $error')));
      }
    } finally {
      if (mounted) setState(() => _sendingId = null);
    }
  }

  @override
  Widget build(BuildContext context) => WorkspacePage(
        title: 'Elegir entrenador',
        kicker: 'SOCIO',
        items: _clientNav,
        selected: 3,
        child: FutureBuilder<Map<String, dynamic>>(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Text(
                  'No se pudieron cargar los entrenadores: ${snapshot.error}');
            }
            final data = snapshot.data ?? {};
            final assignedId = data['assigned_trainer_id']?.toString();
            final pending = data['pending_request'] as Map?;
            final pendingId = pending?['trainer_id']?.toString();
            final trainers = (data['trainers'] as List? ?? [])
                .map((row) => Map<String, dynamic>.from(row as Map))
                .toList();
            if (assignedId != null) {
              return MusklCard(
                  child: Text(
                      'Ya tienes entrenador asignado: ${data['assigned_trainer_name'] ?? ''}. Tu entrenador podrá asignarte una rutina.'));
            }
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                      'Elige a quién quieres solicitar. La asignación se confirma cuando el entrenador acepte.'),
                  if (pendingId != null) ...[
                    const SizedBox(height: 12),
                    MusklCard(
                        child: Text(
                            'Solicitud pendiente para ${pending?['trainer_name'] ?? 'el entrenador seleccionado'}. Puedes elegir otro entrenador si lo prefieres.')),
                  ],
                  const SizedBox(height: 12),
                  if (trainers.isEmpty)
                    const MusklCard(
                        child: Text(
                            'Todavía no hay entrenadores disponibles. Puedes volver a intentarlo después.')),
                  for (final trainer in trainers)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: MusklCard(
                        child: Row(children: [
                          const Icon(Icons.fitness_center,
                              color: AppColors.red),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(
                                    '${trainer['first_name']} ${trainer['last_name']}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                if ((trainer['specialty'] ?? '')
                                    .toString()
                                    .isNotEmpty)
                                  Text(trainer['specialty'].toString(),
                                      style: const TextStyle(
                                          color: AppColors.textMuted)),
                              ])),
                          FilledButton(
                            onPressed: _sendingId != null
                                ? null
                                : () => _request(trainer['id'].toString()),
                            child: Text(_sendingId == trainer['id'].toString()
                                ? 'Enviando…'
                                : pendingId == trainer['id'].toString()
                                    ? 'Elegido'
                                    : 'Solicitar'),
                          ),
                        ]),
                      ),
                    ),
                ]);
          },
        ),
      );
}

class ClientRoutineScreen extends StatefulWidget {
  const ClientRoutineScreen({super.key});
  @override
  State<ClientRoutineScreen> createState() => _ClientRoutineScreenState();
}

class _ClientRoutineScreenState extends State<ClientRoutineScreen>
    with WidgetsBindingObserver {
  late int _day;
  late Future<Map<String, dynamic>> _routine;
  final Stopwatch _workoutClock = Stopwatch();
  final AudioPlayer _applausePlayer = AudioPlayer();
  final FlutterTts _speech = FlutterTts();
  final Set<String> _completedExerciseIds = {};
  Timer? _ticker;
  int _nextEncouragementSeconds = 20 * 60;
  int _encouragementIndex = 0;
  bool _isForeground = true;
  bool _workoutFinished = false;
  bool _saving = false;

  static const _encouragements = [
    '¡Bien hecho! Mantén ese ritmo, vas muy bien.',
    'Cada repetición cuenta. ¡Sigue así!',
    '¡Buen trabajo! Estás más cerca de tu meta.',
    'Tu esfuerzo se nota. ¡Tú puedes!',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _day = DateTime.now().weekday;
    _workoutClock.start();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _configureSpeech();
    _load();
  }

  Future<void> _configureSpeech() async {
    try {
      await _speech.setLanguage('es-MX');
      await _speech.setSpeechRate(0.48);
      await _speech.setVolume(0.9);
      await _applausePlayer.setReleaseMode(ReleaseMode.stop);
    } catch (_) {
      // The visual encouragement still works if device speech is unavailable.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
    if (_isForeground && !_workoutFinished) {
      _workoutClock.start();
      if (mounted) setState(_load);
    } else {
      _workoutClock.stop();
      _stopEncouragementAudio();
    }
  }

  void _tick() {
    if (!_isForeground || _workoutFinished) return;
    final elapsed = _workoutClock.elapsed.inSeconds;
    if (elapsed >= _nextEncouragementSeconds) {
      _nextEncouragementSeconds += 20 * 60;
      _showEncouragement();
    }
  }

  void _showEncouragement() {
    final message =
        _encouragements[_encouragementIndex % _encouragements.length];
    _encouragementIndex++;
    HapticFeedback.mediumImpact();
    _playEncouragement(message);
  }

  Future<void> _playEncouragement(String message) async {
    try {
      await _applausePlayer.play(AssetSource('audio/applause.wav'),
          volume: 0.55);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (_isForeground) await _speech.speak(message);
    } catch (_) {
      // Audio is optional; never interrupt the exercise flow.
    }
  }

  Future<void> _stopEncouragementAudio() async {
    try {
      await _speech.stop();
      await _applausePlayer.stop();
    } catch (_) {}
  }

  void _load() => _routine = authController.clientRoutine(day: _day);

  Future<void> _complete() async {
    if (!mounted) return;
    final data = await _routine;
    final total = (data['exercises'] as List? ?? []).length;
    final done = ((data['completed_exercise_ids'] as List? ?? [])
            .map((id) => id.toString())
            .toSet()
          ..addAll(_completedExerciseIds))
        .length;
    if (done < total) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('¿Finalizar esta sesión?'),
          content: Text(
              'Llevas $done de $total ejercicios. La sesión se cerrará y se registrará tu visita de hoy al gimnasio.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Seguir entrenando')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Finalizar')),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() => _saving = true);
    try {
      final durationSeconds =
          _workoutClock.elapsed.inSeconds.clamp(1, 86400).toInt();
      final completion = await authController.completeClientWorkout(
          durationSeconds: durationSeconds);
      _workoutFinished = true;
      _workoutClock.stop();
      await _stopEncouragementAudio();
      if (mounted) {
        context.push(Uri(path: '/home/complete', queryParameters: {
          'exercise_count': completion['exercise_count'].toString(),
          'sessions_this_week':
              completion['sessions_this_week']?.toString() ?? '1',
          'sessions_total': completion['sessions_total']?.toString() ?? '1',
          'fully_completed':
              completion['fully_completed'] == true ? 'true' : 'false',
          'scheduled_exercise_count':
              completion['scheduled_exercise_count']?.toString() ?? '0',
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
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _stopEncouragementAudio();
    _applausePlayer.dispose();
    _speech.stop();
    super.dispose();
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
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => setState(_load),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Actualizar rutina'),
          ),
        ),
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
              return const Column(children: [
                MusklCard(
                    child: Text(
                        'Tu entrenador o el administrador todavía no te han asignado una rutina. Cuando la asignen, aparecerá aquí.')),
              ]);
            final exercises = (data['exercises'] as List? ?? [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
            final completedIds = <String>{
              ...((data['completed_exercise_ids'] as List? ?? [])
                  .map((id) => id.toString())),
              ..._completedExerciseIds,
            };
            final completedCount = exercises
                .where((exercise) =>
                    completedIds.contains(exercise['id'].toString()))
                .length;
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MusklCard(
                      child: Row(children: [
                    const Icon(Icons.local_fire_department,
                        color: AppColors.accent),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(
                            '${data['routine_name']} · ${data['phase_name']} · ${data['goal']}')),
                  ])),
                  if (data['scheduled_for_date'] != null &&
                      data['today'] != data['scheduled_for_date'])
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                          'Esta sesión quedó pendiente desde ${data['scheduled_for_date']} y pasó a hoy.',
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 12)),
                    ),
                  _section('Ejercicios del día · ${exercises.length}'),
                  if (exercises.isNotEmpty) ...[
                    Text('Finalizados: $completedCount de ${exercises.length}'),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: completedCount / exercises.length,
                      color: AppColors.accent,
                      backgroundColor: AppColors.surfaceHigh,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    const SizedBox(height: 12),
                  ],
                  ...exercises.asMap().entries.map((entry) {
                    final exercise = entry.value;
                    final exerciseId = exercise['id'].toString();
                    final isCompleted = completedIds.contains(exerciseId);
                    final isScheduledToday = data['scheduled_for_date'] !=
                            null &&
                        exercise['day_number'] == data['scheduled_day_number'];
                    return _record(
                      exercise['name'].toString(),
                      '${exercise['sets']} series · ${exercise['reps']} repeticiones · ${exercise['rest_seconds']} s descanso',
                      badge:
                          isCompleted ? '✓' : '${exercise['position'] ?? ''}',
                      icon: isCompleted
                          ? Icons.check_circle
                          : Icons.fitness_center,
                      onTap: () async {
                        final finished = await context.push<bool>(
                            Uri(path: '/home/exercise', queryParameters: {
                          'id': exerciseId,
                          'name': exercise['name'].toString(),
                          'media_url': exercise['media_url']?.toString() ?? '',
                          'muscle_group':
                              exercise['muscle_group']?.toString() ?? 'Rutina',
                          'instructions':
                              exercise['instructions']?.toString() ?? '',
                          'sets': exercise['sets'].toString(),
                          'reps': exercise['reps'].toString(),
                          'rest_seconds': exercise['rest_seconds'].toString(),
                          'can_complete': (isScheduledToday &&
                                  data['completed_today'] != true)
                              .toString(),
                          'already_completed': isCompleted.toString(),
                        }).toString());
                        if (finished == true && mounted) {
                          setState(() => _completedExerciseIds.add(exerciseId));
                        }
                      },
                    );
                  }),
                  if (exercises.isEmpty)
                    const Text('No hay ejercicios programados para este día.'),
                  MusklButton(
                      label: data['completed_today'] == true
                          ? 'Rutina completada'
                          : 'Finalizar rutina ($completedCount/${exercises.length})',
                      icon: Icons.check,
                      loading: _saving,
                      onPressed: exercises.isEmpty ||
                              data['completed_today'] == true ||
                              data['scheduled_for_date'] == null
                          ? null
                          : _complete),
                ]);
          },
        ),
      ]));
}

class ExerciseDetailScreen extends StatefulWidget {
  const ExerciseDetailScreen({
    super.key,
    this.id = '1',
    this.name = 'Sprint en cinta',
    this.mediaUrl = '',
    this.muscleGroup = 'Cardio',
    this.instructions = '',
    this.sets = '4',
    this.reps = '30 s',
    this.restSeconds = '60',
    this.canMarkComplete = false,
    this.alreadyCompleted = false,
  });
  final String id;
  final String name;
  final String mediaUrl;
  final String muscleGroup;
  final String instructions;
  final String sets;
  final String reps;
  final String restSeconds;
  final bool canMarkComplete;
  final bool alreadyCompleted;

  @override
  State<ExerciseDetailScreen> createState() => _ExerciseDetailScreenState();
}

class _ExerciseDetailScreenState extends State<ExerciseDetailScreen> {
  bool _saving = false;

  Future<void> _finishExercise() async {
    if (!widget.canMarkComplete || widget.alreadyCompleted || _saving) return;
    setState(() => _saving = true);
    try {
      await authController.completeClientExercise(exerciseId: widget.id);
      if (mounted) context.pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo finalizar el ejercicio: $error'),
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => WorkspacePage(
      title: 'Detalle de ejercicio',
      items: _clientNav,
      selected: 1,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: double.infinity,
            height: 220,
            color: AppColors.surface,
            alignment: Alignment.center,
            child: widget.mediaUrl.isEmpty
                ? const Icon(Icons.fitness_center,
                    size: 70, color: AppColors.red)
                : Image.network(
                    widget.mediaUrl,
                    width: double.infinity,
                    height: 220,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image_outlined,
                        size: 64,
                        color: AppColors.textMuted),
                  ),
          ),
        ),
        _section('${widget.muscleGroup} · Ejercicio ${widget.id}'),
        Text(widget.name.toUpperCase(),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
        const SizedBox(height: 14),
        Row(children: [
          _metric(widget.sets, 'Series'),
          const SizedBox(width: 8),
          _metric(widget.reps, 'Repeticiones'),
          const SizedBox(width: 8),
          _metric('${widget.restSeconds} s', 'Descanso')
        ]),
        _section('Cómo se hace'),
        MusklCard(
            child: Text(widget.instructions.isEmpty
                ? 'Tu entrenador todavía no agregó instrucciones para este ejercicio.'
                : widget.instructions)),
        const SizedBox(height: 20),
        MusklButton(
            label: widget.alreadyCompleted
                ? 'Ejercicio finalizado'
                : widget.canMarkComplete
                    ? 'Marcar ejercicio finalizado'
                    : 'Disponible en su día programado',
            icon: Icons.check,
            loading: _saving,
            onPressed: widget.canMarkComplete && !widget.alreadyCompleted
                ? _finishExercise
                : null),
      ]));
}

class RoutineCompleteScreen extends StatelessWidget {
  const RoutineCompleteScreen(
      {super.key,
      required this.exerciseCount,
      required this.sessionsThisWeek,
      required this.sessionsTotal,
      this.fullyCompleted = true,
      this.scheduledExerciseCount = 0,
      this.durationSeconds,
      this.date});
  final int exerciseCount;
  final int sessionsThisWeek;
  final int sessionsTotal;
  final bool fullyCompleted;
  final int scheduledExerciseCount;
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
      title: fullyCompleted ? 'Rutina completada' : 'Sesión finalizada',
      items: _clientNav,
      selected: 1,
      child: Column(children: [
        const SizedBox(height: 20),
        const Icon(Icons.check_circle, size: 110, color: AppColors.red),
        const SizedBox(height: 14),
        Text(fullyCompleted ? '¡LO LOGRASTE!' : '¡SESIÓN REGISTRADA!',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 27,
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
          _metric('$sessionsThisWeek', 'Sesiones esta semana',
              color: AppColors.bgDeep, background: AppColors.accent)
        ]),
        const SizedBox(height: 16),
        MusklCard(
            selected: true,
            child: Text(
                fullyCompleted
                    ? 'Tu historial ya suma $sessionsTotal sesiones registradas. Tu racha de rutinas completas avanzó.'
                    : 'Se registró tu asistencia y completaste $exerciseCount de $scheduledExerciseCount ejercicios. La sesión quedó cerrada.',
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
  bool _checkingIn = false;

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

  Future<void> _checkIn() async {
    if (_checkingIn) return;
    setState(() => _checkingIn = true);
    try {
      final result = await authController.checkInClientAttendance();
      if (!mounted) return;
      setState(_load);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result['created'] == true
            ? 'Asistencia registrada para hoy.'
            : 'Tu asistencia de hoy ya estaba registrada.'),
      ));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo registrar la asistencia: $error'),
        ));
      }
    } finally {
      if (mounted) setState(() => _checkingIn = false);
    }
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
          final attendedDates = rows.map((e) => e['date'].toString()).toSet();
          final attended =
              attendedDates.map((date) => DateTime.parse(date).day).toSet();
          final routineDays = (data['routine_days'] as List? ?? [])
              .map((day) => (day as num).toInt())
              .toSet();
          final today = data['today']?.toString() ??
              DateTime.now().toIso8601String().substring(0, 10);
          final alreadyCheckedIn = attendedDates.contains(today);
          final offset = DateTime(_year, _month, 1).weekday - 1;
          final daysInMonth = DateTime(_year, _month + 1, 0).day;
          final cellCount = ((offset + daysInMonth + 6) ~/ 7) * 7;
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (data['can_check_in'] == true)
                  MusklButton(
                    label: _checkingIn
                        ? 'Registrando...'
                        : alreadyCheckedIn
                            ? 'Asistencia registrada hoy'
                            : 'Registrar asistencia de hoy',
                    icon: alreadyCheckedIn
                        ? Icons.check_circle_outline
                        : Icons.how_to_reg_outlined,
                    onPressed:
                        _checkingIn || alreadyCheckedIn ? null : _checkIn,
                  )
                else
                  const Text(
                    'Necesitas una membresía activa para registrar asistencia.',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                const SizedBox(height: 12),
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
                              final date = DateTime(_year, _month, day);
                              final hasAttendance = attended.contains(day);
                              final isRoutineDay =
                                  routineDays.contains(date.weekday);
                              return Container(
                                  width: 30,
                                  height: 32,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: hasAttendance
                                          ? AppColors.red
                                          : Colors.transparent,
                                      border: !hasAttendance && isRoutineDay
                                          ? Border.all(
                                              color: AppColors.accent,
                                              width: 1.5)
                                          : null),
                                  child: Text('$day',
                                      style: TextStyle(
                                          color: hasAttendance
                                              ? AppColors.white
                                              : isRoutineDay
                                                  ? AppColors.accent
                                                  : AppColors.textMuted,
                                          fontSize: 12)));
                            }))),
                  const SizedBox(height: 12),
                  const Wrap(
                    spacing: 14,
                    runSpacing: 8,
                    children: [
                      _CalendarLegend(
                          color: AppColors.red, label: 'Asistí', filled: true),
                      _CalendarLegend(
                          color: AppColors.accent,
                          label: 'Día de rutina',
                          filled: false),
                    ],
                  ),
                ])),
                _section('Resumen del mes'),
                Row(children: [
                  _metric('${data['total'] ?? rows.length}', 'Asistencias'),
                  const SizedBox(width: 8),
                  _metric('${attended.length}', 'Días asistidos'),
                ]),
                _section('Registro del mes'),
                if (rows.isEmpty)
                  const Text('Todavía no hay asistencias registradas este mes.',
                      style: TextStyle(color: AppColors.textMuted)),
                for (final entry in rows.reversed)
                  _record(
                    DateTime.parse(entry['date'].toString()).day.toString() +
                        ' de ${[
                          'enero',
                          'febrero',
                          'marzo',
                          'abril',
                          'mayo',
                          'junio',
                          'julio',
                          'agosto',
                          'septiembre',
                          'octubre',
                          'noviembre',
                          'diciembre'
                        ][DateTime.parse(entry['date'].toString()).month - 1]}',
                    '${DateTime.parse(entry['checked_in_at'].toString()).toLocal().hour.toString().padLeft(2, '0')}:${DateTime.parse(entry['checked_in_at'].toString()).toLocal().minute.toString().padLeft(2, '0')} · ${entry['source'] == 'app' ? 'Registrada en la app' : 'Registrada por el gimnasio'}',
                    icon: Icons.event_available,
                  ),
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
  bool _savingProfile = false;

  @override
  void initState() {
    super.initState();
    _profile = authController.clientDashboard();
  }

  Future<void> _editContact(String field, String current) async {
    final label = field == 'email' ? 'Correo electrónico' : 'Teléfono';
    final values =
        await _editFields(context, 'EDITAR $label', [label], [current]);
    if (!mounted || values == null) return;
    if (field == 'email') {
      final email = values.first.trim();
      if (email.toLowerCase() != current.toLowerCase() &&
          !await _verifyEmailChange(context, email)) return;
      await _saveClientProfile(email: email);
    } else {
      await _saveClientProfile(phone: values.first.trim());
    }
  }

  Future<void> _pickProfilePhoto() async {
    try {
      final selected = await pickProfilePhoto(context);
      if (!mounted || selected == null) return;
      await _saveClientProfile(
          photoData: base64Encode(selected.bytes),
          photoMime: selected.mimeType);
    } catch (e) {
      _showProfileMessage(e.toString().replaceFirst('FormatException: ', ''));
    }
  }

  Future<void> _saveClientProfile(
      {String? firstName,
      String? lastName,
      String? email,
      String? phone,
      String? photoData,
      String? photoMime,
      bool removePhoto = false}) async {
    setState(() => _savingProfile = true);
    try {
      final saved = await authController.updateClientProfile(
          firstName: firstName,
          lastName: lastName,
          email: email,
          phone: phone,
          photoData: photoData,
          photoMime: photoMime,
          removePhoto: removePhoto);
      if (mounted) {
        setState(() => _profile = Future.value(saved));
        _showProfileMessage('Perfil actualizado.');
      }
    } catch (error) {
      _showProfileMessage('No se pudo actualizar el perfil: $error');
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  void _showProfileMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _chooseTrainer() async {
    await context.push('/home/trainers');
    if (mounted) {
      setState(() => _profile = authController.clientDashboard());
    }
  }

  Future<void> _editTrainer(Map<String, dynamic> data) async {
    if ((data['trainer_name'] ?? '').toString().isEmpty) {
      await _chooseTrainer();
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cambio de entrenador'),
        content: const Text(
            'Tu entrenador actual ya está asignado. Para mantener el seguimiento de tu rutina, el administrador puede reasignarte si el entrenador deja el gimnasio.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendido'))
        ],
      ),
    );
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
          final photo = data['profile_photo_data'];
          final photoBytes =
              photo is String && photo.isNotEmpty ? base64Decode(photo) : null;
          final photoUrl = data['profile_photo_url']?.toString();
          return Column(children: [
            if (_savingProfile) const LinearProgressIndicator(),
            MusklCard(
                child: Column(children: [
              ProfilePhotoAvatar(
                  radius: 38,
                  image: photoUrl != null && photoUrl.isNotEmpty
                      ? NetworkImage(photoUrl)
                      : photoBytes == null
                          ? null
                          : MemoryImage(photoBytes),
                  name: '${data['first_name']} ${data['last_name']}',
                  onEdit: _savingProfile ? () {} : _pickProfilePhoto),
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
                icon: Icons.mail_outline,
                editable: true,
                onTap: _savingProfile
                    ? null
                    : () => _editContact(
                        'email', (data['email'] ?? '').toString())),
            _record('Teléfono', (data['phone'] ?? 'Sin teléfono').toString(),
                icon: Icons.phone_outlined,
                editable: true,
                onTap: _savingProfile
                    ? null
                    : () => _editContact(
                        'phone', (data['phone'] ?? '').toString())),
            _record('Entrenador',
                (data['trainer_name'] ?? 'Sin asignar').toString(),
                icon: Icons.person_outline,
                editable: true,
                onTap: () => _editTrainer(data)),
            if ((data['trainer_name'] ?? '').toString().isEmpty)
              _setting(
                  data['pending_trainer_id'] == null
                      ? 'Elegir entrenador'
                      : 'Cambiar solicitud de entrenador',
                  data['pending_trainer_id'] == null
                      ? 'Solicita que un entrenador te acepte'
                      : 'Pendiente con ${data['pending_trainer_name'] ?? 'el entrenador'}',
                  Icons.fitness_center,
                  onTap: _chooseTrainer),
            _section('Membresía'),
            MusklCard(
                child: Row(children: [
              const Icon(Icons.card_membership, color: AppColors.accent),
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
                    Text(
                        'Fecha de pago ${data['payment_due_on'] ?? 'pendiente'}',
                        style: const TextStyle(color: AppColors.textMuted)),
                  ])),
              const Text('ACTIVO', style: TextStyle(color: AppColors.red)),
            ])),
            _setting('Cambiar contraseña', 'Actualiza tus credenciales',
                Icons.lock_outline,
                onTap: () => context.push('/home/password')),
            const SizedBox(height: 8),
            MusklButton(
                label: 'Cerrar sesión',
                style: MusklButtonStyle.ghost,
                onPressed: authController.signOut),
            const SizedBox(height: 10),
            if (data['deletion_request_status'] == 'pending')
              MusklCard(
                  child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.hourglass_top,
                          color: AppColors.accent),
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
            if (data['deletion_request_status'] != 'pending')
              MusklButton(
                  label: 'Solicitar eliminación de mi cuenta',
                  icon: Icons.delete_outline,
                  style: MusklButtonStyle.secondary,
                  onPressed: _requestDeletion),
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
  late Future<List<Map<String, dynamic>>> _assignmentRequests;
  Timer? _assignmentRequestTimer;

  @override
  void initState() {
    super.initState();
    _loadClients();
    _notifications = authController.trainerNotifications();
    _assignmentRequests = authController.trainerAssignmentRequests();
    _assignmentRequestTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() =>
            _assignmentRequests = authController.trainerAssignmentRequests());
      }
    });
  }

  @override
  void dispose() {
    _assignmentRequestTimer?.cancel();
    super.dispose();
  }

  void _loadClients() =>
      _clients = authController.trainerClients(search: search);

  Future<void> _reviewAssignment(String requestId, bool accept) async {
    try {
      Map<String, dynamic>? selectedRoutine;
      if (accept) {
        final routines = await authController.trainerRoutines();
        final published = routines
            .where((routine) =>
                routine['phase_status'] == 'published' &&
                routine['phase_id'] != null)
            .toList();
        if (!mounted) return;
        if (published.isNotEmpty) {
          selectedRoutine = await showModalBottomSheet<Map<String, dynamic>>(
            context: context,
            builder: (context) => SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  const ListTile(
                      title: Text('ELIGE LA RUTINA PARA ESTE SOCIO'),
                      subtitle: Text(
                          'Se asignará junto con la aceptación de la solicitud.')),
                  for (final routine in published)
                    ListTile(
                      leading: const Icon(Icons.fitness_center),
                      title: Text(routine['name'].toString()),
                      subtitle: Text(
                          '${routine['goal']} · ${routine['days_per_week']} días'),
                      onTap: () => Navigator.pop(context, routine),
                    ),
                ],
              ),
            ),
          );
          if (selectedRoutine == null || !mounted) return;
        }
      }
      await authController.reviewTrainerAssignmentRequest(
          requestId: requestId,
          accept: accept,
          routineId: selectedRoutine?['id']?.toString(),
          phaseId: selectedRoutine?['phase_id']?.toString());
      if (!mounted) return;
      setState(() {
        _loadClients();
        _assignmentRequests = authController.trainerAssignmentRequests();
        _notifications = authController.trainerNotifications();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(accept
              ? selectedRoutine == null
                  ? 'Aceptaste al socio. Puedes asignarle una rutina publicada desde Mis rutinas.'
                  : 'Aceptaste al socio y le asignaste ${selectedRoutine['name']}.'
              : 'Solicitud rechazada.')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo revisar la solicitud: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => WorkspacePage(
      title: 'Mis clientes',
      kicker: 'ENTRENADOR',
      items: _trainerNav,
      selected: 0,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FutureBuilder<List<Map<String, dynamic>>>(
            future: _assignmentRequests,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return MusklCard(
                    child: Text(
                        'No se pudieron cargar las solicitudes. Se volverá a intentar automáticamente. ${snapshot.error}'));
              }
              final requests = snapshot.data ?? [];
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(child: _section('Solicitudes de socios')),
                      IconButton(
                          tooltip: 'Actualizar solicitudes',
                          onPressed: () => setState(() => _assignmentRequests =
                              authController.trainerAssignmentRequests()),
                          icon: const Icon(Icons.refresh)),
                    ]),
                    if (requests.isEmpty)
                      const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text('No tienes solicitudes pendientes.')),
                    for (final request in requests)
                      MusklCard(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(
                                '${request['first_name']} ${request['last_name']}',
                                style: Theme.of(context).textTheme.titleMedium),
                            Text(
                                'Socio ${request['member_number'] ?? ''} · ${request['email'] ?? ''}',
                                style: const TextStyle(
                                    color: AppColors.textMuted)),
                            const SizedBox(height: 10),
                            Row(children: [
                              Expanded(
                                  child: OutlinedButton(
                                      onPressed: () => _reviewAssignment(
                                          request['id'].toString(), false),
                                      child: const Text('Rechazar'))),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: FilledButton(
                                      onPressed: () => _reviewAssignment(
                                          request['id'].toString(), true),
                                      child: const Text('Aceptar'))),
                            ]),
                          ])),
                  ]);
            }),
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
                    _metric('$atRisk', 'En riesgo', color: AppColors.accent),
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
                              color: AppColors.accent),
                          const SizedBox(width: 8),
                          _metric('${client['attendance_total'] ?? 0}',
                              'Asistencias'),
                          const SizedBox(width: 8),
                          _metric('${client['workouts_total'] ?? 0}', 'Rutinas',
                              color: AppColors.accent)
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
      final availableClients = clients
          .where((item) => (item['routine_name'] ?? '').toString().isEmpty)
          .toList();
      if (!mounted) return;
      if (availableClients.isEmpty) {
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
              for (final item in availableClients)
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
  final Map<String, List<Map<String, dynamic>>> exercisesByDay = {};
  String activeDay = 'LUN';
  bool saving = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> _addExercise() async {
    final searchController = TextEditingController();
    var results = authController.trainerExerciseCatalog();
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .78,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 16, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Buscar ejercicio',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: searchController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Nombre, grupo muscular o equipo',
                    ),
                    onChanged: (value) => setSheetState(() => results =
                        authController.trainerExerciseCatalog(search: value)),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: FutureBuilder<List<Map<String, dynamic>>>(
                      future: results,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError) {
                          return Center(
                              child:
                                  Text('No se pudo buscar: ${snapshot.error}'));
                        }
                        final rows = snapshot.data ?? [];
                        if (rows.isEmpty) {
                          return const Center(
                              child:
                                  Text('No hay ejercicios con esa búsqueda.'));
                        }
                        return ListView.builder(
                          itemCount: rows.length,
                          itemBuilder: (context, index) {
                            final exercise = rows[index];
                            return ListTile(
                              leading: const Icon(Icons.fitness_center),
                              title: Text(exercise['name'].toString()),
                              subtitle: Text(
                                  '${exercise['muscle_group']} · ${exercise['equipment']}'),
                              onTap: () =>
                                  Navigator.pop(sheetContext, exercise),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    searchController.dispose();
    if (selected != null && mounted) {
      setState(() {
        exercisesByDay.putIfAbsent(activeDay, () => []).add(selected);
        error = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) => WorkspacePage(
      title: 'Nueva rutina',
      items: _trainerNav,
      selected: 2,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        MusklTextField(
          label: 'Nombre de la rutina',
          controller: name,
          icon: Icons.edit,
          onChanged: (_) => setState(() {}),
        ),
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
                            activeDay = d;
                          } else {
                            selectedDays.remove(d);
                            exercisesByDay.remove(d);
                            if (activeDay == d && selectedDays.isNotEmpty) {
                              activeDay = selectedDays.first;
                            }
                          }
                        })))
                .toList()),
        if (selectedDays.isNotEmpty) ...[
          _section('Día que estás editando'),
          Wrap(
              spacing: 6,
              children: ['LUN', 'MAR', 'MIÉ', 'JUE', 'VIE', 'SÁB', 'DOM']
                  .where(selectedDays.contains)
                  .map((d) => ChoiceChip(
                        label: Text(d),
                        selected: activeDay == d,
                        onSelected: (_) => setState(() => activeDay = d),
                      ))
                  .toList()),
        ],
        _section('Ejercicios de $activeDay',
            action: 'Buscar y agregar', onAction: _addExercise),
        for (var i = 0; i < (exercisesByDay[activeDay] ?? []).length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Expanded(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.fitness_center),
                  title: Text(exercisesByDay[activeDay]![i]['name'].toString()),
                  subtitle: Text(
                      '${exercisesByDay[activeDay]![i]['muscle_group']} · ${exercisesByDay[activeDay]![i]['equipment']}'),
                ),
              ),
              IconButton(
                tooltip: 'Quitar ejercicio',
                onPressed: saving
                    ? null
                    : () =>
                        setState(() => exercisesByDay[activeDay]!.removeAt(i)),
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
                    selectedDays
                        .any((day) => (exercisesByDay[day] ?? []).isEmpty) ||
                    exercisesByDay.values.expand((items) => items).any(
                        (exercise) =>
                            exercise['name'].toString().trim().isEmpty) ||
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
                        exercises: [
                          for (final day in selectedDays)
                            for (final exercise in exercisesByDay[day] ?? [])
                              {...exercise, 'day_number': dayNumber[day]},
                        ],
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
  static Map<String, String> hours = {
    for (final day in _weekDays) day: 'Cerrado',
  };
}

const _weekDays = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo'
];

String _formatGymHours(Map<String, dynamic> hours) => _weekDays
    .map((day) => '$day: ${hours[day]?.toString() ?? 'Cerrado'}')
    .join('\n');

Map<String, String> _readGymHours(Map<String, dynamic> value) {
  final result = {for (final day in _weekDays) day: 'Cerrado'};
  for (final day in _weekDays) {
    final schedule = value[day]?.toString();
    if (schedule != null && schedule.isNotEmpty) result[day] = schedule;
  }
  final legacy = value['display']?.toString();
  if (legacy != null) {
    for (final line in legacy.split('\n')) {
      final parts = line.split(':');
      if (parts.length < 2) continue;
      final label = parts.first.trim().toLowerCase();
      final schedule = parts.skip(1).join(':').trim();
      final range = RegExp(
              r'^(lunes|martes|miércoles|jueves|viernes|sábado|domingo)\s+a\s+(lunes|martes|miércoles|jueves|viernes|sábado|domingo)$',
              caseSensitive: false)
          .firstMatch(label);
      if (range != null) {
        final start = _weekDays.indexWhere(
            (d) => d.toLowerCase() == range.group(1)!.toLowerCase());
        final end = _weekDays.indexWhere(
            (d) => d.toLowerCase() == range.group(2)!.toLowerCase());
        if (start >= 0 && end >= start) {
          for (var i = start; i <= end; i++) {
            result[_weekDays[i]] = schedule;
          }
        }
      } else {
        for (final day in _weekDays) {
          if (day.toLowerCase() == label) result[day] = schedule;
        }
      }
    }
  }
  return result;
}

class _GymDayHoursEditor extends StatelessWidget {
  const _GymDayHoursEditor(
      {required this.day, required this.value, required this.onChanged});

  final String day;
  final String value;
  final ValueChanged<String> onChanged;

  Future<void> _pickTime(BuildContext context, {required bool opening}) async {
    final parts = value.split(RegExp(r'[–-]'));
    final current = parts.length == 2
        ? (opening ? parts.first.trim() : parts.last.trim())
        : opening
            ? '05:00'
            : '23:00';
    final parsed = current.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parsed.first) ?? (opening ? 5 : 23),
      minute: parsed.length > 1 ? int.tryParse(parsed[1]) ?? 0 : 0,
    );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    final formatted =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    final start = opening
        ? formatted
        : (parts.length == 2 ? parts.first.trim() : '05:00');
    final end =
        opening ? (parts.length == 2 ? parts.last.trim() : '23:00') : formatted;
    onChanged('$start–$end');
  }

  @override
  Widget build(BuildContext context) {
    final isOpen = value.toLowerCase() != 'cerrado';
    final parts = value.split(RegExp(r'[–-]'));
    return Column(children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(day),
        subtitle: Text(isOpen ? value : 'No se labora'),
        value: isOpen,
        onChanged: (enabled) => onChanged(enabled ? '05:00–23:00' : 'Cerrado'),
      ),
      if (isOpen)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickTime(context, opening: true),
                icon: const Icon(Icons.access_time),
                label: Text(
                    'De ${parts.isNotEmpty ? parts.first.trim() : '05:00'}'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickTime(context, opening: false),
                icon: const Icon(Icons.access_time),
                label:
                    Text('A ${parts.length > 1 ? parts.last.trim() : '23:00'}'),
              ),
            ),
          ]),
        ),
      const Divider(height: 1),
    ]);
  }
}

Future<void> _showCertificationPreview(
  BuildContext context, {
  required String title,
  required String url,
}) async {
  final extension = title.split('.').last.toLowerCase();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          leading: IconButton(
            tooltip: 'Cerrar',
            onPressed: () => Navigator.of(dialogContext).pop(),
            icon: const Icon(Icons.close),
          ),
        ),
        body: extension == 'pdf'
            ? PdfViewer.uri(Uri.parse(url))
            : InteractiveViewer(
                minScale: 0.5,
                maxScale: 5,
                child: Center(
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, progress) =>
                        progress == null
                            ? child
                            : const Center(child: CircularProgressIndicator()),
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Text('No se pudo cargar la imagen.'),
                    ),
                  ),
                ),
              ),
      ),
    ),
  );
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

  Future<void> _changeProfilePhoto() async {
    final selected = await _pickOwnProfilePhoto();
    if (selected == null) return;
    setState(() => _saving = true);
    try {
      final saved = await authController.updateOwnProfilePhoto(
          photoData: base64Encode(selected.bytes),
          photoMime: selected.mimeType);
      if (mounted) {
        setState(
            () => _profile['profile_photo_url'] = saved['profile_photo_url']);
      }
      _message('Foto de perfil actualizada.');
    } catch (e) {
      _message('No se pudo guardar la foto: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<ProfilePhotoSelection?> _pickOwnProfilePhoto() async {
    try {
      return await pickProfilePhoto(context);
    } catch (e) {
      _message(e.toString().replaceFirst('FormatException: ', ''));
      return null;
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
    if (result[2].toLowerCase() != _value('email').toLowerCase()) {
      if (!await _verifyEmailChange(context, result[2])) return;
    }
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

  Future<void> _viewOwnCertification(Map certificate) async {
    try {
      final url = await authController.ownTrainerCertificationDownloadUrl(
        certificationId: certificate['id'].toString(),
      );
      if (!mounted) return;
      await _showCertificationPreview(
        context,
        title: certificate['title']?.toString() ?? 'Certificado',
        url: url,
      );
    } catch (e) {
      _message('No se pudo abrir tu certificado: $e');
    }
  }

  Future<void> _replaceOwnCertification(Map certificate) async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
        allowMultiple: false,
        withData: true,
      );
      if (!mounted || picked == null) return;
      final file = picked.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        _message('No se pudo leer el archivo seleccionado.');
        return;
      }
      if (bytes.length > 10 * 1024 * 1024) {
        _message('El certificado debe pesar máximo 10 MB.');
        return;
      }
      await authController.replaceOwnTrainerCertification(
        certificationId: certificate['id'].toString(),
        filename: file.name,
        bytes: bytes,
      );
      if (!mounted) return;
      final certifications = List<Map<String, dynamic>>.from(
        (_profile['certifications'] as List? ?? [])
            .map((item) => Map<String, dynamic>.from(item as Map)),
      );
      final index = certifications.indexWhere(
          (item) => item['id'].toString() == certificate['id'].toString());
      if (index >= 0) {
        certifications[index] = {
          ...certifications[index],
          'title': file.name,
          'verified_at': null,
        };
      }
      setState(() => _profile['certifications'] = certifications);
      _message('Certificado actualizado y enviado para verificación.');
    } catch (e) {
      _message('No se pudo actualizar el certificado: $e');
    }
  }

  Future<void> _changePassword() async {
    if (mounted) context.push('/trainer/password');
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
                  child: Row(children: [
                ProfilePhotoAvatar(
                    image: _value('profile_photo_url').isEmpty
                        ? null
                        : NetworkImage(_value('profile_photo_url')),
                    name: '${_value('first_name')} ${_value('last_name')}',
                    onEdit: _saving ? () {} : _changeProfilePhoto),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('${_value('first_name')} ${_value('last_name')}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('Entrenador · ${_value('specialty')}'),
                    ])),
              ])),
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
                MusklCard(
                    child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.workspace_premium_outlined,
                      color: AppColors.accent),
                  title: Text((certificate as Map)['title'].toString()),
                  subtitle: Text(certificate['verified_at'] == null
                      ? 'Documento registrado · pendiente de verificación'
                      : 'Certificación verificada'),
                  onTap: () => _viewOwnCertification(certificate),
                  trailing: IconButton(
                    tooltip: 'Reemplazar certificado',
                    onPressed: () => _replaceOwnCertification(certificate),
                    icon: const Icon(Icons.upload_file),
                  ),
                )),
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

Future<bool> _verifyEmailChange(BuildContext context, String newEmail) async {
  final codeController = TextEditingController();
  final passwordController = TextEditingController();
  try {
    await authController.requestEmailChangeCode(newEmail: newEmail.trim());
    if (!context.mounted) return false;
    final credentials = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Verifica tu nuevo correo'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Escribimos un código de 6 dígitos a $newEmail.'),
          const SizedBox(height: 14),
          TextField(
            controller: codeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(labelText: 'Código'),
          ),
          TextField(
            controller: passwordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Contraseña actual'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, [
                    codeController.text.trim(),
                    passwordController.text,
                  ]),
              child: const Text('Verificar y cambiar')),
        ],
      ),
    );
    if (credentials == null || !context.mounted) return false;
    await authController.confirmEmailChange(
      currentPassword: credentials[1],
      code: credentials[0],
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Correo verificado y actualizado.')));
    }
    return true;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo cambiar el correo: $error')));
    }
    return false;
  } finally {
    codeController.dispose();
    passwordController.dispose();
  }
}

Future<List<String>?> _editFields(BuildContext context, String title,
    List<String> labels, List<String> values,
    {bool obscure = false,
    bool trim = true,
    Set<int> multiline = const {}}) async {
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
              onPressed: () => Navigator.pop(
                  dialogContext,
                  controllers
                      .map((c) => trim ? c.text.trim() : c.text)
                      .toList()),
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
            leading: Icon(icon, color: AppColors.accent),
            title: Text(title),
            subtitle: Text(subtitle),
            trailing: const Icon(Icons.chevron_right)));

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _currentPassword = TextEditingController();
  final _code = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmation = TextEditingController();
  int _furthestStep = 0;
  bool _loading = false;
  String? _error;
  String? _deliveryMessage;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this)
      ..addListener(() {
        if (_tabs.index > _furthestStep) _tabs.index = _furthestStep;
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _currentPassword.dispose();
    _code.dispose();
    _newPassword.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    setState(() => _error = null);
    if (_tabs.index == 0) {
      if (_currentPassword.text.isEmpty) {
        setState(() => _error = 'Escribe tu contraseña actual.');
        return;
      }
      setState(() => _loading = true);
      try {
        final channel = await authController.sendPasswordChangeCode(
            currentPassword: _currentPassword.text);
        if (!mounted) return;
        setState(() {
          _deliveryMessage = channel == 'development'
              ? 'Código de prueba generado; revisa la consola del API.'
              : 'Enviamos un código de seguridad al correo vinculado.';
          _furthestStep = 1;
          _tabs.animateTo(1);
        });
      } catch (error) {
        if (mounted) {
          setState(() => _error =
              'No se pudo validar la contraseña actual. ${_readableError(error)}');
        }
      } finally {
        if (mounted) setState(() => _loading = false);
      }
      return;
    }
    if (_tabs.index == 1) {
      if (!RegExp(r'^\d{6}$').hasMatch(_code.text.trim())) {
        setState(() => _error = 'Escribe el código de seguridad de 6 dígitos.');
        return;
      }
      setState(() => _loading = true);
      try {
        await authController.verifyPasswordChangeCode(
            currentPassword: _currentPassword.text, code: _code.text.trim());
        if (!mounted) return;
        setState(() {
          _furthestStep = 2;
          _tabs.animateTo(2);
        });
      } catch (error) {
        if (mounted) setState(() => _error = _readableError(error));
      } finally {
        if (mounted) setState(() => _loading = false);
      }
      return;
    }
    if (!isStrongPassword(_newPassword.text)) {
      setState(() => _error =
          'Usa al menos 8 caracteres con mayúscula, minúscula, número y carácter especial.');
      return;
    }
    if (_newPassword.text != _confirmation.text) {
      setState(() => _error = 'Las contraseñas no coinciden.');
      return;
    }
    setState(() => _loading = true);
    try {
      await authController.changePassword(
          currentPassword: _currentPassword.text,
          newPassword: _newPassword.text,
          code: _code.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Contraseña actualizada. Las demás sesiones se cerraron.')));
      context.pop();
    } catch (error) {
      if (mounted) {
        setState(() => _error =
            'No se pudo cambiar la contraseña. ${_readableError(error)}');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _readableError(Object error) => error is AuthException
      ? error.message
      : error.toString().replaceFirst('Exception: ', '');

  @override
  Widget build(BuildContext context) {
    final step = _tabs.index;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cambiar contraseña'),
        bottom: TabBar(
          controller: _tabs,
          onTap: (index) {
            if (index > _furthestStep) _tabs.animateTo(_furthestStep);
          },
          tabs: const [
            Tab(text: 'Actual', icon: Icon(Icons.lock_outline)),
            Tab(text: 'Código', icon: Icon(Icons.verified_user_outlined)),
            Tab(text: 'Nueva', icon: Icon(Icons.password_outlined)),
          ],
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('PASO ${step + 1} DE 3',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: AppColors.red,
                            fontWeight: FontWeight.bold,
                          )),
                  const SizedBox(height: 12),
                  Expanded(
                    child: TabBarView(
                      controller: _tabs,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _passwordStep(
                          title: 'Confirma tu contraseña actual',
                          description:
                              'La verificaremos antes de enviar el código de seguridad.',
                          controller: _currentPassword,
                          label: 'Contraseña actual',
                        ),
                        _passwordStep(
                          title: 'Verifica tu identidad',
                          description: _deliveryMessage ??
                              'Escribe el código enviado a tu correo.',
                          controller: _code,
                          label: 'Código de 6 dígitos',
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                        ),
                        SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text('Elige una contraseña nueva',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge),
                              const SizedBox(height: 8),
                              const Text(
                                  'Debe incluir mayúscula, minúscula, número y carácter especial.'),
                              const SizedBox(height: 24),
                              _passwordField(_newPassword, 'Nueva contraseña',
                                  onChanged: (_) => setState(() {})),
                              const SizedBox(height: 12),
                              PasswordStrength(password: _newPassword.text),
                              const SizedBox(height: 20),
                              _passwordField(_confirmation,
                                  'Confirmar contraseña',
                                  onChanged: (_) => setState(() {})),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    Text(_error!, style: const TextStyle(color: AppColors.red)),
                    const SizedBox(height: 12),
                  ],
                  MusklButton(
                    label: _loading
                        ? 'Procesando...'
                        : step == 2
                            ? 'Guardar contraseña'
                            : 'Continuar',
                    loading: _loading,
                    onPressed: _loading ? null : _continue,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _passwordStep({
    required String title,
    required String description,
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    int? maxLength,
  }) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(description),
            const SizedBox(height: 24),
            _passwordField(controller, label,
                keyboardType: keyboardType, maxLength: maxLength),
          ],
        ),
      );

  Widget _passwordField(TextEditingController controller, String label,
          {TextInputType? keyboardType,
          int? maxLength,
          ValueChanged<String>? onChanged}) =>
      TextField(
        controller: controller,
        obscureText: keyboardType != TextInputType.number,
        keyboardType: keyboardType,
        maxLength: maxLength,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          counterText: maxLength == null ? null : '',
        ),
      );
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
                              backgroundColor: AppColors.accent,
                              child: Icon(Icons.person_add_alt,
                                  color: AppColors.bgDeep)),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text('$pending SOLICITUDES PENDIENTES',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900))),
                          const Icon(Icons.chevron_right,
                              color: AppColors.accent),
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

  Future<void> _deactivateUser(Map<String, dynamic> user) async {
    final name = '${user['first_name']} ${user['last_name']}';
    final userId = user['id']?.toString();
    final memberNumber = user['member_number']?.toString() ?? '';
    if ((userId == null || userId.isEmpty) && memberNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se encontró el identificador de esta cuenta.')));
      return;
    }
    final changed = await context.push<bool>(
      Uri(
        path: '/admin/deactivate',
        queryParameters: {
          'id': userId ?? '',
          'member': memberNumber,
          'name': name,
          'role': user['role'].toString(),
        },
      ).toString(),
    );
    if (changed == true && mounted) setState(_reload);
  }

  Widget _userRecord(Map<String, dynamic> user) {
    final role = user['role']?.toString().toLowerCase();
    final status = user['status']?.toString().toLowerCase();
    final canDeactivate =
        (role == 'client' || role == 'trainer') && status != 'deactivated';
    final roleLabel = role == 'trainer' ? 'entrenador' : 'socio';
    return Column(children: [
      _record(
        '${user['first_name']} ${user['last_name']}',
        '${role == 'client' ? 'Socio' : role == 'trainer' ? 'Entrenador' : 'Admin'} · ${status == 'deactivated' ? 'Baja' : status == 'pending' ? 'En revisión' : status == 'rejected' ? 'Rechazado' : 'Activo'}${user['member_number'] == null ? '' : ' · ${user['member_number']}'}',
        icon: Icons.person_outline,
        onTap: () async {
          final changed = await context
              .push<bool>(Uri(path: '/admin/member', queryParameters: {
            'id': user['id'].toString(),
            'member': (user['member_number'] ?? '').toString(),
            'name': '${user['first_name']} ${user['last_name']}',
            'role': role ?? '',
            'email': (user['email'] ?? '').toString(),
            'phone': (user['phone'] ?? '').toString(),
            'plan': (user['membership_plan'] ?? '').toString(),
            'status': status ?? '',
            'deactivated_by': (user['deactivated_by'] ?? '').toString(),
            'trainer_id': (user['trainer_id'] ?? '').toString(),
            'trainer_name': (user['trainer_name'] ?? '').toString(),
            'trainer_reassignment_required':
                user['trainer_reassignment_required'] == true
                    ? 'true'
                    : 'false',
            'reactivation_until': user['reactivation_until']?.toString() ?? '',
          }).toString());
          if (changed == true && mounted) setState(_reload);
        },
      ),
      if (canDeactivate)
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 12),
          child: Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: () => _deactivateUser(user),
              icon: const Icon(Icons.person_off_outlined),
              label: Text('Dar de baja $roleLabel'),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.red),
            ),
          ),
        ),
    ]);
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
                  for (final user in rows) _userRecord(user),
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
  bool _savingExercise = false;

  @override
  void initState() {
    super.initState();
    _routine = authController.adminRoutine(routineId: widget.routineId);
  }

  Future<void> _assignToClient(Map<String, dynamic> phase) async {
    try {
      final clients =
          await authController.adminUsers(role: 'client', status: 'active');
      if (!mounted) return;
      if (clients.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No hay socios activos para asignar.')));
        return;
      }
      final client = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('ASIGNAR RUTINA A SOCIO')),
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
      await authController.assignAdminRoutine(
          routineId: widget.routineId,
          phaseId: phase['id'].toString(),
          clientId: client['id'].toString());
      if (!mounted) return;
      setState(() =>
          _routine = authController.adminRoutine(routineId: widget.routineId));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Rutina asignada a ${client['first_name']}. Ya puede verla en su panel.')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo asignar la rutina: $error')));
      }
    }
  }

  Future<void> _editExercise(Map<String, dynamic> exercise) async {
    final values = await _editFields(context, 'EDITAR EJERCICIO', [
      'Nombre',
      'Series',
      'Repeticiones',
      'Descanso en segundos',
      'Día (1 lunes, 7 domingo)',
    ], [
      exercise['name'].toString(),
      exercise['sets'].toString(),
      exercise['reps'].toString(),
      exercise['rest_seconds'].toString(),
      exercise['day_number'].toString(),
    ]);
    if (!mounted || values == null) return;
    final sets = int.tryParse(values[1]);
    final rest = int.tryParse(values[3]);
    final day = int.tryParse(values[4]);
    if (sets == null || rest == null || day == null || day < 1 || day > 7) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Series, descanso o día no son válidos.')));
      return;
    }
    setState(() => _savingExercise = true);
    try {
      await authController.updateAdminRoutineExercise(
        routineId: widget.routineId,
        exerciseId: exercise['id'].toString(),
        name: values[0].trim(),
        sets: sets,
        reps: values[2].trim(),
        restSeconds: rest,
        dayNumber: day,
      );
      if (!mounted) return;
      setState(() =>
          _routine = authController.adminRoutine(routineId: widget.routineId));
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ejercicio de la rutina actualizado.')));
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No se pudo editar: $error')));
    } finally {
      if (mounted) setState(() => _savingExercise = false);
    }
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
                for (final phase in phases) ...[
                  _record('${phase['name']} · Fase ${phase['phase_number']}',
                      '${phase['status'] == 'published' ? 'Publicada' : 'Borrador'} · ${phase['duration_weeks']} semanas · ${phase['exercise_count']} ejercicios',
                      icon: phase['status'] == 'published'
                          ? Icons.check_circle_outline
                          : Icons.edit_outlined),
                  if (phase['status'] == 'published')
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: OutlinedButton.icon(
                          onPressed: () => _assignToClient(phase),
                          icon: const Icon(Icons.person_add_alt_1),
                          label: const Text('Asignar esta fase a un socio'),
                        ),
                      ),
                    ),
                ],
                _section('Ejercicios'),
                for (final exercise in exercises)
                  _record(exercise['name'].toString(),
                      'Fase ${exercise['phase_number']} · Día ${exercise['day_number']} · ${exercise['sets']} series · ${exercise['reps']} repeticiones · ${exercise['rest_seconds']} s',
                      editable: true,
                      onTap: _savingExercise
                          ? null
                          : () => _editExercise(exercise)),
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
  Map<String, dynamic> _ownProfile = {};
  bool _savingPhoto = false;

  @override
  void initState() {
    super.initState();
    _loadGym();
    _loadAdminOptions();
    _loadAdminPreferences();
    _loadOwnProfile();
  }

  Future<void> _loadOwnProfile() async {
    try {
      final profile = await authController.ownProfile();
      if (mounted) setState(() => _ownProfile = profile);
    } catch (e) {
      if (mounted) _showLocalMessage('No se pudo cargar el perfil: $e');
    }
  }

  Future<void> _changeAdminPhoto() async {
    ProfilePhotoSelection? selected;
    try {
      selected = await pickProfilePhoto(context);
    } catch (e) {
      _showLocalMessage(e.toString().replaceFirst('FormatException: ', ''));
      return;
    }
    if (!mounted || selected == null) return;
    setState(() => _savingPhoto = true);
    try {
      final saved = await authController.updateOwnProfilePhoto(
          photoData: base64Encode(selected.bytes),
          photoMime: selected.mimeType);
      if (mounted) setState(() => _ownProfile = saved);
      _showLocalMessage('Foto de perfil actualizada.');
    } catch (e) {
      _showLocalMessage('No se pudo guardar la foto: $e');
    } finally {
      if (mounted) setState(() => _savingPhoto = false);
    }
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
        _PrototypeSettings.hours = _readGymHours(hours);
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
    final hours = Map<String, String>.from(_PrototypeSettings.hours);
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('HORARIOS DE APERTURA'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final day in _weekDays)
                    _GymDayHoursEditor(
                      day: day,
                      value: hours[day] ?? 'Cerrado',
                      onChanged: (value) =>
                          setDialogState(() => hours[day] = value),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, hours),
                child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (result == null) return;
    try {
      final saved = await authController.updateAdminGym(
          name: _PrototypeSettings.gymName,
          address: _PrototypeSettings.gymAddress,
          phone: _PrototypeSettings.gymPhone,
          openingHours: result);
      if (mounted) {
        setState(() => _PrototypeSettings.hours = _readGymHours(
            Map<String, dynamic>.from(
                saved['opening_hours'] as Map? ?? result)));
      }
    } catch (e) {
      _showLocalMessage('No se pudieron guardar los horarios: $e');
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
                    '\$${plan['price_mxn']} MXN · ${plan['duration_days']} días · ${plan['min_group_size'] ?? 1}–${plan['max_group_size'] ?? 1} personas · ${plan['active'] == true ? 'Activo' : 'Inactivo'}'),
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
    final controllers = [
      TextEditingController(text: plan?['name']?.toString() ?? ''),
      TextEditingController(text: plan?['price_mxn']?.toString() ?? ''),
      TextEditingController(text: plan?['duration_days']?.toString() ?? '30'),
      TextEditingController(text: plan?['min_group_size']?.toString() ?? '1'),
      TextEditingController(text: plan?['max_group_size']?.toString() ?? '1'),
    ];
    var active = plan?['active'] != false;
    List<String>? values;
    try {
      values = await showDialog<List<String>>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
                builder: (context, setDialogState) => AlertDialog(
                  title: Text(plan == null ? 'NUEVO PLAN' : 'EDITAR PLAN'),
                  content: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      for (final (index, label) in [
                        'Nombre',
                        'Precio en MXN',
                        'Duración en días',
                        'Mínimo de personas',
                        'Máximo de personas',
                      ].indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: TextField(
                            controller: controllers[index],
                            keyboardType: index == 0
                                ? TextInputType.text
                                : const TextInputType.numberWithOptions(
                                    decimal: true),
                            decoration: InputDecoration(
                              labelText: label,
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Plan disponible para clientes'),
                        value: active,
                        onChanged: (value) =>
                            setDialogState(() => active = value),
                      ),
                    ]),
                  ),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('Cancelar')),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, [
                        ...controllers
                            .map((controller) => controller.text.trim()),
                        active.toString(),
                      ]),
                      child: const Text('Guardar'),
                    ),
                  ],
                ),
              ));
    } finally {
      for (final controller in controllers) {
        controller.dispose();
      }
    }
    if (values == null) return;
    final price = double.tryParse(values[1]);
    final duration = int.tryParse(values[2]);
    final minGroupSize = int.tryParse(values[3]);
    final maxGroupSize = int.tryParse(values[4]);
    if (values[0].trim().isEmpty ||
        price == null ||
        price < 0 ||
        duration == null ||
        duration < 1 ||
        minGroupSize == null ||
        maxGroupSize == null ||
        minGroupSize < 1 ||
        maxGroupSize < minGroupSize) {
      _showLocalMessage(
          'Revisa nombre, precio, duración y cantidad de personas.');
      return;
    }
    try {
      await authController.saveAdminPlan(
          id: plan?['id']?.toString(),
          name: values[0].trim(),
          priceMxn: price,
          durationDays: duration,
          minGroupSize: minGroupSize,
          maxGroupSize: maxGroupSize,
          active: values[5] == 'true');
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
        if (_savingPhoto) const LinearProgressIndicator(),
        MusklCard(
            child: Row(children: [
          ProfilePhotoAvatar(
              image: (_ownProfile['profile_photo_url'] == null ||
                      _ownProfile['profile_photo_url'].toString().isEmpty)
                  ? null
                  : NetworkImage(_ownProfile['profile_photo_url'].toString()),
              name:
                  '${_ownProfile['first_name'] ?? ''} ${_ownProfile['last_name'] ?? ''}',
              onEdit: _savingPhoto ? () {} : _changeAdminPhoto),
          const SizedBox(width: 14),
          const Expanded(
              child: Text('Administrador',
                  style: TextStyle(fontWeight: FontWeight.bold))),
        ])),
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
        _setting(
            'Horarios de apertura',
            _formatGymHours(_PrototypeSettings.hours).replaceAll('\n', ' · '),
            Icons.schedule,
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
            onTap: () => context.push('/admin/password')),
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

  Future<void> _showCertificateLink(
      Map<String, dynamic> request, Map<String, dynamic> certificate) async {
    try {
      final url = await authController.trainerCertificationDownloadUrl(
        trainerId: request['id'].toString(),
        certificationId: certificate['id'].toString(),
      );
      if (!mounted) return;
      await _showCertificationPreview(
        context,
        title: certificate['title']?.toString() ?? 'Certificado',
        url: url,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo obtener el certificado: $e')));
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
              ? 'Baja aprobada. La cuenta se podrá reactivar durante 30 días; después se eliminarán sus datos.'
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
                                      color: AppColors.accent),
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
                            if (!_showDeletions && request['role'] == 'trainer')
                              for (final rawCertificate
                                  in (request['certifications'] as List? ?? []))
                                Builder(builder: (context) {
                                  final certificate = Map<String, dynamic>.from(
                                      rawCertificate as Map);
                                  return Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton.icon(
                                      onPressed: () => _showCertificateLink(
                                          request, certificate),
                                      icon: const Icon(Icons.lock_clock),
                                      label: Text(
                                          'Ver certificado · ${certificate['title']}'),
                                    ),
                                  );
                                }),
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

import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:video_player/video_player.dart';

import '../core/theme/app_colors.dart';
import '../core/widgets/muskl_bottom_nav.dart';
import '../core/widgets/muskl_button.dart';
import '../core/widgets/muskl_card.dart';
import '../core/widgets/password_strength.dart';
import '../core/widgets/profile_photo_avatar.dart';
import 'auth/auth_models.dart';
import 'client_home_content.dart';
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
    final elapsed = Stopwatch()..start();
    await authController.restoreSession();
    const minimumSplashTime = Duration(milliseconds: 900);
    final remaining = minimumSplashTime - elapsed.elapsed;
    if (remaining > Duration.zero) await Future<void>.delayed(remaining);
    if (mounted && authController.session == null) context.go('/welcome');
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.bgDeep,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Opacity(
              opacity: 0.24,
              child: Image.asset(
                'assets/images/splash_loading.jpg',
                fit: BoxFit.cover,
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.fromRGBO(12, 11, 13, 0.48),
                    Color.fromRGBO(12, 11, 13, 0.72),
                  ],
                ),
              ),
            ),
            SafeArea(
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
                    Text('MUSKL',
                        style: Theme.of(context).textTheme.headlineLarge),
                    const SizedBox(height: 8),
                    Text('ENTRENA · REGISTRA · SUPERA',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppColors.textMuted,
                              letterSpacing: 2,
                            )),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
          body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/splash.jpg',
            fit: BoxFit.cover,
            color: Colors.black.withValues(alpha: .52),
            colorBlendMode: BlendMode.darken,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x66090A0D),
                  Color(0x99090A0D),
                  Color(0xF2090A0D),
                ],
                stops: [0, .48, 1],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    const SizedBox(height: 16),
                    const Row(children: [
                      Icon(Icons.fitness_center, color: AppColors.red),
                      SizedBox(width: 12),
                      Text('MUSKL',
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2)),
                    ]),
                    SizedBox(height: MediaQuery.sizeOf(context).height * .25),
                    Text('Tu entrenamiento.\nTu siguiente paso.',
                        style: Theme.of(context).textTheme.headlineLarge),
                    const SizedBox(height: 14),
                    const Text(
                      'Encuentra tu rutina, registra tus visitas y sigue tu progreso con el apoyo de tu entrenador.',
                      style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 16,
                          height: 1.5),
                    ),
                    const SizedBox(height: 28),
                    MusklButton(
                      label: 'Iniciar sesión',
                      icon: Icons.arrow_forward_rounded,
                      onPressed: () => context.push('/login'),
                    ),
                    const SizedBox(height: 12),
                    MusklButton(
                      label: 'Registrarme',
                      style: MusklButtonStyle.secondary,
                      onPressed: () => context.push('/register'),
                    ),
                    const SizedBox(height: 20),
                    const Text('Tu gimnasio, contigo.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textMuted)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ));
}

class WorkspacePage extends StatelessWidget {
  const WorkspacePage(
      {super.key,
      required this.title,
      required this.child,
      required this.items,
      required this.selected,
      this.kicker,
      this.header,
      this.onRefresh,
      this.showAppBar = true});
  final String title;
  final Widget child;
  final List<(String, IconData, String)> items;
  final int selected;
  final String? kicker;
  final Widget? header;
  final bool showAppBar;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: showAppBar
            ? AppBar(
                toolbarHeight: header == null
                    ? null
                    : 96 * MediaQuery.textScalerOf(context).scale(1),
                title: header ??
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (kicker != null)
                          Text(kicker!,
                              style: const TextStyle(
                                  color: AppColors.red,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2)),
                        Text(title,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900)),
                      ],
                    ),
                actions: [
                    if (authController.session?.role == UserRole.admin)
                      IconButton(
                          tooltip: 'Solicitudes pendientes',
                          onPressed: () {
                            final route =
                                switch (authController.session?.role) {
                              UserRole.client => '/home/phase-available',
                              UserRole.trainer => '/trainer',
                              UserRole.admin => '/admin/requests',
                              null => '/',
                            };
                            context.push(route);
                          },
                          icon: const Icon(Icons.notifications_none)),
                  ])
            : null,
        body: SafeArea(
            child: onRefresh == null
                ? _content()
                : RefreshIndicator(onRefresh: onRefresh!, child: _content())),
        bottomNavigationBar: MusklBottomNav(
          items: items.map((e) => MusklNavItem(e.$1, e.$2)).toList(),
          currentIndex: selected,
          onTap: (i) {
            final destination = items[i].$3;
            if (GoRouterState.of(context).uri.path == destination) return;
            context.push(destination);
          },
        ),
      );

  Widget _content() => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: SizedBox(width: double.infinity, child: child)))
        ],
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
            child: Text(title,
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0))),
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
                style: TextStyle(
                    color: background.computeLuminance() > 0.28
                        ? AppColors.bgDeep.withValues(alpha: .78)
                        : AppColors.textMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: 11))
          ])),
    );

String _restTimeLabel(Object? value) {
  final seconds = int.tryParse(value?.toString() ?? '') ?? 0;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

String _profileDateLabel(Object? value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  if (date == null) return 'Sin fecha';
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

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

Widget _profileInfoField(String label, String value,
        {required IconData icon, VoidCallback? onEdit, bool enabled = true}) =>
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(icon, color: AppColors.accent, size: 20),
        const SizedBox(width: 11),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(),
                style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .9)),
            const SizedBox(height: 4),
            Text(value.trim().isEmpty ? 'Sin información' : value,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
        if (onEdit != null)
          IconButton(
            tooltip: 'Editar $label',
            onPressed: enabled ? onEdit : null,
            icon: const Icon(Icons.edit_outlined),
          ),
      ]),
    );

Widget _profileBioInline(String value) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.notes_outlined, color: AppColors.accent, size: 16),
            const SizedBox(width: 6),
            const Expanded(
              child: Text('BIOGRAFÍA',
                  style: TextStyle(
                      fontSize: 10,
                      letterSpacing: .8,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textMuted)),
            ),
          ]),
          const SizedBox(height: 2),
          Text(
            value.trim().isEmpty
                ? 'Agrega una descripción para que los demás te conozcan mejor.'
                : value.trim(),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            softWrap: true,
            style: TextStyle(
              color:
                  value.trim().isEmpty ? AppColors.textMuted : AppColors.white,
              height: 1.3,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );

Widget _exerciseThumbnail(Map<String, dynamic> exercise,
        {required double height}) =>
    ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: (exercise['media_url'] ?? '').toString().isEmpty ||
                (exercise['media_mime'] ?? '').toString().startsWith('video/')
            ? Stack(
       
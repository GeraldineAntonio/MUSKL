Warning: truncated output (original token count: 79233)
Total output lines: 8149

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
import 'package:url_launcher/url_launcher.dart';

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
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 66,
                      height: 66,
                      decoration: BoxDecoration(
                        color: AppColors.red,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(Icons.fitness_center,
                          size: 34, color: AppColors.white),
                    ),
                    const SizedBox(height: 14),
                    Text('MUSKL',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineLarge),
                    const SizedBox(height: 8),
                    Text('ENTRENA · REGISTRA · SUPERA',
                        textAlign: TextAlign.center,
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
                    Text(
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
                    Text('Tu gimnasio, contigo.',
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

String _notificationsPath(UserRole? role) => switch (role) {
      UserRole.client => '/home/notifications',
      UserRole.trainer => '/trainer/notifications',
      UserRole.admin => '/admin/notifications',
      null => '/welcome',
    };

String _accessibilityPath(UserRole? role) => switch (role) {
      UserRole.client => '/home/accessibility',
      UserRole.trainer => '/trainer/accessibility',
      UserRole.admin => '/admin/accessibility',
      null => '/welcome',
    };

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final UserRole? _role = authController.session?.role;
  Map<String, dynamic> _profile = {};
  Map<String, dynamic> _adminPreferences = {};
  Map<String, bool> _clientPreferences = {
    'routine_updates': true,
    'account_updates': true,
  };
  bool _pushNotificationsEnabled = false;
  bool _loading = true;
  bool _saving = false;
  late Future<List<Map<String, dynamic>>> _notifications;

  @override
  void initState() {
    super.initState();
    _notifications = _loadNotifications();
    _load();
  }

  Future<List<Map<String, dynamic>>> _loadNotifications() => switch (_role) {
        UserRole.client => authController.clientNotifications(),
        UserRole.trainer => authController.trainerNotifications(),
        UserRole.admin => authController.adminNotifications(),
        null => Future.value(const <Map<String, dynamic>>[]),
      };

  void _openNotification(Map<String, dynamic> notification) {
    final payload = notification['payload'] is Map
        ? Map<String, dynamic>.from(notification['payload'] as Map)
        : <String, dynamic>{};
    if (_role == UserRole.client &&
        notification['kind'] == 'new_phase_available') {
      context.push('/home/phase-available');
    } else if (_role == UserRole.admin &&
        notification['kind'] == 'account_deletion_requested') {
      context.push('/admin/requests');
    } else if (_role == UserRole.trainer &&
        notification['kind'] == 'client_activity' &&
        payload['client_id'] != null) {
      context.push(Uri(path: '/trainer/client', queryParameters: {
        'id': payload['client_id'].toString(),
        'name': notification['body'].toString().split(' completó').first,
      }).toString());
    }
  }

  Future<void> _confirmNotificationRead(
      Map<String, dynamic> notification) async {
    final id = notification['id'].toString();
    try {
      switch (_role) {
        case UserRole.client:
          await authController.markClientNotificationRead(notificationId: id);
        case UserRole.trainer:
          await authController.markTrainerNotificationRead(notificationId: id);
        case UserRole.admin:
          await authController.markAdminNotificationRead(notificationId: id);
        case null:
          return;
      }
      if (!mounted) return;
      setState(() => _notifications = _loadNotifications());
    } catch (error) {
      _showMessage('No se pudo quitar la notificación: $error');
    }
  }

  Future<void> _load() async {
    try {
      _pushNotificationsEnabled =
          await pushNotificationService.getPushNotificationsEnabled();
      if (_role == UserRole.client) {
        final values = await Future.wait([
          authController.clientDashboard(),
          authController.clientNotificationPreferences(),
        ]);
        _profile = values[0];
        _clientPreferences = Map<String, bool>.from(values[1]
            .map((key, value) => MapEntry(key.toString(), value == true)));
      } else if (_role == UserRole.trainer) {
        _profile = await authController.trainerProfile();
      } else if (_role == UserRole.admin) {
        final values = await Future.wait([
          authController.ownProfile(),
          authController.adminPreferences(),
        ]);
        _profile = values[0];
        _adminPreferences = values[1];
      }
      if (mounted) setState(() => _loading = false);
    } catch (error) {
      if (mounted) setState(() => _loading = false);
      _showMessage('No se pudieron cargar las preferencias: $error');
    }
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  bool get _pushEnabled => _pushNotificationsEnabled;

  Future<void> _setPush(bool enabled) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      if (_role == UserRole.client) {
        if (enabled) {
          await pushNotificationService.enablePushNotifications();
        } else {
          await pushNotificationService.disablePushNotifications();
        }
      } else {
        if (enabled) {
          await pushNotificationService.enablePushNotifications();
        } else {
          await pushNotificationService.disablePushNotifications();
        }
        _profile['push_notifications_enabled'] = enabled;
      }
      _pushNotificationsEnabled = enabled;
      if (mounted) setState(() {});
    } catch (error) {
      _showMessage('No se pudieron cambiar las notificaciones: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setClientReminder(bool enabled) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      if (enabled) {
        await pushNotificationService.enableClientReminders();
      } else {
        await pushNotificationService.disableClientReminders();
      }
      _profile['push_reminders_enabled'] = enabled;
      if (mounted) setState(() {});
    } catch (error) {
      _showMessage('No se pudo guardar el recordatorio: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setClientPreference(String key, bool enabled) async {
    if (_saving) return;
    final previous = Map<String, bool>.from(_clientPreferences);
    final updated = {...previous, key: enabled};
    setState(() {
      _saving = true;
      _clientPreferences = updated;
    });
    try {
      final saved = await authController.updateClientNotificationPreferences(
        routineUpdates: updated['routine_updates'] ?? true,
        accountUpdates: updated['account_updates'] ?? true,
      );
      if (mounted) {
        setState(() => _clientPreferences = Map<String, bool>.from(saved
            .map((key, value) => MapEntry(key.toString(), value == true))));
      }
    } catch (error) {
      _showMessage('No se guardó la preferencia: $error');
      if (mounted) setState(() => _clientPreferences = previous);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Map<String, bool> get _trainerPreferences => Map<String, bool>.from(
      _profile['notification_preferences'] as Map? ?? const {});

  Future<void> _setTrainerPreference(String key, bool value) async {
    if (_saving) return;
    final previous = _trainerPreferences;
    final updated = {..._trainerPreferences, key: value};
    setState(() {
      _saving = true;
      _profile['notification_preferences'] = updated;
    });
    try {
      final saved = await authController.updateTrainerProfile(
        firstName: (_profile['first_name'] ?? '').toString(),
        lastName: (_profile['last_name'] ?? '').toString(),
        email: (_profile['email'] ?? '').toString(),
        phone: (_profile['phone'] ?? '').toString(),
        specialty: (_profile['specialty'] ?? '').toString(),
        bio: (_profile['bio'] ?? '').toString(),
        notificationPreferences: updated,
      );
      if (mounted) setState(() => _profile = saved);
    } catch (error) {
      _showMessage('No se guardó la preferencia: $error');
      if (mounted) {
        setState(() => _profile['notification_preferences'] = previous);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setAdminPreference(String key, bool enabled) async {
    if (_saving) return;
    final updated = {..._adminPreferences, key: enabled};
    setState(() => _saving = true);
    try {
      final saved = await authController.updateAdminPreferences(
        newRequests: updated['new_requests'] != false,
        accountDeletions: updated['account_deletions'] != false,
      );
      if (mounted) setState(() => _adminPreferences = saved);
    } catch (error) {
      _showMessage('No se guardó la preferencia: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _switch(String title, String description, bool value,
          ValueChanged<bool>? onChanged, IconData icon) =>
      MusklCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(description,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch(
              value: value,
              activeThumbColor: AppColors.red,
              onChanged: _saving ? null : onChanged,
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final nav = switch (_role) {
      UserRole.client => _clientNav,
      UserRole.trainer => _trainerNav,
      UserRole.admin => _adminNav,
      null => _clientNav,
    };
    final selected = _role == UserRole.trainer ? 4 : 3;
    return WorkspacePage(
      title: 'Notificaciones',
      kicker: 'PREFERENCIAS',
      items: nav,
      selected: selected,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (_saving) const LinearProgressIndicator(),
              const Text(
                  'Consulta tus avisos y elige cuáles recibir en este teléfono.'),
              _section('Avisos recientes'),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _notifications,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError) {
                    return MusklCard(
                      child: Text(
                          'No se pudieron cargar los avisos: ${snapshot.error}'),
                    );
                  }
                  final notices = snapshot.data ?? const [];
                  if (notices.isEmpty) {
                    return const MusklCard(
                      child: Text('No tienes notificaciones nuevas.'),
                    );
                  }
                  return Column(
                    children: [
                      for (final notice in notices)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: MusklCard(
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                Icons.notifications_active_outlined,
                                color: AppColors.accent,
                              ),
                              title: Text(notice['title'].toString()),
                              subtitle: Text(notice['body'].toString()),
                              trailing: IconButton(
                                tooltip: 'Quitar notificación',
                                onPressed: _saving
                                    ? null
                                    : () => _confirmNotificationRead(notice),
                                icon: const Icon(Icons.close),
                              ),
                              onTap: () => _openNotification(notice),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
              _section('Preferencias de push'),
              const SizedBox(height: 12),
              _switch(
                'Notificaciones en este teléfono',
                'Activa o pausa todos los avisos push de MUSKL.',
                _pushEnabled,
                _setPush,
                Icons.notifications_active_outlined,
              ),
              if (_role == UserRole.client) ...[
                const SizedBox(height: 8),
                _switch(
                  'Recordatorio de rutina y racha',
                  'Aviso nocturno cuando tengas entrenamiento pendiente.',
                  _profile['push_reminders_enabled'] == true,
                  _setClientReminder,
                  Icons.local_fire_department_outlined,
                ),
                const SizedBox(height: 8),
                _switch(
                  'Cambios de rutina o entrenador',
                  'Cuando te asignen una rutina o publiquen una fase.',
                  _clientPreferences['routine_updates'] ?? true,
                  (value) => _setClientPreference('routine_updates', value),
                  Icons.fitness_center,
                ),
                const SizedBox(height: 8),
                _switch(
                  'Avisos de mi cuenta',
                  'Confirmaciones de cambios importantes de tu perfil.',
                  _clientPreferences['account_updates'] ?? true,
                  (value) => _setClientPreference('account_updates', value),
                  Icons.person_outline,
                ),
              ],
              if (_role == UserRole.trainer) ...[
                const SizedBox(height: 8),
                _switch(
                    'Actividad de clientes',
                    'Aviso cuando un socio termina una rutina.',
                    _trainerPreferences['client_activity'] ?? true,
                    (value) => _setTrainerPreference('client_activity', value),
                    Icons.fitness_center),
                const SizedBox(height: 8),
                _switch(
                    'Rutinas por vencer',
                    'Recordatorios sobre fases próximas a vencer.',
                    _trainerPreferences['routine_expiry'] ?? true,
                    (value) => _setTrainerPreference('routine_expiry', value),
                    Icons.event_repeat_outlined),
                const SizedBox(height: 8),
                _switch(
                    'Recordatorio diario',
                    'Resumen diario de actividad de tus clientes.',
                    _trainerPreferences['daily_reminder'] ?? false,
                    (value) => _setTrainerPreference('daily_reminder', value),
                    Icons.alarm_outlined),
              ],
              if (_role == UserRole.admin) ...[
                const SizedBox(height: 8),
                _switch(
                    'Nuevas solicitudes',
                    'Aviso cuando haya solicitudes de cuentas por revisar.',
                    _adminPreferences['new_requests'] != false,
                    (value) => _setAdminPreference('new_requests', value),
                    Icons.person_add_alt_outlined),
                const SizedBox(height: 8),
                _switch(
                    'Solicitudes de eliminación',
                    'Aviso cuando un socio solicite dar de baja su cuenta.',
                    _adminPreferences['account_deletions'] != false,
                    (value) => _setAdminPreference('account_deletions', value),
                    Icons.person_off_outlined),
              ],
            ]),
    );
  }
}

class AccessibilitySettingsScreen extends StatelessWidget {
  const AccessibilitySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final role = authController.session?.role;
    final nav = switch (role) {
      UserRole.client => _clientNav,
      UserRole.trainer => _trainerNav,
      UserRole.admin => _adminNav,
      null => _clientNav,
    };
    return WorkspacePage(
      title: 'Apariencia y texto',
      kicker: 'PERSONALIZA MUSKL',
      items: nav,
      selected: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _section('Tema de la app'),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: appThemeModeNotifier,
            builder: (context, mode, _) => MusklCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Elige cómo quieres ver MUSKL.'),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: _appearanceChoice(
                        label: 'Oscura',
                        icon: Icons.dark_mode_outlined,
                        selected: mode == ThemeMode.dark,
                        onTap: () => _setThemeMode(ThemeMode.dark),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _appearanceChoice(
                        label: 'Clara',
                        icon: Icons.light_mode_outlined,
                        selected: mode == ThemeMode.light,
                        onTap: () => _setThemeMode(ThemeMode.light),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  Row(children: [
                    _themePreviewSwatch(AppColors.bg, 'Fondo'),
                    const SizedBox(width: 8),
                    _themePreviewSwatch(AppColors.surface, 'Tarjetas'),
                    const SizedBox(width: 8),
                    _themePreviewSwatch(AppColors.red, 'Acento'),
                  ]),
                ],
              ),
            ),
          ),
          _section('Tamaño del texto'),
          ValueListenableBuilder<double>(
            valueListenable: appTextScaleNotifier,
            builder: (context, scale, _) => MusklCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Elige el tamaño que te resulte más cómodo.'),
                  const SizedBox(height: 10),
                  Row(children: [
                    for (final (index, option) in const [
                      (0.9, 'Pequeña'),
                      (1.0, 'Normal'),
                      (1.1, 'Grande'),
                    ].indexed) ...[
                      if (index > 0) const SizedBox(width: 8),
                      Expanded(
                        child: _appearanceChoice(
                          label: option.$2,
                          selected: (scale - option.$1).abs() < 0.01,
                          onTap: () => _setTextScale(option.$1),
                        ),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 10),
                  Text(
                    'Vista previa del texto',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void _setThemeMode(ThemeMode mode) {
  AppColors.isLightMode = mode == ThemeMode.light;
  appThemeModeNotifier.value = mode;
  unawaited(appPreferencesStorage.write(
    key: 'app_theme_mode',
    value: mode == ThemeMode.light ? 'light' : 'dark',
  ));
}

void _setTextScale(double scale) {
  appTextScaleNotifier.value = scale;
  unawaited(appPreferencesStorage.write(
    key: 'app_text_scale',
    value: scale.toString(),
  ));
}

Widget _appearanceChoice({
  required String label,
  IconData? icon,
  required bool selected,
  required VoidCallback onTap,
}) =>
    InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        constraints: const BoxConstraints(minHeight: 46),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.red.withValues(alpha: .14)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.red : AppColors.surfaceHigh,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 17,
                  color: selected ? AppColors.red : AppColors.textMuted),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? AppColors.red : AppColors.textMuted,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );

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
  ('Solicitudes', Icons.person_add_alt_1_outlined, '/trainer/requests'),
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

Widget _themePreviewSwatch(Color color, String label) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 28,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: AppColors.surfaceHigh),
            ),
          ),
          const SizedBox(height: 5),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
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
          SizedBox(width: 6),
          Text(label, style: TextStyle(color: AppColors.textMuted)),
        ],
      );
}

Widget _metric(String value, String label, {Color? color, Color? background}) {
  final foreground = color ?? AppColors.white;
  final fill = background ?? AppColors.surface;
  return Expanded(
    child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.surfaceHigh)),
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                  color: foreground)),
          const SizedBox(height: 4),
          Text(label.toUpperCase(),
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: fill.computeLuminance() > 0.28
                      ? AppColors.bgDeep.withValues(alpha: .78)
                      : AppColors.textMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: 11))
        ])),
  );
}

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
                      style:
                          TextStyle(color: AppColors.textMuted, fontSize: 13))
                ])),
            if (badge != null)
              Text(badge,
                  style: TextStyle(
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
                style: TextStyle(
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

Future<void> _openGymWhatsApp(BuildContext context, String phone) async {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return;
  final internationalNumber = digits.startsWith('52') ? digits : '52$digits';
  final uri = Uri.https('wa.me', '/$internationalNumber');
  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No se pudo abrir WhatsApp en este dispositivo.'),
      ));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No se pudo abrir WhatsApp en este dispositivo.'),
      ));
    }
  }
}

Widget _profileBioInline(String value) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.notes_outlined, color: AppColors.accent, size: 16),
            const SizedBox(width: 6),
            Expanded(
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

Widget _compactProfileMeta(String label, String value, IconData icon) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceHigh),
      ),
      child: Row(children: [
        Icon(icon, color: AppColors.accent, size: 17),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .5)),
              const SizedBox(height: 3),
              Text(value.isEmpty ? 'Sin información' : value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ]),
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
                fit: StackFit.expand,
                children: [
                  Image.asset('assets/images/splash.jpg',
                      fit: BoxFit.cover, cacheWidth: 360),
                  Container(color: AppColors.bgDeep.withValues(alpha: .48)),
                  Icon(
                    (exercise['media_mime'] ?? '')
                            .toString()
                            .startsWith('video/')
                        ? Icons.play_circle_outline
                        : Icons.fitness_center,
                    color: AppColors.white,
                    size: 30,
                  ),
                ],
              )
            : Image.network(
                exercise['media_url'].toString(),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: AppColors.bg,
                  alignment: Alignment.center,
                  child: const Icon(Icons.fitness_center,
                      color: AppColors.red, size: 30),
                ),
              ),
      ),
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
          final error = snapshot.error;
          final message = error is AuthException
              ? error.message
              : error?.toString() ?? 'Error desconocido.';
          return Scaffold(
              body: Center(
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_off_outlined,
                              size: 42, color: AppColors.red),
                          const SizedBox(height: 12),
                          const Text('No se pudo cargar tu información',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          Text(message,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppColors.red)),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: () => setState(() =>
                                _dashboard = authController.clientDashboard()),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Reintentar'),
                          ),
                        ],
                      ))));
        }
        final data = snapshot.data ?? {};
        return WorkspacePage(
          title: 'Inicio',
          items: _clientNav,
          selected: 0,
          onRefresh: () async {
            final next = authController.clientDashboard();
            setState(() => _dashboard = next);
            await next;
          },
          child: ClientHomeContent(
              data: data, onNavigate: (route) => context.push(route)),
        );
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
                                      style: TextStyle(
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
  String? _historyPhaseId;
  final Stopwatch _workoutClock = Stopwatch();
  final FlutterTts _speech = FlutterTts();
  final Set<String> _completedExerciseIds = {};
  Timer? _ticker;
  int _nextEncouragementSeconds = 5 * 60;
  int _encouragementIndex = 0;
  bool _isForeground = true;
  bool _workoutFinished = false;
  bool _saving = false;
  bool _encouragementVisible = false;
  String _activeEncouragement = '';

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
      _stopEncouragementSpeech();
    }
  }

  void _tick() {
    if (!_isForeground || _workoutFinished) return;
    final elapsed = _workoutClock.elapsed.inSeconds;
    if (elapsed >= _nextEncouragementSeconds) {
      _nextEncouragementSeconds += 5 * 60;
      _showEncouragement();
    }
  }

  void _showEncouragement() {
    final message =
        _encouragements[_encouragementIndex % _encouragements.length];
    _encouragementIndex++;
    HapticFeedback.mediumImpact();
    if (mounted) {
      setState(() {
        _activeEncouragement = message;
        _encouragementVisible = true;
      });
      Future<void>.delayed(const Duration(seconds: 5), () {
        if (mounted && _activeEncouragement == message) {
          setState(() => _encouragementVisible = false);
        }
      });
    }
    _playEncouragement(message);
  }

  Future<void> _playEncouragement(String message) async {
    try {
      if (_isForeground) await _speech.speak(message);
    } catch (_) {
      // Speech is optional; never interrupt the exercise flow.
    }
  }

  Future<void> _stopEncouragementSpeech() async {
    try {
      await _speech.stop();
    } catch (_) {}
  }

  void _load() {
    final phaseId = _historyPhaseId;
    _routine = phaseId == null
        ? authController.clientRoutine(day: _day)
        : authController.clientHistoricalRoutine(phaseId: phaseId, day: _day);
  }

  Future<void> _openRoutineHistory() async {
    try {
      final history = await authController.clientRoutineHistory();
      if (!mounted) return;
      if (history.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Todavía no hay rutinas o fases anteriores en tu historial.'),
        ));
        return;
      }
      final selected = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: .65,
            minChildSize: .35,
            maxChildSize: .9,
            builder: (context, controller) => ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              children: [
                const ListTile(
                  leading: Icon(Icons.history, color: AppColors.red),
                  title: Text('Rutinas y fases anteriores'),
                  subtitle: Text(
                      'Consulta los ejercicios sin modificar tu progreso actual.'),
                ),
                for (final item in history)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.surfaceHigh,
                      child: Icon(
                        item['earlier_phase_of_current_routine'] == true
                            ? Icons.layers_outlined
                            : Icons.fitness_center,
                        color: AppColors.accent,
                      ),
                    ),
                    title: Text(item['routine_name'].toString()),
                    subtitle: Text(
                      '${item['phase_name']} · Fase ${item['phase_number']} · '
                      '${item['completed_workouts'] ?? 0} sesiones registradas'
                      '${item['last_workout_date'] == null ? '' : ' · Última: ${item['last_workout_date']}'}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(sheetContext, item),
                  ),
              ],
            ),
          ),
        ),
      );
      if (selected == null || !mounted) return;
      setState(() {
        _historyPhaseId = selected['phase_id'].toString();
        _completedExerciseIds.clear();
        _load();
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo cargar el historial: $error'),
        ));
      }
    }
  }

  void _showCurrentRoutine() {
    setState(() {
      _historyPhaseId = null;
      _completedExerciseIds.clear();
      _load();
    });
  }

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
      final dayNumber =
          int.tryParse((data['scheduled_day_number'] ?? _day).toString()) ??
              _day;
      final completion = await authController.completeClientWorkout(
          durationSeconds: durationSeconds, dayNumber: dayNumber);
      _workoutFinished = true;
      _workoutClock.stop();
      await _stopEncouragementSpeech();
      if (mounted) {
        context.push(Uri(path: '/home/complete', queryParameters: {
          'exercise_count': completion['exercise_count'].toString(),
          'sessions_this_week':
              completion['sessions_this_week']?.toString() ?? '1',
          'sessions_total': completion['sessions_total']?.toString() ?? '1',
          'fully_completed':
              completio…49233 tokens truncated…                  borderRadius:
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
                      onTap: () => context.push('/admin/users')),
                  _record('Solicitudes', 'Aprobar o rechazar cuentas',
                      icon: Icons.fact_check_outlined,
                      badge: pending == 0 ? null : '$pending',
                      onTap: () => context.push('/admin/requests')),
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

  Widget _userRecord(Map<String, dynamic> user) {
    final role = user['role']?.toString().toLowerCase();
    final status = user['status']?.toString().toLowerCase();
    return _record(
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
              user['trainer_reassignment_required'] == true ? 'true' : 'false',
          'reactivation_until': user['reactivation_until']?.toString() ?? '',
          'profile_photo_url': (user['profile_photo_url'] ?? '').toString(),
        }).toString());
        if (changed == true && mounted) setState(_reload);
      },
    );
  }

  @override
  Widget build(BuildContext context) => WorkspacePage(
      title: 'Usuarios',
      items: _adminNav,
      selected: 1,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _SearchField(
            hint: 'Buscar por nombre o correo',
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

  Future<void> _deleteRoutine(Map<String, dynamic> routine) async {
    final assigned = (routine['assigned_clients'] as num?)?.toInt() ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar rutina'),
        content: Text(assigned == 0
            ? 'La rutina dejará de aparecer en el catálogo. Sus fases e historial se conservarán.'
            : 'Hay $assigned socios con esta rutina. Se les quitará la rutina activa y se conservará su historial. La rutina dejará de aparecer en el catálogo.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await authController.deleteAdminRoutine(
          routineId: routine['id'].toString());
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rutina eliminada del catálogo.')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo eliminar la rutina: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => WorkspacePage(
      title: 'Rutinas',
      items: _adminNav,
      selected: 2,
      showAppBar: false,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _routines,
        builder: (context, snapshot) {
          final rows = snapshot.data ?? [];
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _routineListHeader(
                    context: context,
                    count: snapshot.connectionState == ConnectionState.waiting
                        ? 'CARGANDO'
                        : '${rows.length} ACTIVAS',
                    title: 'Rutinas',
                    createRoute: '/admin/routine/new'),
                _SearchField(
                    hint: 'Buscar rutina',
                    onChanged: (v) => setState(() {
                          search = v;
                          _reload();
                        })),
                const SizedBox(height: 4),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final option in [
                      'Todas',
                      'Bajar de peso',
                      'Masa muscular',
                      'Resistencia',
                      'Fuerza'
                    ]) ...[
                      FilterChip(
                        label: Text(option),
                        selected: filter == option,
                        onSelected: (_) => setState(() {
                          filter = option;
                          _reload();
                        }),
                      ),
                      const SizedBox(width: 5),
                    ],
                  ]),
                ),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (snapshot.hasError)
                  Text('No se pudieron cargar las rutinas: ${snapshot.error}',
                      style: const TextStyle(color: AppColors.red))
                else if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 20),
                    child: Text('No hay rutinas registradas.'),
                  )
                else
                  for (final routine in rows)
                    _routineVisualCard(
                      name: routine['name'].toString(),
                      goal: routine['goal'].toString(),
                      days: routine['days_per_week'] ?? '—',
                      clients: routine['assigned_clients'] ?? 0,
                      onTap: () => context
                          .push(Uri(path: '/admin/routine', queryParameters: {
                        'id': routine['id'].toString(),
                        'name': routine['name'].toString(),
                      }).toString()),
                      action: PopupMenuButton<String>(
                        tooltip: 'Acciones de rutina',
                        padding: EdgeInsets.zero,
                        iconSize: 17,
                        icon: Icon(Icons.more_vert, color: AppColors.white),
                        onSelected: (action) {
                          if (action == 'open') {
                            context.push(
                                Uri(path: '/admin/routine', queryParameters: {
                              'id': routine['id'].toString(),
                              'name': routine['name'].toString(),
                            }).toString());
                          } else if (action == 'delete') {
                            _deleteRoutine(routine);
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                              value: 'open', child: Text('Abrir rutina')),
                          PopupMenuItem(
                              value: 'delete', child: Text('Eliminar rutina')),
                        ],
                      ),
                    ),
              ]);
        },
      ));
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

  Future<void> _deleteRoutine() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar rutina'),
        content: const Text(
            'La rutina dejará de aparecer en el catálogo y se cerrarán sus asignaciones activas. El historial de entrenamiento se conservará.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await authController.deleteAdminRoutine(routineId: widget.routineId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rutina eliminada del catálogo.')));
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo eliminar la rutina: $error')));
      }
    }
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
              const ListTile(title: Text('ASIGNAR O CAMBIAR RUTINA')),
              for (final item in clients)
                ListTile(
                  title: Text('${item['first_name']} ${item['last_name']}'),
                  subtitle: Text(
                    (item['routine_name'] ?? '').toString().trim().isEmpty
                        ? 'Socio ${item['member_number'] ?? ''} · Sin rutina actual'
                        : 'Socio ${item['member_number'] ?? ''} · Rutina actual: ${item['routine_name']}',
                  ),
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
              'Rutina asignada a ${client['first_name']}. Su rutina anterior quedó en el historial.')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo asignar la rutina: $error')));
      }
    }
  }

  Future<void> _publishPhase(Map<String, dynamic> phase) async {
    try {
      await authController.publishAdminPhase(
        routineId: widget.routineId,
        phaseId: phase['id'].toString(),
      );
      if (!mounted) return;
      setState(() =>
          _routine = authController.adminRoutine(routineId: widget.routineId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fase publicada para asignar.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo publicar la fase: $error')),
        );
      }
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
              .map((phase) => Map<String, dynamic>.from(phase as Map))
              .toList();
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
                              style: TextStyle(color: AppColors.textMuted))
                        ])),
                _section('Fases'),
                for (final phase in phases)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: MusklCard(
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: EdgeInsets.zero,
                        title: Text(
                            '${phase['name']} · Fase ${phase['phase_number']}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w900)),
                        subtitle: Text(
                            '${phase['status'] == 'published' ? 'Publicada' : 'Borrador'} · ${phase['duration_weeks']} semanas · ${phase['exercise_count']} ejercicios'),
                        children: [
                          for (var day = 1; day <= 7; day++)
                            if (exercises.any((exercise) =>
                                exercise['phase_number'] ==
                                    phase['phase_number'] &&
                                (exercise['day_number'] as num).toInt() == day))
                              ExpansionTile(
                                tilePadding: EdgeInsets.zero,
                                title: Text(_weekDays[day - 1]),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: LayoutBuilder(
                                      builder: (context, constraints) {
                                        final tileWidth =
                                            (constraints.maxWidth - 10) / 2;
                                        return Wrap(
                                          spacing: 10,
                                          runSpacing: 10,
                                          children: [
                                            for (final exercise
                                                in exercises.where((exercise) =>
                                                    exercise['phase_number'] ==
                                                        phase['phase_number'] &&
                                                    (exercise['day_number']
                                                                as num)
                                                            .toInt() ==
                                                        day))
                                              SizedBox(
                                                width: tileWidth,
                                                child: MusklCard(
                                                  padding:
                                                      const EdgeInsets.all(9),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      _exerciseThumbnail(
                                                          exercise,
                                                          height: 82),
                                                      const SizedBox(height: 7),
                                                      Text(
                                                          exercise['name']
                                                              .toString(),
                                                          maxLines: 2,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: const TextStyle(
                                                              fontSize: 12,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800)),
                                                      const SizedBox(height: 5),
                                                      Text(
                                                          '${exercise['sets']} series · ${exercise['reps']} reps · ${exercise['rest_seconds']}s',
                                                          maxLines: 2,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                              color: AppColors
                                                                  .textMuted,
                                                              fontSize: 10)),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final changed = await context.push<bool>(Uri(
                                    path: '/admin/phase/new',
                                    queryParameters: {
                                      'routine_id': widget.routineId,
                                      'phase_id': phase['id'].toString(),
                                    },
                                  ).toString());
                                  if (changed == true && mounted) {
                                    setState(() => _routine =
                                        authController.adminRoutine(
                                            routineId: widget.routineId));
                                  }
                                },
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('Editar fase'),
                              ),
                              if (phase['status'] != 'published')
                                OutlinedButton.icon(
                                  onPressed: () => _publishPhase(phase),
                                  icon: const Icon(Icons.publish),
                                  label: const Text('Publicar'),
                                ),
                              if (phase['status'] == 'published')
                                OutlinedButton.icon(
                                  onPressed: () => _assignToClient(phase),
                                  icon: const Icon(Icons.person_add_alt_1),
                                  label: const Text('Asignar a socio'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                if (phases.isNotEmpty && phases.last['status'] == 'published')
                  OutlinedButton.icon(
                    onPressed: () => context.push(Uri(
                      path: '/admin/phase/new',
                      queryParameters: {'routine_id': widget.routineId},
                    ).toString()),
                    icon: const Icon(Icons.add),
                    label: const Text('Crear siguiente fase'),
                  ),
                _section('Clientes asignados'),
                for (final client in clients)
                  _record('${client['first_name']} ${client['last_name']}',
                      'Socio ${client['member_number']}'),
                if (clients.isEmpty) const Text('Sin clientes asignados.'),
                const SizedBox(height: 18),
                MusklButton(
                  label: 'Eliminar rutina',
                  icon: Icons.delete_outline,
                  style: MusklButtonStyle.secondary,
                  onPressed: _deleteRoutine,
                ),
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
  bool _accountDeletionNotifications = true;
  bool _pushNotificationsEnabled = false;
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
      if (mounted) {
        setState(() {
          _ownProfile = profile;
          _pushNotificationsEnabled =
              profile['push_notifications_enabled'] == true;
        });
      }
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

  Future<void> _editAdminProfile() async {
    final values = await _editProfileFields(context, 'DATOS PERSONALES', [
      'Nombre',
      'Apellidos',
    ], [
      (_ownProfile['first_name'] ?? '').toString(),
      (_ownProfile['last_name'] ?? '').toString(),
    ]);
    if (!mounted || values == null) return;
    try {
      final profile = await authController.updateOwnProfile(
          firstName: values[0],
          lastName: values[1],
          phone: (_ownProfile['phone'] ?? '').toString(),
          bio: (_ownProfile['bio'] ?? '').toString());
      if (mounted) {
        setState(() => _ownProfile = {
              ...profile,
              'profile_photo_url': _ownProfile['profile_photo_url']
            });
        _showLocalMessage('Perfil actualizado.');
      }
    } catch (e) {
      _showLocalMessage('No se pudo actualizar el perfil: $e');
    }
  }

  Future<void> _editAdminBio() async {
    final values = await _editProfileFields(
      context,
      'EDITAR BIOGRAFÍA',
      ['Cuéntanos sobre ti'],
      [(_ownProfile['bio'] ?? '').toString()],
      multiline: const {0},
    );
    if (!mounted || values == null) return;
    try {
      final profile = await authController.updateOwnProfile(
        firstName: (_ownProfile['first_name'] ?? '').toString(),
        lastName: (_ownProfile['last_name'] ?? '').toString(),
        phone: (_ownProfile['phone'] ?? '').toString(),
        bio: values.first,
      );
      if (mounted) setState(() => _ownProfile = profile);
      _showLocalMessage('Biografía actualizada.');
    } catch (e) {
      _showLocalMessage('No se pudo actualizar la biografía: $e');
    }
  }

  Future<void> _editAdminPhone() async {
    final values = await _editProfileFields(
      context,
      'EDITAR TELÉFONO',
      ['Teléfono'],
      [(_ownProfile['phone'] ?? '').toString()],
    );
    if (!mounted || values == null) return;
    try {
      final profile = await authController.updateOwnProfile(
        firstName: (_ownProfile['first_name'] ?? '').toString(),
        lastName: (_ownProfile['last_name'] ?? '').toString(),
        phone: values.first,
        bio: (_ownProfile['bio'] ?? '').toString(),
      );
      if (mounted) setState(() => _ownProfile = profile);
      _showLocalMessage('Teléfono actualizado.');
    } catch (e) {
      _showLocalMessage('No se pudo actualizar el teléfono: $e');
    }
  }

  Future<void> _openProfileEditMenu() async {
    final field = await _chooseProfileField(context, [
      const _ProfileEditOption(
        key: 'photo',
        title: 'Foto de perfil',
        value: 'Elegir una foto nueva',
        icon: Icons.camera_alt_outlined,
      ),
      _ProfileEditOption(
        key: 'name',
        title: 'Nombre',
        value:
            '${_ownProfile['first_name'] ?? ''} ${_ownProfile['last_name'] ?? ''}'
                .trim(),
        icon: Icons.person_outline,
      ),
      _ProfileEditOption(
        key: 'email',
        title: 'Correo electrónico',
        value: (_ownProfile['email'] ?? '').toString(),
        icon: Icons.mail_outline,
      ),
      _ProfileEditOption(
        key: 'phone',
        title: 'Teléfono',
        value: (_ownProfile['phone'] ?? '').toString(),
        icon: Icons.phone_outlined,
      ),
      _ProfileEditOption(
        key: 'bio',
        title: 'Biografía',
        value: (_ownProfile['bio'] ?? '').toString(),
        icon: Icons.notes_outlined,
      ),
    ]);
    if (!mounted || field == null) return;
    switch (field) {
      case 'photo':
        await _changeAdminPhoto();
        return;
      case 'name':
        await _editAdminProfile();
        return;
      case 'email':
        await _changeAdminEmail();
        return;
      case 'phone':
        await _editAdminPhone();
        return;
      case 'bio':
        await _editAdminBio();
        return;
    }
  }

  Future<void> _changeAdminEmail() async {
    final changed = await context.push<bool>(Uri(
      path: '/admin/email',
      queryParameters: {'email': (_ownProfile['email'] ?? '').toString()},
    ).toString());
    if (changed == true && mounted) await _loadOwnProfile();
  }

  Future<void> _loadAdminPreferences() async {
    try {
      final preferences = await authController.adminPreferences();
      if (!mounted) return;
      setState(() {
        _newRequestNotifications = preferences['new_requests'] != false;
        _accountDeletionNotifications =
            preferences['account_deletions'] != false;
      });
    } catch (e) {
      if (mounted) _showLocalMessage('No se cargaron las preferencias: $e');
    }
  }

  Future<void> _setNewRequestNotifications(bool enabled) async {
    if (_savingPreferences) return;
    setState(() => _savingPreferences = true);
    try {
      final saved = await authController.updateAdminPreferences(
        newRequests: enabled,
        accountDeletions: _accountDeletionNotifications,
      );
      if (!mounted) return;
      setState(() {
        _newRequestNotifications = saved['new_requests'] != false;
        _accountDeletionNotifications = saved['account_deletions'] != false;
      });
    } catch (e) {
      if (mounted) _showLocalMessage('No se guardó la preferencia: $e');
    } finally {
      if (mounted) setState(() => _savingPreferences = false);
    }
  }

  Future<void> _setAdminPushNotifications(bool enabled) async {
    if (_savingPreferences) return;
    setState(() => _savingPreferences = true);
    try {
      if (enabled) {
        await pushNotificationService.enablePushNotifications();
      } else {
        await pushNotificationService.disablePushNotifications();
      }
      if (mounted) {
        setState(() => _pushNotificationsEnabled = enabled);
        _showLocalMessage(enabled
            ? 'Notificaciones push activadas en este teléfono.'
            : 'Notificaciones push desactivadas.');
      }
    } catch (e) {
      if (mounted) {
        _showLocalMessage('No se pudieron cambiar las notificaciones: $e');
      }
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
              allowEdit: false,
              onEdit: () {}),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                    '${_ownProfile['first_name'] ?? ''} ${_ownProfile['last_name'] ?? ''}'
                        .trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 17)),
                Text((_ownProfile['email'] ?? '').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                Text(
                    (_ownProfile['phone'] ?? '').toString().isEmpty
                        ? 'Sin teléfono'
                        : _ownProfile['phone'].toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                _profileBioInline((_ownProfile['bio'] ?? '').toString()),
              ])),
          IconButton(
            tooltip: 'Editar perfil',
            onPressed: _savingPhoto ? null : _openProfileEditMenu,
            icon: const Icon(Icons.edit_outlined),
          ),
        ])),
        _setting('Notificaciones', 'Elige qué avisos recibir',
            Icons.notifications_active_outlined,
            onTap: () =>
                context.push(_notificationsPath(authController.session?.role))),
        _setting('Apariencia y texto', 'Tema y tamaño de letra',
            Icons.text_fields_outlined,
            onTap: () =>
                context.push(_accessibilityPath(authController.session?.role))),
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
  bool _showDeletions = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _requests = authController.staffRequests();
    _deletionRequests = authController.accountDeletionRequests();
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
                                  style: TextStyle(color: AppColors.textMuted)),
                            if (_showDeletions &&
                                request['note'] != null &&
                                request['note'].toString().isNotEmpty)
                              Text('Motivo: ${request['note']}'),
                            if (!_showDeletions && request['specialty'] != null)
                              Text('Especialidad: ${request['specialty']}',
                                  style: TextStyle(color: AppColors.textMuted)),
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'core/router.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/api_auth_repository.dart';
import 'features/notifications/push_notification_service.dart';

/// Permite cambiar el backend al compilar mediante MUSKL_API_URL.
const _apiUrl = String.fromEnvironment(
  'MUSKL_API_URL',
  defaultValue: 'https://muskl-api.onrender.com',
);
final apiAuthRepository = ApiAuthRepository(_apiUrl);
final pushNotificationService = PushNotificationService(apiAuthRepository);
final authController = AuthController(apiAuthRepository);
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
final appTextScaleNotifier = ValueNotifier<double>(1.0);
final appThemeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.dark);
const appPreferencesStorage = FlutterSecureStorage();
void _connectSessionUpdates() {
  apiAuthRepository.onSessionChanged = (session) {
    authController.updateSessionFromRepository(session);
    unawaited(pushNotificationService.syncSession(session));
  };
}

void main() {
  runApp(const MusklApp());
}

class MusklApp extends StatefulWidget {
  const MusklApp({super.key});

  @override
  State<MusklApp> createState() => _MusklAppState();
}

class _MusklAppState extends State<MusklApp> {
  final _router = buildRouter(authController);
  StreamSubscription<(String, String)>? _pushSubscription;

  @override
  void initState() {
    super.initState();
    _connectSessionUpdates();
    unawaited(_restorePreferences());
    _pushSubscription = pushNotificationService.foregroundNotifications.listen(
      (notification) => rootScaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('${notification.$1}\n${notification.$2}')),
      ),
    );
  }

  Future<void> _restorePreferences() async {
    final values = await Future.wait([
      appPreferencesStorage.read(key: 'app_text_scale'),
      appPreferencesStorage.read(key: 'app_theme_mode'),
    ]);
    final scale = double.tryParse(values[0] ?? '');
    if (scale != null && scale >= 1 && scale <= 1.25) {
      appTextScaleNotifier.value = scale;
    }
    if (values[1] == 'light') appThemeModeNotifier.value = ThemeMode.light;
  }

  @override
  void dispose() {
    _pushSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
        valueListenable: appThemeModeNotifier,
        builder: (context, themeMode, _) {
          AppColors.isLightMode = themeMode == ThemeMode.light;
          return ValueListenableBuilder<double>(
            valueListenable: appTextScaleNotifier,
            builder: (context, textScale, _) => MaterialApp.router(
              title: 'MUSKL',
              debugShowCheckedModeBanner: false,
              scaffoldMessengerKey: rootScaffoldMessengerKey,
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              themeMode: themeMode,
              routerConfig: _router,
              builder: (context, child) {
                final media = MediaQuery.of(context);
                final systemScale = media.textScaler.scale(1);
                final effectiveScale =
                    systemScale > textScale ? systemScale : textScale;
                return MediaQuery(
                  data: media.copyWith(
                    textScaler: TextScaler.linear(effectiveScale),
                  ),
                  child: child ?? const SizedBox.shrink(),
                );
              },
            ),
          );
        });
  }
}

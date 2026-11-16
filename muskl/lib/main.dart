import 'package:flutter/material.dart';

import 'core/router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/api_auth_repository.dart';

/// Permite cambiar el backend al compilar mediante MUSKL_API_URL.
const _apiUrl = String.fromEnvironment(
  'MUSKL_API_URL',
  defaultValue: 'https://muskl-api.onrender.com',
);
final apiAuthRepository = ApiAuthRepository(_apiUrl);
final authController = AuthController(apiAuthRepository);
void _connectSessionUpdates() {
  apiAuthRepository.onSessionChanged =
      authController.updateSessionFromRepository;
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

  @override
  void initState() {
    super.initState();
    _connectSessionUpdates();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'MUSKL',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      routerConfig: _router,
    );
  }
}

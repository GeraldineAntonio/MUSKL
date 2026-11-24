import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../auth/api_auth_repository.dart';
import '../auth/auth_models.dart';

/// FCM is optional until the Firebase app values are supplied at build time.
/// This keeps the rest of the app usable in local/demo builds.
class PushNotificationService {
  PushNotificationService(this._repository);

  final ApiAuthRepository _repository;
  Future<bool>? _initializing;
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;
  final _foregroundNotifications =
      StreamController<(String, String)>.broadcast();

  Stream<(String, String)> get foregroundNotifications =>
      _foregroundNotifications.stream;

  static const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const _senderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const _iosBundleId = String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID');

  bool get isConfigured =>
      _apiKey.isNotEmpty &&
      _appId.isNotEmpty &&
      _senderId.isNotEmpty &&
      _projectId.isNotEmpty;

  Future<bool> _initialize() async {
    if (!isConfigured) return false;
    final running = _initializing;
    if (running != null) return running;
    final task = _initializeFirebase();
    _initializing = task;
    try {
      return await task;
    } finally {
      _initializing = null;
    }
  }

  Future<bool> _initializeFirebase() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: FirebaseOptions(
            apiKey: _apiKey,
            appId: _appId,
            messagingSenderId: _senderId,
            projectId: _projectId,
            iosBundleId: _iosBundleId.isEmpty ? null : _iosBundleId,
          ),
        );
      }
      _tokenSubscription ??= FirebaseMessaging.instance.onTokenRefresh.listen(
        (token) => unawaited(_refreshToken(token)),
      );
      _messageSubscription ??= FirebaseMessaging.onMessage.listen((message) {
        final notification = message.notification;
        if (notification == null) return;
        _foregroundNotifications.add((
          notification.title ?? 'MUSKL',
          notification.body ?? 'Tienes un recordatorio de entrenamiento.',
        ));
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> syncSession(Session? session) async {
    if (session?.role != UserRole.client || !await _initialize()) return;
    try {
      final enabled = await _repository.getClientPushReminders();
      if (!enabled) return;
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) await _saveToken(token);
    } catch (_) {
      // Push setup should never prevent login or session restoration.
    }
  }

  Future<void> enableClientReminders() async {
    if (!isConfigured || !await _initialize()) {
      throw const AuthException(
        AuthErrorType.server,
        'Faltan los datos de Firebase para activar notificaciones push.',
      );
    }
    final permission = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (permission.authorizationStatus != AuthorizationStatus.authorized &&
        permission.authorizationStatus != AuthorizationStatus.provisional) {
      throw const AuthException(
        AuthErrorType.server,
        'Permite las notificaciones de MUSKL en los ajustes del teléfono.',
      );
    }
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) {
      throw const AuthException(
        AuthErrorType.server,
        'No se pudo registrar este teléfono para recibir notificaciones.',
      );
    }
    await _saveToken(token);
    await _repository.setClientPushReminders(true);
  }

  Future<void> disableClientReminders() =>
      _repository.setClientPushReminders(false);

  Future<void> _refreshToken(String token) async {
    try {
      if (await _repository.getClientPushReminders()) await _saveToken(token);
    } catch (_) {}
  }

  Future<void> _saveToken(String token) => _repository.registerClientPushToken(
        token: token,
        platform: defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
      );
}

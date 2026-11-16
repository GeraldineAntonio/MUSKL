import 'package:google_sign_in/google_sign_in.dart';

/// Retry only the native stale-account failure, never an ordinary cancellation.
Future<T> recoverGoogleAuthentication<T>({
  required Future<T> Function() authenticate,
  required Future<void> Function() clearSession,
}) async {
  try {
    return await authenticate();
  } on GoogleSignInException catch (error) {
    if (!(error.description ?? '').toLowerCase().contains('account reauth failed')) {
      rethrow;
    }
    await clearSession();
    return authenticate();
  }
}

String googleSignInMessage(GoogleSignInException error) {
  if ((error.description ?? '').toLowerCase().contains('account reauth failed')) {
    return 'Google no pudo verificar tu cuenta. Prueba otra cuenta o entra con tu correo y contraseña.';
  }
  return switch (error.code) {
    GoogleSignInExceptionCode.canceled => 'No se completó el acceso con Google. Puedes intentarlo otra vez o usar tu correo.',
    GoogleSignInExceptionCode.clientConfigurationError => 'El acceso con Google no está disponible en esta versión. Puedes entrar con tu correo y contraseña.',
    GoogleSignInExceptionCode.providerConfigurationError => 'Revisa que los servicios de Google Play estén actualizados e intenta de nuevo.',
    _ => 'No pudimos conectar con Google. Intenta de nuevo o entra con tu correo y contraseña.',
  };
}

class GoogleAuth {
  static Future<void>? _initialization;

  static Future<void> initialize(String clientId) async {
    try {
      await (_initialization ??= GoogleSignIn.instance.initialize(serverClientId: clientId));
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }
}

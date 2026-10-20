enum UserRole { client, trainer, admin }

/// Estado de la cuenta, siempre decidido por el backend (nunca por la app).
enum AccountStatus {
  activeNoOnboarding,
  activeOnboarded,
  pending, // entrenador/admin esperando aprobación
  rejected,
  deactivated, // dado de baja por un admin
}

class Session {
  const Session({
    required this.role,
    required this.status,
    this.userId,
    this.memberNumber,
    this.reason,
    this.deactivatedAt,
    this.deactivatedBy,
    this.reactivationUntil,
  });

  final UserRole role;
  final AccountStatus status;
  final String? userId;
  final String? memberNumber;

  /// Motivo de rechazo o de baja.
  final String? reason;
  final DateTime? deactivatedAt;
  final String? deactivatedBy;
  final DateTime? reactivationUntil;
}

enum AuthErrorType {
  invalidCredentials,
  notFound,
  offline,
  invalidCode,
  emailNotVerified,
  server
}

class AuthException implements Exception {
  const AuthException(this.type, [this._detail]) : code = null;
  const AuthException.withCode(this.type, this._detail, {this.code});
  final AuthErrorType type;
  final String? _detail;
  final String? code;

  String get message =>
      _detail ??
      switch (type) {
        AuthErrorType.invalidCredentials => 'Correo o contraseña incorrectos.',
        AuthErrorType.notFound => 'No encontramos una cuenta con esos datos.',
        AuthErrorType.offline =>
          'Sin conexión. Revisa tu internet e intenta de nuevo.',
        AuthErrorType.invalidCode => 'El código es incorrecto o ya venció.',
        AuthErrorType.emailNotVerified =>
          'Verifica tu correo antes de iniciar sesión.',
        AuthErrorType.server => 'Ocurrió un error. Intenta de nuevo.',
      };
}

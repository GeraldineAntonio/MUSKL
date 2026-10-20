import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:go_router/go_router.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/muskl_button.dart';
import '../../core/widgets/muskl_text_field.dart';
import '../../main.dart';
import 'auth_models.dart';
import 'widgets/auth_scaffold.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _googleServerClientId = String.fromEnvironment(
    'MUSKL_GOOGLE_SERVER_CLIENT_ID',
    defaultValue:
        '355323290179-5t96b3a4efp9lqju4dvt4hk3vu11m1m4.apps.googleusercontent.com',
  );
  static const _appleServiceId =
      String.fromEnvironment('MUSKL_APPLE_SERVICE_ID');
  static const _appleRedirectUri =
      String.fromEnvironment('MUSKL_APPLE_REDIRECT_URI');

  final _id = TextEditingController();
  final _pass = TextEditingController();
  Future<void>? _googleInitialization;
  bool _loading = false;
  String? _error;
  AuthErrorType? _errorType;

  @override
  void dispose() {
    _id.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_id.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() {
        _errorType = null;
        _error = 'Escribe tu correo o número de socio y tu contraseña.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _errorType = null;
    });
    try {
      // El router redirige solo según el estado de la cuenta.
      await authController.signIn(_id.text, _pass.text);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _errorType = e.type;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error =
            'No se pudo iniciar sesión. Revisa la conexión e intenta de nuevo.';
        _errorType = AuthErrorType.offline;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resendVerification() async {
    final email = _id.text.trim().toLowerCase();
    if (!email.contains('@')) return;
    setState(() => _loading = true);
    try {
      await authController.resendRegistrationEmailCode(email);
      if (mounted) {
        context.go(Uri(path: '/verify-email', queryParameters: {'email': email})
            .toString());
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInGoogle() async {
    if (_googleServerClientId.isEmpty) {
      setState(() => _error =
          'Falta configurar el acceso de Google para esta versión de MUSKL.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _errorType = null;
    });
    String? googleIdentityToken;
    var googleEmail = '';
    var googleName = '';
    try {
      final google = GoogleSignIn.instance;
      _googleInitialization ??=
          google.initialize(serverClientId: _googleServerClientId);
      await _googleInitialization;
      final account = await google.authenticate();
      final token = account.authentication.idToken;
      if (token == null || token.isEmpty) {
        throw const AuthException(
            AuthErrorType.server, 'Google no devolvió un token de acceso.');
      }
      googleIdentityToken = token;
      googleEmail = account.email.trim().toLowerCase();
      googleName = account.displayName?.trim() ?? '';
      await authController.signInWithProvider(
          provider: 'google', identityToken: token);
    } catch (error) {
      if (error is AuthException &&
          error.code == 'SOCIAL_ACCOUNT_NOT_FOUND' &&
          googleIdentityToken != null &&
          googleEmail.isNotEmpty &&
          mounted) {
        context.push('/register/google', extra: {
          'identity_token': googleIdentityToken,
          'email': googleEmail,
          'name': googleName,
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _error = error is AuthException
            ? error.message
            : 'No se pudo iniciar sesión con Google: ${error.toString().replaceFirst('Exception: ', '')}';
        _errorType = error is AuthException ? error.type : AuthErrorType.server;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInApple() async {
    if (_appleServiceId.isEmpty || _appleRedirectUri.isEmpty) {
      setState(() => _error =
          'Falta configurar el acceso de Apple para esta versión de MUSKL.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _errorType = null;
    });
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        webAuthenticationOptions: WebAuthenticationOptions(
          clientId: _appleServiceId,
          redirectUri: Uri.parse(_appleRedirectUri),
        ),
      );
      await authController.signInWithProvider(
        provider: 'apple',
        identityToken: credential.identityToken,
        authorizationCode: credential.authorizationCode,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is AuthException
            ? error.message
            : 'No se pudo iniciar sesión con Apple: ${error.toString().replaceFirst('Exception: ', '')}';
        _errorType = error is AuthException ? error.type : AuthErrorType.server;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      kicker: 'Bienvenido de vuelta',
      title: 'Inicia sesión',
      showBack: false,
      children: [
        if (_error != null) ...[
          _ErrorBanner(
            message: _error!,
            offline: _errorType == AuthErrorType.offline,
          ),
          const SizedBox(height: 16),
        ],
        if (_errorType == AuthErrorType.emailNotVerified &&
            _id.text.trim().contains('@'))
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _loading ? null : _resendVerification,
              icon: const Icon(Icons.mark_email_unread_outlined),
              label: const Text('Reenviar código de verificación'),
            ),
          ),
        MusklTextField(
          label: 'Correo o número de socio',
          controller: _id,
          icon: Icons.person_outline,
          hint: 'diego@correo.com',
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username],
        ),
        const SizedBox(height: 16),
        MusklTextField(
          label: 'Contraseña',
          controller: _pass,
          icon: Icons.lock_outline,
          hint: '••••••••',
          obscure: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          autofillHints: const [AutofillHints.password],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => context.push('/forgot'),
            child: const Text(
              '¿Olvidaste tu contraseña?',
              style: TextStyle(color: AppColors.accent, fontSize: 15),
            ),
          ),
        ),
        const SizedBox(height: 8),
        MusklButton(
          label: _errorType == AuthErrorType.offline
              ? 'Reintentar'
              : 'Iniciar sesión',
          icon: Icons.arrow_forward,
          loading: _loading,
          onPressed: _submit,
        ),
        const SizedBox(height: 24),
        Row(
          children: const [
            Expanded(child: Divider(color: AppColors.surfaceHigh)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'O CONTINÚA CON',
                style: TextStyle(
                    color: AppColors.textMuted, fontSize: 12, letterSpacing: 1),
              ),
            ),
            Expanded(child: Divider(color: AppColors.surfaceHigh)),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: MusklButton(
                label: 'Google',
                icon: Icons.g_mobiledata,
                style: MusklButtonStyle.light,
                loading: _loading,
                onPressed: _loading ? null : _signInGoogle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MusklButton(
                label: 'Apple',
                icon: Icons.apple,
                style: MusklButtonStyle.secondary,
                loading: _loading,
                onPressed: _loading ? null : _signInApple,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Center(
          child: TextButton(
            onPressed: () => context.push('/register'),
            child: const Text.rich(
              TextSpan(
                text: '¿No tienes cuenta? ',
                style: TextStyle(color: AppColors.textMuted, fontSize: 16),
                children: [
                  TextSpan(
                    text: 'Regístrate',
                    style: TextStyle(
                        color: AppColors.red, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.offline});

  final String message;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(
            offline ? Icons.wifi_off : Icons.error_outline,
            color: AppColors.red,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: const TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}

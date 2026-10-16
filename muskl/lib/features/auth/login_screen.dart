import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
  final _id = TextEditingController();
  final _pass = TextEditingController();
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

  void _social(String provider) {
    // Pendiente: tras entrar con Google/Apple hay que pedir los datos
    // que asigna el gimnasio (membresía, número de socio).
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Acceso con $provider: pendiente de integrar.')),
    );
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
              style: TextStyle(color: AppColors.yellow, fontSize: 15),
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
                onPressed: () => _social('Google'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MusklButton(
                label: 'Apple',
                icon: Icons.apple,
                style: MusklButtonStyle.secondary,
                onPressed: () => _social('Apple'),
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
        Center(
          child: TextButton(
            onPressed: () => context.go('/welcome'),
            child: const Text('Volver a bienvenida',
                style: TextStyle(color: AppColors.textMuted)),
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

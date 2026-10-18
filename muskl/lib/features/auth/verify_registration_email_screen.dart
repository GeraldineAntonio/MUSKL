import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/muskl_button.dart';
import '../../core/widgets/otp_input.dart';
import '../../main.dart';
import 'auth_models.dart';
import 'widgets/auth_scaffold.dart';

class VerifyRegistrationEmailScreen extends StatefulWidget {
  const VerifyRegistrationEmailScreen({super.key, required this.email});

  final String email;

  @override
  State<VerifyRegistrationEmailScreen> createState() =>
      _VerifyRegistrationEmailScreenState();
}

class _VerifyRegistrationEmailScreenState
    extends State<VerifyRegistrationEmailScreen> {
  String _code = '';
  String? _error;
  bool _loading = false;
  bool _resending = false;
  int _seconds = 30;
  int _inputKey = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _seconds = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_seconds <= 1) timer.cancel();
      if (mounted) {
        setState(() => _seconds = (_seconds - 1).clamp(0, 30).toInt());
      }
    });
  }

  Future<void> _verify() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await authController.verifyRegistrationEmail(
          email: widget.email, code: _code);
      if (mounted) {
        final session = authController.session!;
        context.go(session.role == UserRole.client ? '/onboarding' : '/pending');
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo verificar el código.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    if (_resending) return;
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      await authController.resendRegistrationEmailCode(widget.email);
      if (!mounted) return;
      setState(() {
        _code = '';
        _inputKey++;
      });
      _startCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Si tu cuenta requiere verificación, enviaremos otro código.')));
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo reenviar el código.');
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthScaffold(
        kicker: 'Verifica tu cuenta',
        title: 'Confirma tu correo',
        subtitle: 'Escribe el código de 6 dígitos que enviamos a ${widget.email}.',
        bottom: MusklButton(
          label: 'Verificar correo',
          icon: Icons.verified_outlined,
          loading: _loading,
          onPressed: _code.length == 6 ? _verify : null,
        ),
        children: [
          OtpInput(
            key: ValueKey(_inputKey),
            hasError: _error != null,
            onChanged: (value) => setState(() {
              _code = value;
              _error = null;
            }),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppColors.red)),
          ],
          const SizedBox(height: 24),
          Center(
            child: _seconds > 0
                ? Text('Reenviar código en 0:${_seconds.toString().padLeft(2, '0')}',
                    style: const TextStyle(color: AppColors.textMuted))
                : TextButton(
                    onPressed: _resending ? null : _resend,
                    child: Text(_resending ? 'Enviando…' : 'Reenviar código'),
                  ),
          ),
        ],
      );
}

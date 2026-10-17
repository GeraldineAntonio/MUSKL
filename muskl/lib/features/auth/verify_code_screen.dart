import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/muskl_button.dart';
import '../../core/widgets/otp_input.dart';
import '../../main.dart';
import 'auth_models.dart';
import 'widgets/auth_scaffold.dart';

/// Paso 2 de 3: código de 6 dígitos con "Reenviar" y contador.
class VerifyCodeScreen extends StatefulWidget {
  const VerifyCodeScreen({super.key, required this.email});

  final String email;

  @override
  State<VerifyCodeScreen> createState() => _VerifyCodeScreenState();
}

class _VerifyCodeScreenState extends State<VerifyCodeScreen> {
  static const _cooldown = 30;

  String _code = '';
  bool _loading = false;
  bool _resending = false;
  String? _error;
  int _left = _cooldown;
  Timer? _timer;
  int _otpKey = 0; // cambia para limpiar las casillas

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _left = _cooldown);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_left <= 1) {
        t.cancel();
      }
      if (mounted) setState(() => _left = _left - 1);
    });
  }

  Future<void> _resend() async {
    if (_resending) return;
    setState(() => _resending = true);
    try {
      await authController.repository.sendResetCode(widget.email);
      if (!mounted) return;
      setState(() {
        _error = null;
        _code = '';
        _otpKey++;
      });
      _startTimer();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Código reenviado.')));
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = 'No se pudo reenviar el código. Intenta de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _verify() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await authController.repository
          .verifyResetCode(email: widget.email, code: _code);
      if (mounted) {
        context.push('/forgot/new', extra: (email: widget.email, code: _code));
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      kicker: 'Paso 2 de 3',
      title: 'Código de verificación',
      subtitle: 'Lo enviamos a ${widget.email}. Escríbelo aquí.',
      bottom: MusklButton(
        label: 'Verificar',
        icon: Icons.check,
        loading: _loading,
        onPressed: _code.length == 6 ? _verify : null,
      ),
      children: [
        OtpInput(
          key: ValueKey(_otpKey),
          hasError: _error != null,
          onChanged: (v) => setState(() {
            _code = v;
            _error = null;
          }),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!,
              style: const TextStyle(color: AppColors.red, fontSize: 15)),
        ],
        const SizedBox(height: 24),
        Center(
          child: _left > 0
              ? Text(
                  'Reenviar código en 0:${_left.toString().padLeft(2, '0')}',
                  style:
                      const TextStyle(color: AppColors.textMuted, fontSize: 16),
                )
              : TextButton(
                  onPressed: _resending ? null : _resend,
                  child: Text(
                    _resending ? 'Enviando…' : 'Reenviar código',
                    style: TextStyle(color: AppColors.accent, fontSize: 16),
                  ),
                ),
        ),
      ],
    );
  }
}

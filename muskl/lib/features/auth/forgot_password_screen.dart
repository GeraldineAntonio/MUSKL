import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/muskl_button.dart';
import '../../core/widgets/muskl_text_field.dart';
import '../../main.dart';
import 'auth_models.dart';
import 'widgets/auth_scaffold.dart';

/// Paso 1 de 3: correo -> se envía un código de 6 dígitos.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _loading = false;
  String? _error;

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _email.text.trim();
    if (!_emailRe.hasMatch(email)) {
      setState(() => _error = 'Escribe un correo válido.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await authController.repository.sendResetCode(email);
      if (mounted) context.push('/forgot/code', extra: email);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      kicker: 'Paso 1 de 3',
      title: '¿Olvidaste tu contraseña?',
      subtitle:
          'Escribe el correo de tu cuenta y te enviaremos un código de 6 dígitos.',
      bottom: MusklButton(
        label: 'Enviar código',
        icon: Icons.send_outlined,
        loading: _loading,
        onPressed: _send,
      ),
      children: [
        MusklTextField(
          label: 'Correo',
          controller: _email,
          icon: Icons.mail_outline,
          hint: 'diego@correo.com',
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          errorText: _error,
          onSubmitted: (_) => _send(),
        ),
      ],
    );
  }
}

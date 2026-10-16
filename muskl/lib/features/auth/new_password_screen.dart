import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/muskl_button.dart';
import '../../core/widgets/muskl_text_field.dart';
import '../../core/widgets/password_strength.dart';
import '../../main.dart';
import 'auth_models.dart';
import 'widgets/auth_scaffold.dart';

/// Paso 3 de 3: nueva contraseña + confirmación.
class NewPasswordScreen extends StatefulWidget {
  const NewPasswordScreen({super.key, required this.email, required this.code});

  final String email;
  final String code;

  @override
  State<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends State<NewPasswordScreen> {
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (passwordScore(_pass.text) < 3 || _pass.text.length < 8) {
      setState(() => _error =
          'Usa mínimo 8 caracteres y combina mayúscula, número o símbolo.');
      return;
    }
    if (_pass.text != _confirm.text) {
      setState(() => _error = 'Las contraseñas no coinciden.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await authController.repository.resetPassword(
        email: widget.email,
        code: widget.code,
        newPassword: _pass.text,
      );
      if (mounted) context.go('/forgot/success');
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      kicker: 'Paso 3 de 3',
      title: 'Nueva contraseña',
      subtitle: 'Elige una contraseña que no uses en otras apps.',
      bottom: MusklButton(
        label: 'Guardar contraseña',
        icon: Icons.lock_reset,
        loading: _loading,
        onPressed: _save,
      ),
      children: [
        MusklTextField(
          label: 'Nueva contraseña',
          controller: _pass,
          icon: Icons.lock_outline,
          obscure: true,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() => _error = null),
        ),
        const SizedBox(height: 12),
        PasswordStrength(password: _pass.text),
        const SizedBox(height: 16),
        MusklTextField(
          label: 'Confirmar contraseña',
          controller: _confirm,
          icon: Icons.lock_outline,
          obscure: true,
          textInputAction: TextInputAction.done,
          errorText: _error,
          onSubmitted: (_) => _save(),
        ),
      ],
    );
  }
}

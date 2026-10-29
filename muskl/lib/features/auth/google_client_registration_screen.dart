import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/muskl_button.dart';
import '../../core/widgets/muskl_card.dart';
import '../../core/widgets/muskl_text_field.dart';
import '../../main.dart';
import 'auth_models.dart';

class GoogleClientRegistrationScreen extends StatefulWidget {
  const GoogleClientRegistrationScreen({super.key, required this.googleData});

  final Map<String, String> googleData;

  @override
  State<GoogleClientRegistrationScreen> createState() =>
      _GoogleClientRegistrationScreenState();
}

class _GoogleClientRegistrationScreenState
    extends State<GoogleClientRegistrationScreen> {
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  final _phone = TextEditingController();
  final _memberNumber = TextEditingController();
  DateTime? _birthDate;
  List<Map<String, dynamic>> _matches = [];
  String? _selectedRegistryId;
  bool _lookupDone = false;
  bool _lookingUp = false;
  bool _saving = false;
  String? _error;
  String _role = 'Cliente';

  @override
  void initState() {
    super.initState();
    final fullName = widget.googleData['name']?.trim() ?? '';
    final words = fullName.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final parts = words.toList();
    _firstName = TextEditingController(text: parts.isEmpty ? '' : parts.first);
    _lastName = TextEditingController(
        text: parts.length < 2 ? '' : parts.skip(1).join(' '));
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _memberNumber.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _birthDate ?? DateTime(today.year - 18, today.month, today.day),
      firstDate: DateTime(1900),
      lastDate: today,
      helpText: 'Selecciona tu fecha de nacimiento',
      confirmText: 'Aceptar',
    );
    if (picked != null && mounted) {
      setState(() {
        _birthDate = picked;
        _error = null;
      });
    }
  }

  Future<void> _lookupMember() async {
    final number = _memberNumber.text.trim();
    if (number.isEmpty) {
      setState(() => _error = 'Escribe tu número de socio primero.');
      return;
    }
    setState(() {
      _lookingUp = true;
      _lookupDone = false;
      _selectedRegistryId = null;
      _matches = [];
      _error = null;
    });
    try {
      final result =
          await authController.lookupMemberNumber(memberNumber: number);
      final rows = (result['members'] as List? ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _matches = rows;
        _lookupDone = true;
        _lookingUp = false;
      });
      if (rows.length == 1) _selectRegistry(rows.first);
      if (rows.isEmpty) {
        setState(() => _error = null);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _lookingUp = false;
        _error = error is AuthException
            ? error.message
            : error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _selectRegistry(Map<String, dynamic> member) {
    if (member['registered'] == true) {
      setState(() => _error =
          'Esta ficha ya está vinculada a una cuenta MUSKL. Inicia sesión con Google.');
      return;
    }
    final birthDate = DateTime.tryParse(member['birth_date']?.toString() ?? '');
    setState(() {
      _selectedRegistryId = member['registry_id']?.toString();
      _firstName.text = member['first_name']?.toString() ?? '';
      _lastName.text = member['last_name']?.toString() ?? '';
      _phone.text = member['phone']?.toString() ?? '';
      _birthDate = birthDate;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_firstName.text.trim().isEmpty || _lastName.text.trim().isEmpty) {
      setState(() => _error = 'Completa tu nombre y apellido.');
      return;
    }
    if (_memberNumber.text.trim().isEmpty || !_lookupDone) {
      setState(() => _error = 'Busca tu número de socio antes de continuar.');
      return;
    }
    if (_matches.length > 1 && _selectedRegistryId == null) {
      setState(() => _error = 'Selecciona tu ficha de socio.');
      return;
    }
    if (_birthDate == null) {
      setState(() => _error = 'Selecciona tu fecha de nacimiento.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await authController.registerGoogleClient(
        identityToken: widget.googleData['identity_token']!,
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        memberNumber: _memberNumber.text.trim(),
        memberRegistryId: _selectedRegistryId,
        birthDate: _birthDate!,
      );
      if (mounted) context.go('/onboarding');
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is AuthException
            ? error.message
            : 'No se pudo guardar el registro: ${error.toString().replaceFirst('Exception: ', '')}');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _continueWithEmailRegistration() {
    context.push('/register', extra: {
      'initial_role': _role == 'Entrenador' ? 'Entrenador' : 'Admin',
      'email': widget.googleData['email'] ?? '',
      'name': widget.googleData['name'] ?? '',
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Completa tu registro')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              MusklCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('CUENTA CON GOOGLE',
                        style: TextStyle(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    Text(widget.googleData['email'] ?? '',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(_role == 'Cliente'
                        ? 'Usaremos este correo verificado. No necesitas escribirlo ni crear una contraseña.'
                        : 'Usaremos este correo en el formulario de registro y podrás vincular Google después de verificarlo.'),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text('¿QUÉ TIPO DE CUENTA NECESITAS?',
                  style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1)),
              const SizedBox(height: 8),
              for (final option in [
                ('Cliente', Icons.person_outline, 'Acceso de socio'),
                ('Entrenador', Icons.fitness_center, 'Solicitud para entrenar'),
                ('Admin', Icons.admin_panel_settings_outlined,
                    'Requiere invitación'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _saving ? null : () => setState(() => _role = option.$1),
                    child: MusklCard(
                      selected: _role == option.$1,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Row(children: [
                        Icon(option.$2,
                            color: _role == option.$1
                                ? AppColors.red
                                : AppColors.textMuted),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(option.$1,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800)),
                              Text(option.$3,
                                  style: const TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 12)),
                            ])),
                        Icon(_role == option.$1
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off),
                      ]),
                    ),
                  ),
                ),
              if (_role != 'Cliente') ...[
                MusklCard(
                  child: Text(_role == 'Entrenador'
                      ? 'Para enviar una solicitud de entrenador, continuaremos con el formulario seguro. Tu correo de Google quedará vinculado después de verificarlo.'
                      : 'El registro de administrador requiere un token de invitación. Continuaremos con el formulario seguro y podrás entrar con Google después de verificar el correo.'),
                ),
                const SizedBox(height: 12),
                MusklButton(
                    label: 'Continuar como ${_role.toLowerCase()}',
                    icon: Icons.arrow_forward,
                    onPressed:
                        _saving ? null : _continueWithEmailRegistration),
              ],
              if (_role == 'Cliente') ...[
              MusklTextField(
                  label: 'Nombre *',
                  controller: _firstName,
                  icon: Icons.person_outline),
              const SizedBox(height: 12),
              MusklTextField(
                  label: 'Apellido *',
                  controller: _lastName,
                  icon: Icons.person_outline),
              const SizedBox(height: 12),
              MusklTextField(
                  label: 'Teléfono (opcional)',
                  controller: _phone,
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone),
              const SizedBox(height: 12),
              MusklTextField(
                label: 'Número de socio *',
                controller: _memberNumber,
                icon: Icons.badge_outlined,
                onChanged: (_) => setState(() {
                  _lookupDone = false;
                  _selectedRegistryId = null;
                  _matches = [];
                  _error = null;
                }),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _lookingUp || _saving ? null : _lookupMember,
                icon: _lookingUp
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.search),
                label:
                    Text(_lookingUp ? 'Buscando…' : 'Buscar número de socio'),
              ),
              if (_lookupDone && _matches.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child:
                      Text('No encontramos ficha previa. Crearemos una nueva.'),
                ),
              if (_matches.length > 1) ...[
                const SizedBox(height: 8),
                const Text('Selecciona tu ficha de socio:'),
                for (final member in _matches)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title:
                        Text('${member['first_name']} ${member['last_name']}'),
                    subtitle: Text('Nacimiento · ${member['birth_date']}'),
                    trailing: _selectedRegistryId == member['registry_id']
                        ? const Icon(Icons.check_circle,
                            color: AppColors.accent)
                        : null,
                    onTap: () => _selectRegistry(member),
                  ),
              ],
              const SizedBox(height: 12),
              InkWell(
                onTap: _saving ? null : _pickBirthDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Fecha de nacimiento *',
                    prefixIcon: Icon(Icons.cake_outlined),
                    border: OutlineInputBorder(),
                  ),
                  child: Text(_birthDate == null
                      ? 'Selecciona la fecha'
                      : '${_birthDate!.day.toString().padLeft(2, '0')}/${_birthDate!.month.toString().padLeft(2, '0')}/${_birthDate!.year}'),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                MusklCard(
                    child: Row(children: [
                  const Icon(Icons.error_outline, color: AppColors.red),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(_error!,
                          style: const TextStyle(color: AppColors.red))),
                ])),
              ],
              const SizedBox(height: 20),
              MusklButton(
                label: _saving ? 'Guardando…' : 'Crear cuenta con Google',
                icon: Icons.arrow_forward,
                loading: _saving,
                onPressed: _saving ? null : _submit,
              ),
              ],
            ],
          ),
        ),
      );
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/theme/app_colors.dart';
import '../core/widgets/muskl_button.dart';
import '../core/widgets/muskl_card.dart';
import '../core/widgets/muskl_text_field.dart';
import '../core/widgets/password_strength.dart';
import '../core/widgets/profile_photo_avatar.dart';
import '../main.dart';
import 'auth/auth_models.dart';

const _goals = ['Bajar de peso', 'Masa muscular', 'Resistencia', 'Fuerza'];
const _trainerSpecialties = [
  'Fuerza',
  'Hipertrofia',
  'Pérdida de peso',
  'Resistencia',
  'Entrenamiento funcional',
  'Movilidad',
  'Acondicionamiento físico',
];
const _goalImages = {
  'Bajar de peso': 'assets/images/goals/bajar_de_peso.jpeg',
  'Masa muscular': 'assets/images/goals/masa_muscular.jpg',
  'Resistencia': 'assets/images/goals/resistencia.jpeg',
  'Fuerza': 'assets/images/goals/fuerza.jpeg',
};

Map<int, List<Map<String, dynamic>>> _groupExercises(
    List<Map<String, dynamic>> exercises) {
  final grouped = <int, List<Map<String, dynamic>>>{};
  for (final exercise in exercises) {
    final day = int.tryParse(exercise['day_number'].toString()) ?? 1;
    grouped.putIfAbsent(day, () => []).add(exercise);
  }
  return grouped;
}

String _weekdayName(int day) => [
      'Lunes',
      'Martes',
      'Miércoles',
      'Jueves',
      'Viernes',
      'Sábado',
      'Domingo'
    ][day - 1];

class _GroupMemberFields {
  final firstName = TextEditingController();
  final lastName = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  final password = TextEditingController();
  DateTime? birthDate;

  void dispose() {
    firstName.dispose();
    lastName.dispose();
    email.dispose();
    phone.dispose();
    password.dispose();
  }
}

String _formatBirthDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

Widget _birthDateInput(BuildContext context,
        {required DateTime? value,
        required VoidCallback onTap,
        String label = 'Fecha de nacimiento *'}) =>
    InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.cake_outlined),
          suffixIcon: const Icon(Icons.calendar_month_outlined),
        ),
        child: Text(
            value == null ? 'Selecciona la fecha' : _formatBirthDate(value)),
      ),
    );

class PrototypePage extends StatelessWidget {
  const PrototypePage(
      {super.key,
      required this.title,
      required this.child,
      this.step,
      this.onBack,
      this.backWithinFlow = false});
  final String title;
  final Widget child;
  final String? step;
  final VoidCallback? onBack;
  final bool backWithinFlow;

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !backWithinFlow,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && backWithinFlow) onBack?.call();
        },
        child: Scaffold(
          appBar: AppBar(
              title: Text(title.toUpperCase()),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: backWithinFlow
                    ? onBack
                    : context.canPop()
                        ? () => context.pop()
                        : null,
              )),
          body: SafeArea(
              child: ListView(padding: const EdgeInsets.all(20), children: [
            if (step != null) ...[
              Text(step!,
                  style: const TextStyle(
                      color: AppColors.accent, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
            ],
            child,
          ])),
        ),
      );
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.initialRole = 'Cliente'});
  final String initialRole;
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _memberNumber = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _invite = TextEditingController();
  String? _certName;
  Uint8List? _certBytes;
  Uint8List? _profilePhotoBytes;
  String? _profilePhotoMime;
  final Set<String> _selectedSpecialties = {};
  bool _loading = false;
  String? _error;
  DateTime? _birthDate;
  List<Map<String, dynamic>> _registryMatches = [];
  String? _memberRegistryId;
  String? _memberPaymentDueOn;
  bool _memberLookupDone = false;
  bool _memberLookupLoading = false;
  bool _registeringAdditionalGroupMember = false;
  late String _role;

  @override
  void initState() {
    super.initState();
    _role = widget.initialRole;
  }

  @override
  void dispose() {
    _name.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    _memberNumber.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _invite.dispose();
    super.dispose();
  }

  Future<void> _pickCertification() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final selected = result.files.single;
    if (selected.size > 10 * 1024 * 1024 || selected.bytes == null) {
      setState(() => _error = 'El archivo debe pesar hasta 10 MB.');
      return;
    }
    setState(() {
      _certName = selected.name;
      _certBytes = selected.bytes;
      _error = null;
    });
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Selecciona tu fecha de nacimiento',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );
    if (picked != null && mounted) {
      setState(() {
        _birthDate = picked;
        _error = null;
      });
    }
  }

  Future<void> _lookupMemberNumber() async {
    final number = _memberNumber.text.trim();
    if (number.isEmpty) {
      setState(() => _error = 'Escribe tu número de socio primero.');
      return;
    }
    setState(() {
      _memberLookupLoading = true;
      _memberLookupDone = false;
      _registryMatches = [];
      _memberRegistryId = null;
      _memberPaymentDueOn = null;
      _registeringAdditionalGroupMember = false;
      _error = null;
    });
    try {
      final result =
          await authController.lookupMemberNumber(memberNumber: number);
      final matches = (result['members'] as List? ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _registryMatches = matches;
        _memberLookupDone = true;
        _memberLookupLoading = false;
      });
      if (matches.isEmpty) {
        setState(() {
          _name.clear();
          _lastName.clear();
          _birthDate = null;
        });
        return;
      }
      if (matches.length == 1) {
        _applyRegistryMember(matches.first);
        return;
      }
      final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Selecciona tu ficha de socio'),
          children: matches
              .map((member) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, member),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                          '${member['first_name']} ${member['last_name']}'),
                      subtitle: Text(
                          'Nacimiento ${member['birth_date']} · ${member['registered'] == true ? 'Cuenta ya vinculada' : 'Pendiente de registro'}'),
                    ),
                  ))
              .toList(),
        ),
      );
      if (selected != null && mounted) _applyRegistryMember(selected);
    } catch (error) {
      if (mounted) {
        setState(() {
          _memberLookupLoading = false;
          _error = error.toString().replaceFirst('AuthException: ', '');
        });
      }
    }
  }

  void _applyRegistryMember(Map<String, dynamic> member) {
    if (member['registered'] == true) {
      setState(() => _error =
          'Esta ficha ya tiene una cuenta. Inicia sesión o recupera la contraseña.');
      return;
    }
    final birthDate = DateTime.tryParse(member['birth_date']?.toString() ?? '');
    setState(() {
      _memberRegistryId = member['registry_id']?.toString();
      _memberPaymentDueOn = member['payment_due_on']?.toString();
      _registeringAdditionalGroupMember = false;
      _name.text = member['first_name']?.toString() ?? '';
      _lastName.text = member['last_name']?.toString() ?? '';
      _phone.text = member['phone']?.toString() ?? '';
      _birthDate = birthDate;
      _error = null;
    });
  }

  void _registerAnotherGroupMember() {
    setState(() {
      _memberRegistryId = null;
      _memberPaymentDueOn = null;
      _registeringAdditionalGroupMember = true;
      _name.clear();
      _lastName.clear();
      _birthDate = null;
      _error = null;
    });
  }

  Future<void> _pickProfilePhoto() async {
    try {
      final selected = await pickProfilePhoto(context);
      if (!mounted || selected == null) return;
      setState(() {
        _profilePhotoBytes = selected.bytes;
        _profilePhotoMime = selected.mimeType;
        _error = null;
      });
    } catch (e) {
      if (mounted)
        setState(
            () => _error = e.toString().replaceFirst('FormatException: ', ''));
    }
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (_name.text.trim().isEmpty ||
        _lastName.text.trim().isEmpty ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email) ||
        !isStrongPassword(_password.text)) {
      setState(() => _error =
          'Completa tus datos y usa una contraseña de 8 caracteres con mayúscula, minúscula, número y carácter especial.');
      return;
    }
    if (_password.text != _confirmPassword.text) {
      setState(() => _error = 'Las contraseñas no coinciden.');
      return;
    }
    if (_role == 'Cliente' && _birthDate == null) {
      setState(() => _error = 'Selecciona tu fecha de nacimiento.');
      return;
    }
    if (_role == 'Cliente' &&
        (_memberNumber.text.trim().isEmpty || !_memberLookupDone)) {
      setState(() => _error = 'Busca tu número de socio antes de continuar.');
      return;
    }
    if (_role == 'Entrenador' && _selectedSpecialties.isEmpty) {
      setState(() => _error = 'Selecciona al menos una especialidad.');
      return;
    }
    if (_role == 'Admin' && _invite.text.trim().isEmpty) {
      setState(
          () => _error = 'El registro admin requiere un token de invitación.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final first = _name.text.trim();
      final last = _lastName.text.trim();
      final normalizedEmail = email.toLowerCase();
      final phone = _phone.text.trim().isEmpty ? null : _phone.text.trim();
      if (_role == 'Cliente') {
        await authController.registerClient(
            firstName: first,
            lastName: last,
            email: normalizedEmail,
            phone: phone,
            memberNumber: _memberNumber.text.trim(),
            memberRegistryId: _memberRegistryId,
            birthDate: _birthDate!,
            password: _password.text,
            profilePhotoBytes: _profilePhotoBytes,
            profilePhotoMime: _profilePhotoMime);
      } else if (_role == 'Entrenador') {
        await authController.repository.registerTrainer(
            firstName: first,
            lastName: last,
            email: normalizedEmail,
            phone: phone,
            password: _password.text,
            specialty: _selectedSpecialties.join(' · '),
            certificationName: _certName,
            certificationBytes: _certBytes,
            profilePhotoBytes: _profilePhotoBytes,
            profilePhotoMime: _profilePhotoMime);
      } else {
        await authController.repository.registerAdmin(
            firstName: first,
            lastName: last,
            email: normalizedEmail,
            phone: phone,
            password: _password.text,
            inviteToken: _invite.text.trim(),
            profilePhotoBytes: _profilePhotoBytes,
            profilePhotoMime: _profilePhotoMime);
      }
      if (mounted) {
        context.go(Uri(path: '/verify-email', queryParameters: {
          'email': normalizedEmail,
        }).toString());
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted)
        setState(() => _error =
            'No se pudo enviar el registro. Revisa la conexión e intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => PrototypePage(
      title: 'Crear cuenta',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MusklCard(
            child: Row(children: [
          const Icon(Icons.shield_outlined, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
              child: Text(_role == 'Cliente'
                  ? 'Crea tu cuenta de socio. Después eliges membresía y preferencias para tu rutina.'
                  : 'Completa tus datos para continuar con el registro.')),
        ])),
        const SizedBox(height: 14),
        Align(
            alignment: Alignment.centerLeft,
            child: Text('TIPO DE CUENTA',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: AppColors.textMuted))),
        const SizedBox(height: 8),
        Wrap(
            spacing: 8,
            children: ['Cliente', 'Entrenador', 'Admin']
                .map((v) => ChoiceChip(
                    label: Text(v),
                    selected: _role == v,
                    onSelected: (_) => setState(() => _role = v)))
                .toList()),
        const SizedBox(height: 14),
        MusklCard(
            child: Column(children: [
          ProfilePhotoAvatar(
              image: _profilePhotoBytes == null
                  ? null
                  : MemoryImage(_profilePhotoBytes!),
              onEdit: _loading ? () {} : _pickProfilePhoto,
              radius: 42,
              name: '${_name.text} ${_lastName.text}'),
          const SizedBox(height: 8),
          const Text('Foto de perfil · opcional'),
        ])),
        const SizedBox(height: 14),
        if (_role == 'Cliente') ...[
          MusklTextField(
              label: 'Número de socio *',
              controller: _memberNumber,
              icon: Icons.badge_outlined,
              onChanged: (_) => setState(() {
                    _memberLookupDone = false;
                    _memberRegistryId = null;
                    _memberPaymentDueOn = null;
                    _registryMatches = [];
                    _error = null;
                  })),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _memberLookupLoading ? null : _lookupMemberNumber,
            icon: _memberLookupLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.search),
            label: Text(
                _memberLookupLoading ? 'Buscando…' : 'Buscar número de socio'),
          ),
          if (_memberLookupDone && _registryMatches.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child:
                  Text('Número nuevo: completa tus datos para crear tu ficha.'),
            ),
          if (_memberRegistryId != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Ficha encontrada.'),
            ),
          if (_memberRegistryId != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  'Fecha de pago: ${_memberPaymentDueOn ?? 'pendiente de captura'}'),
            ),
          if (_registryMatches.isNotEmpty && _memberRegistryId == null)
            TextButton.icon(
              onPressed: _registerAnotherGroupMember,
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('Soy otro integrante que comparte este número'),
            ),
          const SizedBox(height: 14),
        ],
        MusklTextField(
            label: 'Nombre',
            controller: _name,
            icon: Icons.person_outline,
            readOnly: _memberRegistryId != null),
        const SizedBox(height: 14),
        MusklTextField(
            label: 'Apellido',
            controller: _lastName,
            icon: Icons.person_outline,
            readOnly: _memberRegistryId != null),
        const SizedBox(height: 14),
        MusklTextField(
            label: 'Correo electrónico *',
            controller: _email,
            icon: Icons.mail_outline,
            keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 14),
        MusklTextField(
            label: 'Teléfono (opcional)',
            controller: _phone,
            icon: Icons.phone_outlined,
            hint: '+52 55 1234 5678',
            keyboardType: TextInputType.phone),
        if (_role == 'Cliente') ...[
          const SizedBox(height: 14),
          _birthDateInput(context,
              value: _birthDate,
              onTap: _loading || _memberRegistryId != null
                  ? () {}
                  : _pickBirthDate),
        ],
        const SizedBox(height: 14),
        if (_role == 'Entrenador') ...[
          MusklCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('ESPECIALIDADES',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                const Text('Selecciona una o varias'),
                const Divider(),
                for (final specialty in _trainerSpecialties)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(specialty),
                    value: _selectedSpecialties.contains(specialty),
                    onChanged: _loading
                        ? null
                        : (selected) => setState(() {
                              if (selected == true) {
                                _selectedSpecialties.add(specialty);
                              } else {
                                _selectedSpecialties.remove(specialty);
                              }
                            }),
                  ),
              ])),
          const SizedBox(height: 14),
          OutlinedButton.icon(
              onPressed: _loading ? null : _pickCertification,
              icon: const Icon(Icons.upload_file),
              label: Text(_certName ?? 'Adjuntar certificación (opcional)')),
          const SizedBox(height: 14),
        ],
        if (_role == 'Admin') ...[
          MusklTextField(
              label: 'Token de invitación admin',
              controller: _invite,
              icon: Icons.key),
          const SizedBox(height: 14),
        ],
        MusklTextField(
            label: 'Contraseña segura',
            controller: _password,
            icon: Icons.lock_outline,
            obscure: true,
            onChanged: (_) => setState(() {})),
        const SizedBox(height: 8),
        PasswordStrength(password: _password.text),
        const SizedBox(height: 14),
        MusklTextField(
            label: 'Confirmar contraseña',
            controller: _confirmPassword,
            icon: Icons.lock_outline,
            obscure: true),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppColors.red)),
        ],
        const SizedBox(height: 22),
        MusklButton(
            label: _loading
                ? 'Enviando...'
                : _role == 'Cliente'
                    ? 'Crear cuenta'
                    : 'Enviar solicitud',
            icon: Icons.arrow_forward,
            loading: _loading,
            onPressed: _submit),
      ]));
}

class ChoiceScreen extends StatefulWidget {
  const ChoiceScreen(
      {super.key,
      required this.title,
      required this.step,
      required this.options,
      required this.next});
  final String title, step, next;
  final List<String> options;
  @override
  State<ChoiceScreen> createState() => _ChoiceScreenState();
}

class _ChoiceScreenState extends State<ChoiceScreen> {
  String? choice;
  @override
  Widget build(BuildContext context) => PrototypePage(
      title: widget.title,
      step: widget.step,
      child: Column(children: [
        for (final option in widget.options)
          Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                onTap: () => setState(() => choice = option),
                child: MusklCard(
                    child: Row(children: [
                  Expanded(
                      child: Text(option,
                          style: Theme.of(context).textTheme.titleMedium)),
                  Icon(
                      choice == option
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      color: choice == option
                          ? AppColors.accent
                          : AppColors.textMuted)
                ])),
              )),
        const SizedBox(height: 12),
        MusklButton(
            label: 'Continuar',
            icon: Icons.arrow_forward,
            onPressed: choice == null ? null : () => context.go(widget.next)),
      ]));
}

class AdminMembersScreen extends StatelessWidget {
  const AdminMembersScreen({super.key});
  @override
  Widget build(BuildContext context) => PrototypePage(
      title: 'Usuarios',
      child: Column(children: [
        for (final item in [
          ('MSK-0142', 'Diego Ramírez', 'Activo'),
          ('MSK-0198', 'Ana López', 'Baja · 07 oct 2026')
        ])
          Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                  onTap: () => context.push(item.$3.startsWith('Baja')
                      ? '/admin/member?deactivated=true'
                      : '/admin/member'),
                  child: MusklCard(
                      child: Row(children: [
                    const Icon(Icons.person_outline, color: AppColors.accent),
                    const SizedBox(width: 14),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(item.$2,
                              style: Theme.of(context).textTheme.titleMedium),
                          Text('${item.$1} · ${item.$3}',
                              style:
                                  const TextStyle(color: AppColors.textMuted))
                        ])),
                    const Icon(Icons.chevron_right)
                  ])))),
        const SizedBox(height: 8),
        MusklButton(
            label: 'Cerrar sesión',
            style: MusklButtonStyle.secondary,
            onPressed: authController.signOut),
      ]));
}

class AdminMemberDetailScreen extends StatefulWidget {
  const AdminMemberDetailScreen(
      {super.key,
      this.deactivated = false,
      this.userId,
      this.memberNumber = '',
      this.name = 'Socio',
      this.email = '',
      this.phone = '',
      this.plan = '',
      this.role = 'client',
      this.status = 'active',
      this.deactivatedBy = '',
      this.trainerId = '',
      this.trainerName = '',
      this.trainerReassignmentRequired = false,
      this.reactivationUntil = ''});
  final bool deactivated;
  final String? userId;
  final String memberNumber,
      name,
      email,
      phone,
      plan,
      role,
      status,
      deactivatedBy,
      trainerId,
      trainerName,
      reactivationUntil;
  final bool trainerReassignmentRequired;

  @override
  State<AdminMemberDetailScreen> createState() =>
      _AdminMemberDetailScreenState();
}

class _AdminMemberDetailScreenState extends State<AdminMemberDetailScreen> {
  bool _assigningTrainer = false;

  Future<void> _assignTrainer() async {
    final clientId = widget.userId;
    if (clientId == null || clientId.isEmpty || _assigningTrainer) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se encontró el identificador del socio.')));
      return;
    }
    setState(() => _assigningTrainer = true);
    try {
      final trainers =
          await authController.adminUsers(role: 'trainer', status: 'active');
      if (!mounted) return;
      if (trainers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Primero debe haber un entrenador aprobado.')));
        return;
      }
      final trainer = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('ASIGNAR ENTRENADOR')),
              for (final option in trainers)
                ListTile(
                  leading: const Icon(Icons.fitness_center),
                  title: Text('${option['first_name']} ${option['last_name']}'),
                  subtitle: Text(option['specialty']?.toString() ?? ''),
                  trailing: option['id'].toString() == widget.trainerId
                      ? const Icon(Icons.check_circle, color: AppColors.red)
                      : null,
                  onTap: () => Navigator.pop(sheetContext, option),
                ),
            ],
          ),
        ),
      );
      if (trainer == null || !mounted) return;
      if (trainer['id'].toString() == widget.trainerId) return;
      await authController.reassignClientTrainer(
          clientId: clientId, trainerId: trainer['id'].toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Socio asignado a ${trainer['first_name']} ${trainer['last_name']}.')));
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('No se pudo asignar el entrenador: $error')));
      }
    } finally {
      if (mounted) setState(() => _assigningTrainer = false);
    }
  }

  @override
  Widget build(BuildContext context) => PrototypePage(
      title: widget.role == 'trainer'
          ? 'Detalle de entrenador'
          : 'Detalle de socio',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        MusklCard(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.name.toUpperCase(),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
              '${widget.memberNumber}${widget.plan.isEmpty ? '' : ' · Plan ${widget.plan}'} · ${widget.deactivated ? 'BAJA' : widget.status == 'pending' ? 'EN REVISIÓN' : widget.status == 'rejected' ? 'RECHAZADO' : 'ACTIVO'}'),
          Text(
              '${widget.email}${widget.phone.isEmpty ? '' : ' · ${widget.phone}'}'),
          if (widget.role == 'client')
            Text(widget.trainerName.isEmpty
                ? 'Sin entrenador asignado'
                : 'Entrenador: ${widget.trainerName}'),
          if (widget.deactivatedBy.isNotEmpty)
            Text('Baja registrada por: ${widget.deactivatedBy}'),
          if (widget.deactivated)
            Text(
                'Reactivación disponible hasta ${widget.reactivationUntil.isEmpty ? '—' : widget.reactivationUntil.substring(0, 10)}',
                style: const TextStyle(color: AppColors.accent))
        ])),
        const SizedBox(height: 16),
        if (!widget.deactivated &&
            (widget.role == 'client' || widget.role == 'trainer')) ...[
          if (widget.role == 'client' && widget.trainerReassignmentRequired)
            MusklButton(
                label: 'Reasignar entrenador',
                icon: Icons.fitness_center,
                loading: _assigningTrainer,
                onPressed: _assigningTrainer ? null : _assignTrainer),
          if (widget.role == 'client' && widget.trainerReassignmentRequired)
            const SizedBox(height: 10),
          MusklButton(
              label:
                  'Dar de baja al ${widget.role == 'trainer' ? 'entrenador' : 'socio'}',
              icon: Icons.person_off_outlined,
              style: MusklButtonStyle.primary,
              onPressed: () async {
                final changed = await context.push<bool>(
                    Uri(path: '/admin/deactivate', queryParameters: {
                  'member': widget.memberNumber,
                  'id': widget.userId ?? '',
                  'name': widget.name,
                  'role': widget.role,
                }).toString());
                if (changed == true && context.mounted) {
                  Navigator.of(context).pop(true);
                }
              }),
        ],
        if (widget.deactivated)
          MusklButton(
              label:
                  'Reactivar ${widget.role == 'trainer' ? 'entrenador' : 'socio'}',
              icon: Icons.person_add_alt,
              style: MusklButtonStyle.secondary,
              onPressed: () async {
                try {
                  await authController.repository.reactivateMember(
                      memberNumber: widget.memberNumber,
                      userId: widget.userId,
                      by: 'Admin MUSKL');
                  if (context.mounted) Navigator.of(context).pop(true);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('No se pudo reactivar: $e')));
                  }
                }
              }),
      ]));
}

class DeactivateMemberScreen extends StatefulWidget {
  const DeactivateMemberScreen(
      {super.key,
      this.memberNumber = '',
      this.userId,
      this.name = 'Diego Martínez',
      this.role = 'client'});
  final String memberNumber, name;
  final String role;
  final String? userId;
  @override
  State<DeactivateMemberScreen> createState() => _DeactivateMemberScreenState();
}

class _DeactivateMemberScreenState extends State<DeactivateMemberScreen> {
  String? reason;
  bool _saving = false;
  final note = TextEditingController();
  final reasons = [
    'Membresía vencida sin renovar',
    'Incumplimiento de reglas',
    'Solicitud del socio',
    'Otro'
  ];
  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  String get _roleLabel => widget.role == 'trainer' ? 'entrenador' : 'socio';

  @override
  Widget build(BuildContext context) => PrototypePage(
      title: 'Dar de baja al $_roleLabel',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        MusklCard(
            child: Text('${widget.name.toUpperCase()} · ${widget.memberNumber}',
                style: const TextStyle(fontWeight: FontWeight.bold))),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: 'Motivo'),
            items: reasons
                .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                .toList(),
            onChanged: (v) => setState(() => reason = v)),
        const SizedBox(height: 14),
        MusklTextField(
            label: 'Nota (opcional)', controller: note, icon: Icons.notes),
        const SizedBox(height: 14),
        MusklCard(
            child: Text(
                widget.role == 'trainer'
                    ? 'El entrenador perderá acceso de inmediato. Sus clientes quedarán sin entrenador asignado para que el administrador pueda reasignarlos. Sus datos se eliminarán después de 30 días si no se reactiva.'
                    : 'El socio perderá acceso de inmediato. La cuenta y sus datos se eliminarán después de 30 días si no se reactiva.',
                style: TextStyle(color: AppColors.red))),
        MusklButton(
            label: _saving ? 'Procesando…' : 'Confirmar baja',
            style: MusklButtonStyle.primary,
            loading: _saving,
            onPressed: reason == null || _saving
                ? null
                : () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('¿Confirmas la baja?'),
                        content: Text(
                          'Se desactivará el acceso de ${widget.name} a MUSKL. '
                          '${widget.role == 'trainer' ? 'Sus clientes activos quedarán sin entrenador y podrán reasignarse después. ' : ''}'
                          'Podrás reactivar la cuenta durante 30 días; después se eliminarán sus datos. '
                          'Se intentará avisar al correo registrado.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => dialogContext.pop(false),
                            child: const Text('Cancelar'),
                          ),
                          FilledButton(
                            onPressed: () => dialogContext.pop(true),
                            child: const Text('Sí, dar de baja'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true || !mounted) return;
                    setState(() => _saving = true);
                    try {
                      final detail = note.text.trim();
                      final channel = await authController.repository
                          .deactivateMember(
                              memberNumber: widget.memberNumber,
                              userId: widget.userId,
                              reason: detail.isEmpty
                                  ? reason!
                                  : '${reason!}: $detail',
                              by: 'Admin MUSKL',
                              at: DateTime.now());
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(channel == 'email'
                              ? 'Baja registrada. Aviso enviado al correo.'
                              : 'Baja registrada, pero no se pudo enviar el correo. Revisa la configuración de Brevo.'),
                        ));
                        context.pop(true);
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('No se pudo dar de baja: $e')));
                      }
                    } finally {
                      if (mounted) setState(() => _saving = false);
                    }
                  }),
        const SizedBox(height: 8),
        MusklButton(
            label: 'Cancelar',
            style: MusklButtonStyle.secondary,
            onPressed: () => context.pop()),
      ]));
}

class TrainerPhasesScreen extends StatefulWidget {
  const TrainerPhasesScreen({super.key, required this.routineId});
  final String routineId;

  @override
  State<TrainerPhasesScreen> createState() => _TrainerPhasesScreenState();
}

class _TrainerPhasesScreenState extends State<TrainerPhasesScreen> {
  late Future<Map<String, dynamic>> _routine;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() =>
      _routine = authController.trainerRoutine(routineId: widget.routineId);

  Future<void> _createPhase(Map<String, dynamic> data) async {
    if (data['phases'] is! List || (data['phases'] as List).isEmpty) return;
    context.go(Uri(path: '/trainer/routine/new', queryParameters: {
      'routine_id': widget.routineId,
    }).toString());
  }

  Future<void> _publish(Map<String, dynamic> phase) async {
    setState(() => _saving = true);
    try {
      if (phase['phase_number'] == 1) {
        await authController.publishTrainerRoutine(routineId: widget.routineId);
      } else {
        await authController.publishTrainerPhase(
            routineId: widget.routineId, phaseId: phase['id'].toString());
      }
      if (mounted) {
        setState(_reload);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Fase publicada.')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No se pudo publicar: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PrototypePage(
      title: 'Fases de rutina',
      child: FutureBuilder<Map<String, dynamic>>(
        future: _routine,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError)
            return Text('No se pudieron cargar las fases: ${snapshot.error}',
                style: const TextStyle(color: AppColors.red));
          final data = snapshot.data ?? {};
          final phases = (data['phases'] as List? ?? [])
              .map((phase) => Map<String, dynamic>.from(phase as Map))
              .toList();
          final exercises = (data['exercises'] as List? ?? [])
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
          final latest = phases.isEmpty ? null : phases.last;
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final phase in phases)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: MusklCard(
                          child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: EdgeInsets.zero,
                        title: Text('FASE ${phase['phase_number']}',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                            '${phase['status'] == 'published' ? 'Publicada' : 'Borrador'} · Plan semanal'),
                        children: [
                          for (final dayGroup in _groupExercises(exercises
                                  .where((exercise) =>
                                      exercise['phase_number'] ==
                                      phase['phase_number'])
                                  .toList())
                              .entries)
                            ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              title: Text(_weekdayName(dayGroup.key)),
                              children: [
                                for (final exercise in dayGroup.value)
                                  ListTile(
                                    dense: true,
                                    title: Text(exercise['name'].toString()),
                                  )
                              ],
                            ),
                        ],
                      ))),
                if (_saving) const LinearProgressIndicator(),
                if (latest != null && latest['status'] != 'published')
                  MusklButton(
                      label: latest['phase_number'] == 1
                          ? 'Publicar rutina'
                          : 'Publicar fase',
                      icon: Icons.publish,
                      loading: _saving,
                      onPressed: _saving ? null : () => _publish(latest)),
                if (latest != null && latest['status'] == 'published')
                  MusklButton(
                      label: 'Crear fase siguiente',
                      icon: Icons.add,
                      onPressed: _saving ? null : () => _createPhase(data)),
              ]);
        },
      ));
}

class NewPhaseScreen extends StatefulWidget {
  const NewPhaseScreen({super.key});
  @override
  State<NewPhaseScreen> createState() => _NewPhaseScreenState();
}

class _NewPhaseScreenState extends State<NewPhaseScreen> {
  late Future<List<Map<String, dynamic>>> _notifications;

  @override
  void initState() {
    super.initState();
    _notifications = authController.clientNotifications();
  }

  Future<void> _openRoutine(Map<String, dynamic>? notice) async {
    if (notice != null) {
      await authController.markClientNotificationRead(
          notificationId: notice['id'].toString());
    }
    if (mounted) context.go('/home/routine');
  }

  @override
  Widget build(BuildContext context) => PrototypePage(
      title: 'Nueva fase disponible',
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _notifications,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError)
            return Text('No se pudo cargar el aviso: ${snapshot.error}');
          final notice =
              (snapshot.data ?? []).isEmpty ? null : snapshot.data!.first;
          final payload = notice?['payload'] is Map
              ? Map<String, dynamic>.from(notice!['payload'] as Map)
              : <String, dynamic>{};
          return Column(children: [
            MusklCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                      notice == null
                          ? 'SIN CAMBIOS NUEVOS'
                          : 'FASE ${payload['phase_number'] ?? 'NUEVA'} · 8 SEMANAS',
                      style: const TextStyle(color: AppColors.accent)),
                  const SizedBox(height: 10),
                  Text(notice?['body']?.toString() ??
                      'No tienes una fase nueva por revisar.'),
                ])),
            const SizedBox(height: 18),
            MusklButton(
                label: 'Ver mi rutina', onPressed: () => _openRoutine(notice)),
          ]);
        },
      ));
}

class ClientProfileScreen extends StatelessWidget {
  const ClientProfileScreen({super.key});
  @override
  Widget build(BuildContext context) => PrototypePage(
      title: 'Perfil',
      child: Column(children: [
        const MusklCard(
            child: Text(
                'Diego Ramírez · MSK-0142\n+52 55 1234 5678 · Ciudad de México')),
        const SizedBox(height: 16),
        MusklButton(
            label: 'Solicitar eliminación de mi cuenta',
            icon: Icons.delete_outline,
            style: MusklButtonStyle.primary,
            onPressed: () => showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                        title: const Text('Solicitar eliminación'),
                        content: const Text(
                            'La solicitud se enviará al administrador del gimnasio.'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Cancelar')),
                          TextButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Solicitud registrada en el prototipo.')));
                              },
                              child: const Text('Enviar solicitud'))
                        ]))),
      ]));
}

class HomePrototypeScreen extends StatelessWidget {
  const HomePrototypeScreen({super.key});
  @override
  Widget build(BuildContext context) => PrototypePage(
      title: 'Inicio del socio',
      child: Column(children: [
        const MusklCard(
            child: Column(children: [
          Text('NÚMERO DE SOCIO'),
          SizedBox(height: 8),
          Text('MSK-0142',
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.accent)),
          Text('Racha: 4 semanas · Asistencias: 32')
        ])),
        const SizedBox(height: 12),
        MusklButton(
            label: 'Nueva fase disponible',
            icon: Icons.notifications_active_outlined,
            style: MusklButtonStyle.secondary,
            onPressed: () => context.push('/home/phase-available')),
        const SizedBox(height: 8),
        MusklButton(
            label: 'Ver perfil',
            onPressed: () => context.push('/home/profile')),
      ]));
}

class TrainerHomeScreen extends StatelessWidget {
  const TrainerHomeScreen({super.key});
  @override
  Widget build(BuildContext context) => PrototypePage(
      title: 'Panel del entrenador',
      child: Column(children: [
        const MusklCard(
            child:
                Text('Mis rutinas · Clientes · Alertas de rutinas por vencer')),
        const SizedBox(height: 14),
        MusklButton(
            label: 'Rutina de Diego · Ver fases',
            onPressed: () => context.push('/trainer/phases')),
        const SizedBox(height: 8),
        MusklButton(
            label: 'Cerrar sesión',
            style: MusklButtonStyle.secondary,
            onPressed: authController.signOut),
      ]));
}

class OnboardingStartScreen extends StatefulWidget {
  const OnboardingStartScreen({super.key});
  @override
  State<OnboardingStartScreen> createState() => _OnboardingStartScreenState();
}

class _OnboardingStartScreenState extends State<OnboardingStartScreen> {
  static const _draftStorage = FlutterSecureStorage();
  int _step = 0;
  bool _loading = true;
  bool _saving = false;
  bool _optionsFailed = false;
  String? _error;
  List<Map<String, dynamic>> _plans = [];
  List<Map<String, dynamic>> _trainers = [];
  String? _planId;
  String? _trainerId;
  String? _goal;
  String? _level;
  int? _days;
  int _selectedGroupSize = 1;
  final _weightKg = TextEditingController();
  final _heightCm = TextEditingController();
  final List<_GroupMemberFields> _groupMembers = [];
  bool _editingGroupMembers = false;
  bool _groupRegistered = false;
  final _limitations = TextEditingController();

  String? get _draftKey {
    final id = authController.session?.userId;
    return id == null ? null : 'muskl_onboarding_draft_$id';
  }

  @override
  void initState() {
    super.initState();
    _restoreDraft().then((_) {
      if (mounted) _loadOptions();
    });
  }

  Future<void> _restoreDraft() async {
    final key = _draftKey;
    if (key == null) return;
    try {
      final encoded = await _draftStorage.read(key: key);
      if (encoded == null || !mounted) return;
      final draft = Map<String, dynamic>.from(jsonDecode(encoded) as Map);
      setState(() {
        // Step 4 belonged to the old flow where clients chose their own
        // routine. Resume at the final profile step after upgrading.
        _step = (draft['step'] as num?)?.toInt().clamp(0, 3).toInt() ?? 0;
        _planId = draft['plan_id']?.toString();
        _trainerId = draft['trainer_id']?.toString();
        _goal = draft['goal']?.toString();
        _level = draft['level']?.toString();
        _days = (draft['days'] as num?)?.toInt();
        _selectedGroupSize =
            (draft['group_size'] as num?)?.toInt().clamp(1, 4).toInt() ?? 1;
        _weightKg.text = draft['weight_kg']?.toString() ?? '';
        _heightCm.text = draft['height_cm']?.toString() ?? '';
        _limitations.text = draft['limitations']?.toString() ?? '';
      });
    } catch (_) {
      await _draftStorage.delete(key: key);
    }
  }

  Future<void> _saveDraft() async {
    final key = _draftKey;
    if (key == null) return;
    await _draftStorage.write(
      key: key,
      value: jsonEncode({
        'step': _step,
        'plan_id': _planId,
        'trainer_id': _trainerId,
        'goal': _goal,
        'level': _level,
        'days': _days,
        'group_size': _selectedGroupSize,
        'weight_kg': _weightKg.text,
        'height_cm': _heightCm.text,
        'limitations': _limitations.text,
      }),
    );
  }

  Future<void> _goBack() async {
    if (_step > 0) {
      setState(() {
        _step--;
        _error = null;
      });
      await _saveDraft();
      return;
    }
    final shouldSignOut = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('SALIR DEL REGISTRO'),
              content: const Text(
                  'Tu perfil aún está incompleto. Puedes volver a iniciar sesión y continuar después.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Seguir aquí')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Cerrar sesión')),
              ],
            ));
    if (shouldSignOut == true) {
      await _saveDraft();
      await authController.signOut();
    }
  }

  @override
  void dispose() {
    _limitations.dispose();
    _weightKg.dispose();
    _heightCm.dispose();
    for (final member in _groupMembers) {
      member.dispose();
    }
    super.dispose();
  }

  Future<void> _loadOptions() async {
    try {
      final data = await authController.clientOnboardingOptions();
      if (!mounted) return;
      setState(() {
        _plans = (data['plans'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _trainers = (data['trainers'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _trainerId ??= data['assigned_trainer_id']?.toString();
        final groupPlanId = data['group_plan_id']?.toString();
        if (groupPlanId != null) {
          _planId = groupPlanId;
          _groupRegistered = (data['group_member_count'] as num? ?? 1) > 1;
        }
        _loading = false;
        _optionsFailed = false;
        if (_plans.isEmpty) {
          _error =
              'El gimnasio todavía no tiene membresías activas. Contacta al administrador.';
        }
      });
    } on AuthException catch (e) {
      if (mounted)
        setState(() {
          _error = e.message;
          _loading = false;
          _optionsFailed = true;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _error = 'No se pudieron cargar los planes. Revisa la conexión.';
          _loading = false;
          _optionsFailed = true;
        });
    }
  }

  void _retryOptions() {
    setState(() {
      _loading = true;
      _optionsFailed = false;
      _error = null;
    });
    _loadOptions();
  }

  List<Map<String, dynamic>> get _plansForSelectedGroupSize =>
      _plans.where((plan) {
        final minSize = (plan['min_group_size'] as num?)?.toInt() ?? 1;
        final maxSize = (plan['max_group_size'] as num?)?.toInt() ?? 1;
        return minSize <= _selectedGroupSize && _selectedGroupSize <= maxSize;
      }).toList();

  Future<void> _continue() async {
    final weightKg = double.tryParse(_weightKg.text.replaceAll(',', '.'));
    final heightCm = _heightCm.text.trim().isEmpty
        ? null
        : double.tryParse(_heightCm.text.replaceAll(',', '.'));
    final valid = switch (_step) {
      0 => _planId != null,
      1 => _trainerId != null,
      2 => _goal != null,
      3 => _level != null &&
          _days != null &&
          weightKg != null &&
          weightKg >= 20 &&
          weightKg <= 350 &&
          (_heightCm.text.trim().isEmpty ||
              (heightCm != null && heightCm >= 100 && heightCm <= 250)),
      _ => false,
    };
    if (!valid) {
      setState(() => _error = _step == 3
          ? 'Indica tu peso (20–350 kg) y, si agregas estatura, usa 100–250 cm.'
          : _step == 1 && _trainers.isEmpty
              ? 'No hay entrenadores disponibles. Contacta al gimnasio para continuar.'
              : 'Selecciona una opción para continuar.');
      return;
    }
    await _saveDraft();
    if (_step == 0 && !_groupRegistered) {
      if (_selectedGroupSize > 1 && !_editingGroupMembers) {
        setState(() {
          _editingGroupMembers = true;
          while (_groupMembers.length < _selectedGroupSize - 1) {
            _groupMembers.add(_GroupMemberFields());
          }
        });
        return;
      }
      if (_editingGroupMembers) {
        final validMembers = _groupMembers.every((member) =>
            member.firstName.text.trim().isNotEmpty &&
            member.lastName.text.trim().isNotEmpty &&
            member.email.text.contains('@') &&
            member.birthDate != null &&
            isStrongPassword(member.password.text));
        if (!validMembers) {
          setState(() => _error =
              'Cada integrante necesita sus datos y una contraseña con mayúscula, minúscula, número y carácter especial (8 caracteres mínimo).');
          return;
        }
        setState(() {
          _saving = true;
          _error = null;
        });
        try {
          await authController.registerClientGroupMembers(
            planId: _planId!,
            members: _groupMembers
                .map((member) => <String, String>{
                      'first_name': member.firstName.text.trim(),
                      'last_name': member.lastName.text.trim(),
                      'email': member.email.text.trim(),
                      'phone': member.phone.text.trim(),
                      'birth_date':
                          member.birthDate!.toIso8601String().substring(0, 10),
                      'password': member.password.text,
                    })
                .toList(),
          );
          if (!mounted) return;
          setState(() {
            _groupRegistered = true;
            _editingGroupMembers = false;
            _step = 1;
          });
        } on AuthException catch (e) {
          if (mounted) setState(() => _error = e.message);
        } catch (_) {
          if (mounted)
            setState(() =>
                _error = 'No se pudo registrar el grupo. Intenta de nuevo.');
        } finally {
          if (mounted) setState(() => _saving = false);
        }
        return;
      }
    }
    if (_step < 3) {
      setState(() {
        _step++;
        _error = null;
      });
      await _saveDraft();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await authController.saveClientOnboarding(
        planId: _planId!,
        trainerId: _trainerId,
        goal: _goal!,
        experienceLevel: _level!,
        daysPerWeek: _days!,
        weightKg: weightKg!,
        heightCm: heightCm,
        limitations:
            _limitations.text.trim().isEmpty ? null : _limitations.text.trim(),
      );
      final key = _draftKey;
      if (key != null) await _draftStorage.delete(key: key);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Registro completado'),
          content: const Text(
              'Inicia sesión para continuar. Tu entrenador recibirá la solicitud y podrá asignarte una rutina cuando te acepte.'),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Ir a iniciar sesión'))
          ],
        ),
      );
      if (!mounted) return;
      await authController.signOut();
      if (mounted) context.go('/login');
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted)
        setState(
            () => _error = 'No se pudo guardar tu perfil. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _option(String title,
          {String? subtitle,
          required bool selected,
          required VoidCallback onTap}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: MusklCard(
            selected: selected,
            child: Row(children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(subtitle,
                          style: const TextStyle(color: AppColors.textMuted))
                    ],
                  ])),
              Icon(selected ? Icons.check_circle : Icons.circle_outlined,
                  color: selected ? AppColors.accent : AppColors.textMuted),
            ]),
          ),
        ),
      );

  Widget _stepContent() => switch (_step) {
        0 => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_editingGroupMembers) ...[
              const Text('REGISTRO DE INTEGRANTES'),
              const SizedBox(height: 8),
              Text(
                  'Cada persona tendrá su propia cuenta, contraseña y perfil. Todos compartirán el número de socio ${authController.session?.memberNumber ?? ''}.'),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _saving
                    ? null
                    : () => setState(() {
                          _editingGroupMembers = false;
                          for (final member in _groupMembers) {
                            member.dispose();
                          }
                          _groupMembers.clear();
                        }),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Cambiar membresía'),
              ),
              for (var i = 0; i < _groupMembers.length; i++)
                _groupMemberForm(i),
            ] else if (_groupRegistered) ...[
              const Text('MEMBRESÍA DEL GRUPO'),
              const SizedBox(height: 12),
              _option(
                  _plans
                      .firstWhere((p) => p['id'] == _planId)['name']
                      .toString(),
                  subtitle:
                      'Plan compartido. Cada integrante configura su perfil individual.',
                  selected: true,
                  onTap: () {}),
            ] else ...[
              const Text('¿Cuántas personas se inscribirán?'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [1, 2, 3, 4].map((size) {
                  final selected = _selectedGroupSize == size;
                  return ChoiceChip(
                    label: Text(size == 1 ? '1 persona' : '$size personas'),
                    selected: selected,
                    onSelected: _saving
                        ? null
                        : (_) => setState(() {
                              _selectedGroupSize = size;
                              _planId = null;
                              _editingGroupMembers = false;
                              for (final member in _groupMembers) {
                                member.dispose();
                              }
                              _groupMembers.clear();
                              _error = null;
                            }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const Text('Elige tu membresía'),
              const SizedBox(height: 14),
              if (_plansForSelectedGroupSize.isEmpty)
                const Text(
                  'El gimnasio todavía no ofrece una membresía para esta cantidad de personas.',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              for (final plan in _plansForSelectedGroupSize)
                _option(plan['name'].toString(),
                    subtitle:
                        '${plan['price_mxn'] == null ? 'Precio por confirmar' : '\$${plan['price_mxn']} MXN'} · ${plan['duration_days']} días · ${_selectedGroupSize == 1 ? 'Individual' : 'Para $_selectedGroupSize personas'}',
                    selected: _planId == plan['id'],
                    onTap: () => setState(() {
                          _planId = plan['id'].toString();
                          _editingGroupMembers = false;
                          _groupRegistered = false;
                          for (final member in _groupMembers) {
                            member.dispose();
                          }
                          _groupMembers.clear();
                        })),
            ],
          ]),
        1 => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Elige el entrenador al que enviarás tu solicitud'),
            const SizedBox(height: 14),
            if (_trainers.isEmpty)
              const MusklCard(
                  child: Text(
                      'No hay entrenadores activos disponibles en este momento.')),
            for (final trainer in _trainers)
              _option('${trainer['first_name']} ${trainer['last_name']}',
                  subtitle: trainer['specialty']?.toString(),
                  selected: _trainerId == trainer['id'],
                  onTap: () =>
                      setState(() => _trainerId = trainer['id'].toString())),
          ]),
        2 => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('¿Cuál es tu objetivo?'),
            const SizedBox(height: 14),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _goals.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1,
              ),
              itemBuilder: (context, index) {
                final goal = _goals[index];
                final selected = _goal == goal;
                return Semantics(
                  button: true,
                  selected: selected,
                  label: goal,
                  child: InkWell(
                    onTap: () => setState(() => _goal = goal),
                    borderRadius: BorderRadius.circular(16),
                    child: Ink(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: selected ? AppColors.accent : Colors.white24,
                          width: selected ? 3 : 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.asset(_goalImages[goal]!, fit: BoxFit.cover),
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Color(0xCC000000),
                                  ],
                                  stops: [0.35, 1],
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.bottomLeft,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(
                                  goal,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    shadows: [
                                      Shadow(
                                          blurRadius: 8, color: Colors.black),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (selected)
                              const Positioned(
                                top: 8,
                                right: 8,
                                child: Icon(Icons.check_circle,
                                    color: AppColors.accent),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ]),
        3 => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Nivel de experiencia'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ['principiante', 'intermedio', 'avanzado']
                  .map((v) => ChoiceChip(
                        label: Text(v.toUpperCase()),
                        selected: _level == v,
                        onSelected: (_) => setState(() => _level = v),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 20),
            const Text('Días disponibles por semana'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [3, 4, 5, 6]
                  .map((v) => ChoiceChip(
                        label: Text('$v días'),
                        selected: _days == v,
                        onSelected: (_) => setState(() => _days = v),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 20),
            const Text('Datos físicos'),
            const SizedBox(height: 8),
            MusklTextField(
                label: 'Peso en kilogramos',
                hint: 'Ej. 68.5',
                controller: _weightKg,
                icon: Icons.monitor_weight_outlined,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() => _error = null)),
            const SizedBox(height: 12),
            MusklTextField(
                label: 'Estatura en centímetros (opcional)',
                hint: 'Ej. 165',
                controller: _heightCm,
                icon: Icons.height,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() => _error = null)),
            const SizedBox(height: 20),
            MusklTextField(
                label: 'Lesiones o limitaciones (opcional)',
                controller: _limitations,
                icon: Icons.health_and_safety_outlined),
          ]),
        _ => const SizedBox.shrink(),
      };

  Widget _groupMemberForm(int index) {
    final member = _groupMembers[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('INTEGRANTE ${index + 2}',
            style: const TextStyle(
                color: AppColors.accent, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        MusklTextField(
            label: 'Nombre',
            controller: member.firstName,
            icon: Icons.person_outline),
        const SizedBox(height: 8),
        MusklTextField(
            label: 'Apellidos',
            controller: member.lastName,
            icon: Icons.person_outline),
        const SizedBox(height: 8),
        MusklTextField(
            label: 'Correo personal',
            controller: member.email,
            icon: Icons.email_outlined),
        const SizedBox(height: 8),
        MusklTextField(
            label: 'Teléfono (opcional)',
            controller: member.phone,
            icon: Icons.phone_outlined),
        const SizedBox(height: 8),
        _birthDateInput(context,
            value: member.birthDate,
            label: 'Fecha de nacimiento *',
            onTap: _saving
                ? () {}
                : () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: member.birthDate ??
                          DateTime(now.year - 18, now.month, now.day),
                      firstDate: DateTime(1900),
                      lastDate: now,
                      helpText: 'Fecha de nacimiento del integrante',
                      cancelText: 'Cancelar',
                      confirmText: 'Aceptar',
                    );
                    if (picked != null && mounted) {
                      setState(() {
                        member.birthDate = picked;
                        _error = null;
                      });
                    }
                  }),
        const SizedBox(height: 8),
        MusklTextField(
            label: 'Contraseña individual segura',
            controller: member.password,
            icon: Icons.lock_outline,
            obscure: true,
            onChanged: (_) => setState(() {})),
        const SizedBox(height: 8),
        PasswordStrength(password: member.password.text),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => PrototypePage(
        title: 'Completa tu perfil',
        step: 'PASO ${_step + 1} DE 4',
        backWithinFlow: true,
        onBack: _saving ? null : _goBack,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(
                    'Configura tu membresía y preferencias para personalizar tu rutina.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppColors.textMuted)),
                const SizedBox(height: 16),
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: AppColors.red)),
                  const SizedBox(height: 12),
                  if (_optionsFailed)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _retryOptions,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar'),
                      ),
                    ),
                ],
                _stepContent(),
                const SizedBox(height: 20),
                MusklButton(
                    label: _saving
                        ? 'Guardando...'
                        : _step == 3
                            ? 'Finalizar'
                            : _step == 0 && _editingGroupMembers
                                ? 'Crear cuentas y continuar'
                                : _step == 0 &&
                                        _planId != null &&
                                        !_groupRegistered &&
                                        _selectedGroupSize > 1
                                    ? 'Agregar integrantes'
                                    : 'Continuar',
                    loading: _saving,
                    onPressed:
                        _plans.isEmpty || (_step == 1 && _trainers.isEmpty)
                            ? null
                            : _continue),
              ]),
      );
}

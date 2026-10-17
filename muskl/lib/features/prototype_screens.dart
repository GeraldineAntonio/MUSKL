import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';

import '../core/theme/app_colors.dart';
import '../core/widgets/muskl_button.dart';
import '../core/widgets/muskl_card.dart';
import '../core/widgets/muskl_text_field.dart';
import '../main.dart';
import 'auth/auth_models.dart';

const _goals = ['Bajar de peso', 'Masa muscular', 'Resistencia', 'Fuerza'];
const _goalImages = {
  'Bajar de peso': 'assets/images/goals/bajar_de_peso.jpeg',
  'Masa muscular': 'assets/images/goals/masa_muscular.jpg',
  'Resistencia': 'assets/images/goals/resistencia.jpeg',
  'Fuerza': 'assets/images/goals/fuerza.jpeg',
};

class _GroupMemberFields {
  final firstName = TextEditingController();
  final lastName = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  final password = TextEditingController();

  void dispose() {
    firstName.dispose();
    lastName.dispose();
    email.dispose();
    phone.dispose();
    password.dispose();
  }
}

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
  Widget build(BuildContext context) => Scaffold(
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
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _specialty = TextEditingController();
  final _invite = TextEditingController();
  String? _certName;
  Uint8List? _certBytes;
  bool _loading = false;
  String? _error;
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
    _password.dispose();
    _confirmPassword.dispose();
    _specialty.dispose();
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

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (_name.text.trim().isEmpty ||
        _lastName.text.trim().isEmpty ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email) ||
        _password.text.length < 8) {
      setState(() => _error =
          'Completa nombre y apellido, escribe un correo válido y usa una contraseña de al menos 8 caracteres.');
      return;
    }
    if (_password.text != _confirmPassword.text) {
      setState(() => _error = 'Las contraseñas no coinciden.');
      return;
    }
    if (_role == 'Entrenador' &&
        (_specialty.text.trim().isEmpty || _certBytes == null)) {
      setState(
          () => _error = 'Indica tu especialidad y adjunta la certificación.');
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
            password: _password.text);
        if (mounted) context.go('/onboarding');
      } else if (_role == 'Entrenador') {
        await authController.repository.registerTrainer(
            firstName: first,
            lastName: last,
            email: normalizedEmail,
            phone: phone,
            password: _password.text,
            specialty: _specialty.text.trim(),
            certificationName: _certName!,
            certificationBytes: _certBytes!);
        if (mounted) context.go('/pending');
      } else {
        await authController.repository.registerAdmin(
            firstName: first,
            lastName: last,
            email: normalizedEmail,
            phone: phone,
            password: _password.text,
            inviteToken: _invite.text.trim());
        if (mounted) context.go('/pending');
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
        MusklTextField(
            label: 'Nombre', controller: _name, icon: Icons.person_outline),
        const SizedBox(height: 14),
        MusklTextField(
            label: 'Apellido',
            controller: _lastName,
            icon: Icons.person_outline),
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
        const SizedBox(height: 14),
        if (_role == 'Entrenador') ...[
          MusklTextField(
              label: 'Especialidad',
              controller: _specialty,
              icon: Icons.fitness_center),
          const SizedBox(height: 14),
          OutlinedButton.icon(
              onPressed: _loading ? null : _pickCertification,
              icon: const Icon(Icons.upload_file),
              label: Text(_certName ?? 'Adjuntar certificación PDF o imagen')),
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
            label: 'Contraseña (mínimo 8 caracteres)',
            controller: _password,
            icon: Icons.lock_outline,
            obscure: true),
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

class AdminMemberDetailScreen extends StatelessWidget {
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
      this.deactivatedBy = '',
      this.reactivationUntil = ''});
  final bool deactivated;
  final String? userId;
  final String memberNumber,
      name,
      email,
      phone,
      plan,
      role,
      deactivatedBy,
      reactivationUntil;
  @override
  Widget build(BuildContext context) => PrototypePage(
      title: 'Detalle de socio',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        MusklCard(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name.toUpperCase(),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
              '$memberNumber${plan.isEmpty ? '' : ' · Plan $plan'} · ${deactivated ? 'BAJA' : 'ACTIVO'}'),
          Text('$email${phone.isEmpty ? '' : ' · $phone'}'),
          if (deactivatedBy.isNotEmpty)
            Text('Baja registrada por: $deactivatedBy'),
          if (deactivated)
            Text(
                'Reactivación disponible hasta ${reactivationUntil.isEmpty ? '—' : reactivationUntil.substring(0, 10)}',
                style: const TextStyle(color: AppColors.accent))
        ])),
        const SizedBox(height: 16),
        if (!deactivated && role == 'client')
          MusklButton(
              label: 'Dar de baja al socio',
              icon: Icons.person_off_outlined,
              style: MusklButtonStyle.primary,
              onPressed: () async {
                final changed = await context.push<bool>(Uri(
                    path: '/admin/deactivate',
                    queryParameters: {
                      'member': memberNumber,
                      'id': userId ?? '',
                      'name': name
                    }).toString());
                if (changed == true && context.mounted) {
                  Navigator.of(context).pop(true);
                }
              }),
        if (deactivated)
          MusklButton(
              label: 'Reactivar socio',
              icon: Icons.person_add_alt,
              style: MusklButtonStyle.secondary,
              onPressed: () async {
                try {
                  await authController.repository.reactivateMember(
                      memberNumber: memberNumber,
                      userId: userId,
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
      this.name = 'Diego Martínez'});
  final String memberNumber, name;
  final String? userId;
  @override
  State<DeactivateMemberScreen> createState() => _DeactivateMemberScreenState();
}

class _DeactivateMemberScreenState extends State<DeactivateMemberScreen> {
  String? reason;
  bool understood = false;
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

  @override
  Widget build(BuildContext context) => PrototypePage(
      title: 'Dar de baja al socio',
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
        const MusklCard(
            child: Text(
                'El socio perderá acceso a su rutina, asistencia y progreso hasta que se reactive la cuenta.',
                style: TextStyle(color: AppColors.red))),
        CheckboxListTile(
            value: understood,
            onChanged: (v) => setState(() => understood = v ?? false),
            title: const Text('Entiendo que la cuenta quedará desactivada'),
            contentPadding: EdgeInsets.zero),
        MusklButton(
            label: _saving ? 'Procesando…' : 'Confirmar baja',
            style: MusklButtonStyle.primary,
            loading: _saving,
            onPressed: reason == null || !understood || _saving
                ? null
                : () async {
                    setState(() => _saving = true);
                    try {
                      final detail = note.text.trim();
                      await authController.repository.deactivateMember(
                          memberNumber: widget.memberNumber,
                          userId: widget.userId,
                          reason:
                              detail.isEmpty ? reason! : '${reason!}: $detail',
                          by: 'Admin MUSKL',
                          at: DateTime.now());
                      if (context.mounted) {
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
    final phases = (data['phases'] as List? ?? [])
        .map((phase) => Map<String, dynamic>.from(phase as Map))
        .toList();
    final latestNumber =
        phases.isEmpty ? 0 : phases.last['phase_number'] as int;
    final latestExercises = (data['exercises'] as List? ?? [])
        .map((exercise) => Map<String, dynamic>.from(exercise as Map))
        .where((exercise) => exercise['phase_number'] == latestNumber)
        .map((exercise) => exercise['name'].toString())
        .toSet()
        .join('\n');
    final exercises = TextEditingController(text: latestExercises);
    try {
      final values = await showDialog<List<String>>(
        context: context,
        builder: (dialogContext) {
          final name = TextEditingController(text: 'Fase ${latestNumber + 1}');
          return AlertDialog(
            title: const Text('CREAR FASE'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: name,
                  decoration:
                      const InputDecoration(labelText: 'Nombre de la fase')),
              const SizedBox(height: 10),
              TextField(
                  controller: exercises,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(
                      labelText: 'Un ejercicio por línea')),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar')),
              FilledButton(
                  onPressed: () =>
                      Navigator.pop(dialogContext, [name.text, exercises.text]),
                  child: const Text('Guardar borrador')),
            ],
          );
        },
      );
      if (values == null || !mounted) return;
      final names = values[1]
          .split('\n')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();
      if (values[0].trim().isEmpty || names.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Indica el nombre de la fase y al menos un ejercicio.')));
        return;
      }
      final activeDays = (data['exercises'] as List? ?? [])
          .map((exercise) => Map<String, dynamic>.from(exercise as Map))
          .where((exercise) => exercise['phase_number'] == latestNumber)
          .map((exercise) => exercise['day_number'] as int)
          .toSet()
          .toList()
        ..sort();
      setState(() => _saving = true);
      await authController.createTrainerPhase(
          routineId: widget.routineId,
          name: values[0].trim(),
          days: activeDays,
          exercises: names);
      if (mounted) {
        setState(_reload);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Fase guardada como borrador.')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo guardar la fase: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
      exercises.dispose();
    }
  }

  Future<void> _publish(Map<String, dynamic> phase) async {
    setState(() => _saving = true);
    try {
      await authController.publishTrainerPhase(
          routineId: widget.routineId, phaseId: phase['id'].toString());
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
                MusklCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text((data['name'] ?? 'Rutina').toString().toUpperCase(),
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w900)),
                      Text(
                          '${data['goal']} · ${data['days_per_week']} días por semana'),
                    ])),
                for (final phase in phases)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: MusklCard(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(
                                '${phase['name']} · ${phase['duration_weeks']} semanas',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            Text(
                                '${phase['status'] == 'published' ? 'PUBLICADA' : 'BORRADOR'} · ${phase['exercise_count']} ejercicios'),
                            for (final exercise in exercises.where((exercise) =>
                                exercise['phase_number'] ==
                                phase['phase_number']))
                              Text(
                                  'Día ${exercise['day_number']} · ${exercise['name']} · ${exercise['sets']}×${exercise['reps']}'),
                          ]))),
                if (_saving) const LinearProgressIndicator(),
                if (latest != null && latest['status'] != 'published')
                  MusklButton(
                      label: 'Publicar fase siguiente',
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
  int _step = 0;
  bool _loading = true;
  bool _saving = false;
  bool _optionsFailed = false;
  String? _error;
  List<Map<String, dynamic>> _plans = [];
  List<Map<String, dynamic>> _trainers = [];
  List<Map<String, dynamic>> _routines = [];
  bool _loadingRoutines = false;
  String? _routineId;
  String? _planId;
  String? _trainerId;
  String? _goal;
  String? _level;
  int? _days;
  int _selectedGroupSize = 1;
  final List<_GroupMemberFields> _groupMembers = [];
  bool _editingGroupMembers = false;
  bool _groupRegistered = false;
  final _limitations = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  Future<void> _goBack() async {
    if (_step > 0) {
      setState(() {
        _step--;
        _error = null;
      });
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
    if (shouldSignOut == true) await authController.signOut();
  }

  @override
  void dispose() {
    _limitations.dispose();
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
        return minSize <= _selectedGroupSize &&
            _selectedGroupSize <= maxSize;
      }).toList();

  Future<void> _continue() async {
    final valid = switch (_step) {
      0 => _planId != null,
      1 => true,
      2 => _goal != null,
      3 => _level != null && _days != null,
      _ => _routines.isEmpty || _routineId != null,
    };
    if (!valid) {
      setState(() => _error = 'Selecciona una opción para continuar.');
      return;
    }
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
            member.password.text.length >= 8);
        if (!validMembers) {
          setState(() => _error =
              'Cada integrante necesita nombre, apellido, correo válido y contraseña de al menos 8 caracteres.');
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
      return;
    }
    if (_step == 3) {
      setState(() {
        _loadingRoutines = true;
        _error = null;
      });
      try {
        _routines = await authController.clientOnboardingRoutines(
            goal: _goal!, daysPerWeek: _days!, trainerId: _trainerId);
        if (!mounted) return;
        setState(() {
          _step = 4;
          _routineId = null;
        });
      } on AuthException catch (e) {
        if (mounted) setState(() => _error = e.message);
      } catch (_) {
        if (mounted) {
          setState(
              () => _error = 'No se pudieron cargar las rutinas disponibles.');
        }
      } finally {
        if (mounted) setState(() => _loadingRoutines = false);
      }
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
        routineId: _routineId,
        goal: _goal!,
        experienceLevel: _level!,
        daysPerWeek: _days!,
        limitations:
            _limitations.text.trim().isEmpty ? null : _limitations.text.trim(),
      );
      if (mounted) context.go('/home');
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
            const Text('Elige entrenador (opcional)'),
            const SizedBox(height: 14),
            _option('Sin preferencia',
                subtitle: 'El gimnasio puede asignarte después',
                selected: _trainerId == null,
                onTap: () => setState(() => _trainerId = null)),
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
                                      Shadow(blurRadius: 8, color: Colors.black),
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
            MusklTextField(
                label: 'Lesiones o limitaciones (opcional)',
                controller: _limitations,
                icon: Icons.health_and_safety_outlined),
          ]),
        _ => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Opciones disponibles para tu objetivo y horario.'),
            const SizedBox(height: 12),
            if (_routines.isEmpty)
              const MusklCard(
                  child: Text(
                      'Todavía no hay una rutina publicada que coincida. Puedes continuar y tu entrenador te asignará una después.')),
            for (final routine in _routines)
              _option(
                routine['name'].toString(),
                subtitle:
                    '${routine['days_per_week']} días · ${routine['duration_weeks']} semanas · Fase 1 · ${routine['trainer_name']}',
                selected: _routineId == routine['id'].toString(),
                onTap: () =>
                    setState(() => _routineId = routine['id'].toString()),
              ),
          ]),
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
        MusklTextField(
            label: 'Contraseña individual',
            controller: member.password,
            icon: Icons.lock_outline,
            obscure: true),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => PrototypePage(
        title: 'Completa tu perfil',
        step: _step < 4 ? 'PASO ${_step + 1} DE 4' : 'OPCIONES DE RUTINA',
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
                        : _step == 4
                            ? 'Empezar fase 1'
                            : _step == 3
                                ? 'Ver opciones de rutina'
                                : _step == 0 && _editingGroupMembers
                                    ? 'Crear cuentas y continuar'
                                    : _step == 0 &&
                                            _planId != null &&
                                            !_groupRegistered &&
                                            _selectedGroupSize > 1
                                        ? 'Agregar integrantes'
                                        : 'Continuar',
                    loading: _saving || _loadingRoutines,
                    onPressed: _plans.isEmpty ||
                            (_step == 4 &&
                                _routines.isNotEmpty &&
                                _routineId == null)
                        ? null
                        : _continue),
                if (_step > 0)
                  TextButton(
                      onPressed: _saving ? null : () => setState(() => _step--),
                      child: const Text('Anterior')),
              ]),
      );
}

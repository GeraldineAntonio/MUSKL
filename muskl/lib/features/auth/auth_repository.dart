import 'auth_models.dart';
import 'dart:typed_data';

/// Contrato de datos para las pantallas. La app conecta [ApiAuthRepository];
/// [FakeAuthRepository] queda para vistas previas locales.
abstract class AuthRepository {
  Future<Session?> restoreSession();
  Future<Session> registerClient(
      {required String firstName,
      required String lastName,
      required String email,
      String? phone,
      required String password});
  Future<Map<String, dynamic>> registerClientGroupMembers(
      {required String planId, required List<Map<String, String>> members});
  Future<void> registerTrainer(
      {required String firstName,
      required String lastName,
      required String email,
      String? phone,
      required String password,
      required String specialty,
      required String certificationName,
      required Uint8List certificationBytes});
  Future<void> registerAdmin(
      {required String firstName,
      required String lastName,
      required String email,
      String? phone,
      required String password,
      required String inviteToken});
  Future<Map<String, dynamic>> getClientOnboardingOptions();
  Future<List<Map<String, dynamic>>> getClientOnboardingRoutines(
      {required String goal, required int daysPerWeek, String? trainerId});
  Future<Session> completeClientOnboarding(
      {required String planId,
      String? trainerId,
      String? routineId,
      required String goal,
      required String experienceLevel,
      required int daysPerWeek,
      String? limitations});
  Future<List<Map<String, dynamic>>> getAdminUsers(
      {String search = '', String? role, String? status});
  Future<List<Map<String, dynamic>>> getAdminRoutines(
      {String search = '', String? goal});
  Future<Map<String, dynamic>> getAdminRoutine({required String routineId});
  Future<Map<String, dynamic>> getAdminDashboard();
  Future<Map<String, dynamic>> getAdminGym();
  Future<Map<String, dynamic>> updateAdminGym(
      {required String name,
      required String address,
      required String phone,
      required String openingHours});
  Future<Map<String, dynamic>> getAdminPreferences();
  Future<Map<String, dynamic>> updateAdminPreferences(
      {required bool newRequests});
  Future<List<Map<String, dynamic>>> getAdminNotifications();
  Future<void> markAdminNotificationRead({required String notificationId});
  Future<List<Map<String, dynamic>>> getAdminPlans();
  Future<Map<String, dynamic>> saveAdminPlan(
      {String? id,
      required String name,
      required double priceMxn,
      required int durationDays,
      required bool active});
  Future<List<Map<String, dynamic>>> getAdminInvites();
  Future<Map<String, dynamic>> createAdminInvite();
  Future<void> revokeAdminInvite({required String inviteId});
  Future<Map<String, dynamic>> getTrainerProfile();
  Future<Map<String, dynamic>> updateTrainerProfile(
      {required String firstName,
      required String lastName,
      required String email,
      required String phone,
      required String specialty,
      required String bio,
      required Map<String, bool> notificationPreferences});
  Future<void> changePassword(
      {required String currentPassword, required String newPassword});
  Future<List<Map<String, dynamic>>> getTrainerClients({String search = ''});
  Future<Map<String, dynamic>> getTrainerClient({required String clientId});
  Future<List<Map<String, dynamic>>> getTrainerRoutines();
  Future<Map<String, dynamic>> getTrainerRoutine({required String routineId});
  Future<List<Map<String, dynamic>>> getTrainerExerciseCatalog(
      {String search = ''});
  Future<void> createTrainerPhase(
      {required String routineId,
      required String name,
      required List<int> days,
      required List<String> exercises});
  Future<void> publishTrainerPhase(
      {required String routineId, required String phaseId});
  Future<void> createTrainerRoutine(
      {required String name,
      required String goal,
      required List<int> days,
      required List<Map<String, dynamic>> exercises});
  Future<void> publishTrainerRoutine({required String routineId});
  Future<void> assignTrainerRoutine(
      {required String routineId,
      required String phaseId,
      required String clientId});
  Future<Map<String, dynamic>> getClientDashboard();
  Future<Map<String, dynamic>> updateClientProfile(
      {String? firstName,
      String? lastName,
      String? email,
      String? phone,
      String? photoData,
      String? photoMime,
      bool removePhoto = false});
  Future<Map<String, dynamic>> getClientAttendance(
      {required int year, required int month});
  Future<Map<String, dynamic>> checkInClientAttendance();
  Future<Map<String, dynamic>> getClientRoutine({required int day});
  Future<Map<String, dynamic>> completeClientExercise(
      {required String exerciseId});
  Future<List<Map<String, dynamic>>> getClientNotifications();
  Future<void> markClientNotificationRead({required String notificationId});
  Future<List<Map<String, dynamic>>> getTrainerNotifications();
  Future<void> markTrainerNotificationRead({required String notificationId});
  Future<Map<String, dynamic>> completeClientWorkout({int? durationSeconds});
  Future<void> requestAccountDeletion();
  Future<List<Map<String, dynamic>>> getStaffRequests();
  Future<void> reviewStaffRequest(
      {required String userId, required bool approved, String? reason});
  Future<List<Map<String, dynamic>>> getAccountDeletionRequests();
  Future<void> reviewAccountDeletionRequest(
      {required String requestId, required bool approved, String? note});
  Future<Session> signIn(
      {required String identifier, required String password});
  Future<void> sendResetCode(String email);
  Future<void> verifyResetCode({required String email, required String code});
  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  });
  Future<void> signOut();

  // Admin actions implemented by the API; the fake repository is only a
  // local preview implementation.
  Future<void> deactivateMember({
    required String memberNumber,
    String? userId,
    required String reason,
    required String by,
    DateTime? at,
    DateTime? reactivationUntil,
  });

  Future<void> reactivateMember(
      {required String memberNumber, String? userId, required String by});
}

/// Simulación para probar los flujos sin backend.
///
/// Prueba con el campo "correo o número de socio":
///   cliente@muskl.mx      -> cliente activo con onboarding
///   nuevo@muskl.mx        -> cliente activo sin onboarding
///   entrenador@muskl.mx   -> entrenador pendiente (cuenta en revisión)
///   entrenador.activo@muskl.mx -> panel del entrenador
///   rechazado@muskl.mx    -> solicitud rechazada
///   baja@muskl.mx         -> cuenta dada de baja
///   admin@muskl.mx        -> admin activo
///   noexiste@muskl.mx     -> cuenta no encontrada
///   offline@muskl.mx      -> sin conexión
/// Contraseña "mala" -> credenciales incorrectas. Código de recuperación: 123456.
class FakeAuthRepository implements AuthRepository {
  // In-memory store of deactivated members for the fake implementation.
  final Map<String, Session> _deactivated = {};
  final Map<DateTime, DateTime> _fakeAttendance = {};
  int _fakeCompletedWorkouts = 0;
  final List<Map<String, dynamic>> _staffRequests = [
    {
      'id': 'demo-request-trainer',
      'role': 'trainer',
      'first_name': 'Camila',
      'last_name': 'Reyes',
      'email': 'camila@correo.com',
      'specialty': 'Funcional · HIIT'
    },
    {
      'id': 'demo-request-admin',
      'role': 'admin',
      'first_name': 'Tomás',
      'last_name': 'Herrera',
      'email': 'tomas@muskl.mx',
      'specialty': null
    },
  ];
  static bool _fakeNewRequestNotifications = true;

  @override
  Future<Session?> restoreSession() async => null;

  @override
  Future<Session> registerClient(
          {required String firstName,
          required String lastName,
          required String email,
          String? phone,
          required String password}) async =>
      const Session(
          role: UserRole.client,
          status: AccountStatus.activeNoOnboarding,
          memberNumber: 'MSK-DEMO');

  @override
  Future<Map<String, dynamic>> registerClientGroupMembers(
          {required String planId,
          required List<Map<String, String>> members}) async =>
      {'member_number': 'MSK-DEMO', 'member_count': members.length + 1};

  @override
  Future<void> registerTrainer(
      {required String firstName,
      required String lastName,
      required String email,
      String? phone,
      required String password,
      required String specialty,
      required String certificationName,
      required Uint8List certificationBytes}) async {}

  @override
  Future<void> registerAdmin(
      {required String firstName,
      required String lastName,
      required String email,
      String? phone,
      required String password,
      required String inviteToken}) async {}

  @override
  Future<Map<String, dynamic>> getClientOnboardingOptions() async => {
        'plans': [
          {
            'id': 'demo-normal',
            'name': 'Normal',
            'price_mxn': '600',
            'duration_days': 30
          },
          {
            'id': 'demo-estudiante',
            'name': 'Estudiante',
            'price_mxn': '450',
            'duration_days': 30
          },
          {
            'id': 'demo-quincenal',
            'name': 'Quincenal',
            'price_mxn': '350',
            'duration_days': 15
          },
        ],
        'trainers': [],
      };

  @override
  Future<Session> completeClientOnboarding(
          {required String planId,
          String? trainerId,
          String? routineId,
          required String goal,
          required String experienceLevel,
          required int daysPerWeek,
          String? limitations}) async =>
      const Session(
          role: UserRole.client,
          status: AccountStatus.activeOnboarded,
          memberNumber: 'MSK-DEMO');

  @override
  Future<List<Map<String, dynamic>>> getClientOnboardingRoutines(
          {required String goal,
          required int daysPerWeek,
          String? trainerId}) async =>
      [
        {
          'id': 'demo-routine-1',
          'name': 'Base total',
          'goal': goal,
          'days_per_week': daysPerWeek,
          'trainer_name': 'Marcos Rivas',
          'duration_weeks': 8,
        }
      ];

  @override
  Future<List<Map<String, dynamic>>> getAdminUsers(
          {String search = '', String? role, String? status}) async =>
      [
        {
          'id': 'demo-trainer-1',
          'role': 'trainer',
          'status': 'active',
          'first_name': 'Marcos',
          'last_name': 'Rivas',
          'email': 'marcos@muskl.mx'
        },
        {
          'id': 'demo-trainer-2',
          'role': 'trainer',
          'status': 'active',
          'first_name': 'Lucía',
          'last_name': 'Fernández',
          'email': 'lucia@muskl.mx'
        },
        {
          'id': 'demo-client-1',
          'role': 'client',
          'status': 'active',
          'first_name': 'Diego',
          'last_name': 'Martínez',
          'email': 'diego@muskl.mx',
          'member_number': 'MSK-0142',
          'membership_plan': 'Normal'
        },
        {
          'id': 'demo-client-2',
          'role': 'client',
          'status': 'deactivated',
          'first_name': 'Ana',
          'last_name': 'López',
          'email': 'ana@muskl.mx',
          'member_number': 'MSK-0198',
          'membership_plan': 'Estudiante'
        },
      ]
          .where((row) =>
              (role == null || row['role'] == role) &&
              (status == null || row['status'] == status) &&
              ('${row['first_name']} ${row['last_name']} ${row['member_number'] ?? ''}'
                  .toLowerCase()
                  .contains(search.toLowerCase())))
          .toList();

  @override
  Future<List<Map<String, dynamic>>> getAdminRoutines(
          {String search = '', String? goal}) async =>
      [
        {
          'id': 'demo-routine-1',
          'name': 'Hipertrofia 6D',
          'goal': 'Masa muscular',
          'days_per_week': 6,
          'trainer_name': 'Marcos Rivas',
          'assigned_clients': 18,
          'phases': 2,
          'phase_status': 'published',
        }
      ]
          .where((row) =>
              (goal == null || row['goal'] == goal) &&
              '${row['name']} ${row['trainer_name']}'
                  .toLowerCase()
                  .contains(search.toLowerCase()))
          .toList();

  @override
  Future<Map<String, dynamic>> getAdminRoutine(
          {required String routineId}) async =>
      {
        'id': routineId,
        'name': 'Hipertrofia 6D',
        'goal': 'Masa muscular',
        'days_per_week': 6,
        'trainer_name': 'Marcos Rivas',
        'phases': [
          {
            'id': 'demo-phase-1',
            'phase_number': 1,
            'name': 'Fase 1',
            'status': 'published',
            'duration_weeks': 8,
            'exercise_count': 3
          }
        ],
        'clients': [
          {
            'id': 'demo-client-1',
            'first_name': 'Diego',
            'last_name': 'Martínez',
            'member_number': 'MSK-0142',
            'current_phase_id': 'demo-phase-1'
          }
        ],
        'exercises': [
          {
            'id': 'demo-ex-1',
            'phase_number': 1,
            'day_number': 1,
            'name': 'Press banca plano',
            'sets': 4,
            'reps': '8-10',
            'rest_seconds': 90
          }
        ],
      };

  @override
  Future<Map<String, dynamic>> getAdminDashboard() async => {
        'clients': 312,
        'trainers': 14,
        'routines': 38,
        'pending_requests': _staffRequests.length,
        'attendance_today': 87,
        'attendance_week': [
          {'date': '2026-10-01', 'total': 42},
          {'date': '2026-10-02', 'total': 65},
          {'date': '2026-10-03', 'total': 53},
          {'date': '2026-10-04', 'total': 78},
          {'date': '2026-10-05', 'total': 61},
          {'date': '2026-10-06', 'total': 89},
          {'date': '2026-10-07', 'total': 100},
        ],
      };

  @override
  Future<Map<String, dynamic>> getAdminGym() async => {
        'name': 'MUSKL GYM',
        'address': 'Ciudad de México, México',
        'phone': '+52 55 1234 5678',
        'opening_hours': {
          'display':
              'Lunes a viernes: 05:00–23:00\nSábado: 07:00–17:00\nDomingo: cerrado'
        },
        'timezone': 'America/Mexico_City'
      };

  @override
  Future<Map<String, dynamic>> updateAdminGym(
          {required String name,
          required String address,
          required String phone,
          required String openingHours}) async =>
      {
        'name': name,
        'address': address,
        'phone': phone,
        'opening_hours': {'display': openingHours},
        'timezone': 'America/Mexico_City'
      };

  @override
  Future<Map<String, dynamic>> getAdminPreferences() async => {
        'new_requests': _fakeNewRequestNotifications,
      };

  @override
  Future<Map<String, dynamic>> updateAdminPreferences(
      {required bool newRequests}) async {
    _fakeNewRequestNotifications = newRequests;
    return {'new_requests': _fakeNewRequestNotifications};
  }

  @override
  Future<List<Map<String, dynamic>>> getAdminNotifications() async => [];

  @override
  Future<void> markAdminNotificationRead(
      {required String notificationId}) async {}

  static final List<Map<String, dynamic>> _demoPlans = [
    {
      'id': 'demo-normal',
      'name': 'Normal',
      'price_mxn': 600,
      'duration_days': 30,
      'active': true
    },
    {
      'id': 'demo-student',
      'name': 'Estudiante',
      'price_mxn': 450,
      'duration_days': 30,
      'active': true
    },
  ];
  static final List<Map<String, dynamic>> _demoInvites = [];

  @override
  Future<List<Map<String, dynamic>>> getAdminPlans() async =>
      _demoPlans.map((row) => Map<String, dynamic>.from(row)).toList();

  @override
  Future<Map<String, dynamic>> saveAdminPlan(
      {String? id,
      required String name,
      required double priceMxn,
      required int durationDays,
      required bool active}) async {
    final row = {
      'id': id ?? 'demo-plan-${DateTime.now().microsecondsSinceEpoch}',
      'name': name,
      'price_mxn': priceMxn,
      'duration_days': durationDays,
      'active': active,
    };
    final index = _demoPlans.indexWhere((item) => item['id'] == id);
    if (index < 0) {
      _demoPlans.add(row);
    } else {
      _demoPlans[index] = row;
    }
    return row;
  }

  @override
  Future<List<Map<String, dynamic>>> getAdminInvites() async =>
      _demoInvites.map((row) => Map<String, dynamic>.from(row)).toList();

  @override
  Future<Map<String, dynamic>> createAdminInvite() async {
    final row = {
      'id': 'demo-invite-${DateTime.now().microsecondsSinceEpoch}',
      'token': 'MSK-ADM-DEMO',
      'expires_at':
          DateTime.now().add(const Duration(days: 30)).toIso8601String(),
    };
    _demoInvites.add(row);
    return row;
  }

  @override
  Future<void> revokeAdminInvite({required String inviteId}) async {
    _demoInvites.removeWhere((row) => row['id'] == inviteId);
  }

  static final Map<String, dynamic> _demoTrainerProfile = {
    'first_name': 'Marcos',
    'last_name': 'Rivas',
    'email': 'marcos@muskl.mx',
    'phone': '+52 55 1234 5678',
    'specialty': 'Funcional · HIIT',
    'bio': '',
    'notification_preferences': {
      'client_activity': true,
      'routine_expiry': true,
      'daily_reminder': false,
    },
    'certifications': [
      {'id': 'demo-cert-1', 'title': 'Entrenamiento funcional'}
    ],
  };

  @override
  Future<Map<String, dynamic>> getTrainerProfile() async =>
      Map<String, dynamic>.from(_demoTrainerProfile);

  @override
  Future<Map<String, dynamic>> updateTrainerProfile(
      {required String firstName,
      required String lastName,
      required String email,
      required String phone,
      required String specialty,
      required String bio,
      required Map<String, bool> notificationPreferences}) async {
    _demoTrainerProfile.addAll({
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'phone': phone,
      'specialty': specialty,
      'bio': bio,
      'notification_preferences': notificationPreferences,
    });
    return Map<String, dynamic>.from(_demoTrainerProfile);
  }

  @override
  Future<void> changePassword(
      {required String currentPassword, required String newPassword}) async {}

  @override
  Future<List<Map<String, dynamic>>> getTrainerClients(
          {String search = ''}) async =>
      [
        {
          'id': 'demo-client-1',
          'first_name': 'Diego',
          'last_name': 'Martínez',
          'member_number': 'MSK-0142',
          'routine_name': 'Hipertrofia 6D',
          'membership_plan': 'Normal'
        },
        {
          'id': 'demo-client-2',
          'first_name': 'Valeria',
          'last_name': 'Ortiz',
          'member_number': 'MSK-0143',
          'routine_name': 'Fuerza 5x5',
          'membership_plan': 'Estudiante'
        },
        {
          'id': 'demo-client-3',
          'first_name': 'Mateo',
          'last_name': 'Guzmán',
          'member_number': 'MSK-0144',
          'routine_name': 'Quema 50',
          'membership_plan': 'Normal'
        },
      ]
          .where((row) => '${row['first_name']} ${row['last_name']}'
              .toLowerCase()
              .contains(search.toLowerCase()))
          .toList();

  @override
  Future<Map<String, dynamic>> getTrainerClient(
          {required String clientId}) async =>
      {
        'id': clientId,
        'first_name': 'Diego',
        'last_name': 'Martínez',
        'member_number': 'MSK-0142',
        'goal': 'Masa muscular',
        'membership_plan': 'Normal',
        'routine_name': 'Hipertrofia 6D',
        'phase_number': 1,
        'attendance_total': 86,
        'workouts_total': 64,
        'workouts_7d': 4,
        'attendance_7d_dates': [],
      };

  @override
  Future<List<Map<String, dynamic>>> getTrainerRoutines() async => [
        {
          'id': 'demo-routine-1',
          'name': 'Hipertrofia 6D',
          'goal': 'Masa muscular',
          'days_per_week': 6,
          'assigned_clients': 18,
          'phases': 2
        },
        {
          'id': 'demo-routine-2',
          'name': 'Quema 50',
          'goal': 'Bajar de peso',
          'days_per_week': 5,
          'assigned_clients': 8,
          'phases': 1
        },
        {
          'id': 'demo-routine-3',
          'name': 'Fuerza 5x5',
          'goal': 'Fuerza',
          'days_per_week': 4,
          'assigned_clients': 11,
          'phases': 3
        },
      ];

  @override
  Future<Map<String, dynamic>> getTrainerRoutine(
          {required String routineId}) async =>
      {
        'id': routineId,
        'name': 'Hipertrofia 6D',
        'goal': 'Masa muscular',
        'days_per_week': 3,
        'phases': [
          {
            'id': 'demo-phase-1',
            'phase_number': 1,
            'name': 'Fase 1',
            'status': 'published',
            'duration_weeks': 8,
            'exercise_count': 2
          },
          {
            'id': 'demo-phase-2',
            'phase_number': 2,
            'name': 'Fase 2',
            'status': 'draft',
            'duration_weeks': 8,
            'exercise_count': 2
          },
        ],
        'exercises': [],
      };

  @override
  Future<void> createTrainerPhase(
      {required String routineId,
      required String name,
      required List<int> days,
      required List<String> exercises}) async {}

  @override
  Future<void> publishTrainerPhase(
      {required String routineId, required String phaseId}) async {}

  @override
  Future<List<Map<String, dynamic>>> getTrainerExerciseCatalog(
          {String search = ''}) async =>
      [];

  @override
  Future<void> createTrainerRoutine(
      {required String name,
      required String goal,
      required List<int> days,
      required List<Map<String, dynamic>> exercises}) async {}

  @override
  Future<void> publishTrainerRoutine({required String routineId}) async {}

  @override
  Future<void> assignTrainerRoutine(
      {required String routineId,
      required String phaseId,
      required String clientId}) async {}

  @override
  Future<Map<String, dynamic>> getClientDashboard() async => {
        'first_name': 'Diego',
        'last_name': 'Martínez',
        'member_number': 'MSK-DEMO',
        'goal': 'Masa muscular',
        'plan_name': 'Normal',
        'trainer_name': 'Marcos Rivas',
        'routine_name': 'Hipertrofia 6D',
        'phase_number': 1,
        'attendance_total': 19,
        'workouts_7d': 4,
        'attendance_7d_dates': [],
      };

  @override
  Future<Map<String, dynamic>> updateClientProfile(
          {String? firstName,
          String? lastName,
          String? email,
          String? phone,
          String? photoData,
          String? photoMime,
          bool removePhoto = false}) async =>
      {
        ...await getClientDashboard(),
        if (firstName != null) 'first_name': firstName,
        if (lastName != null) 'last_name': lastName,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        if (photoData != null) 'profile_photo_data': photoData,
        if (photoMime != null) 'profile_photo_mime': photoMime,
        if (removePhoto) 'profile_photo_data': null,
      };

  @override
  Future<Map<String, dynamic>> getClientAttendance(
      {required int year, required int month}) async {
    final days = _fakeAttendance.entries
        .where((entry) => entry.key.year == year && entry.key.month == month)
        .map((entry) => {
              'date': entry.key.toIso8601String().substring(0, 10),
              'checked_in_at': entry.value.toIso8601String(),
              'source': 'app',
            })
        .toList();
    return {
      'days': days,
      'total': days.length,
      'today': DateTime.now().toIso8601String().substring(0, 10),
      'can_check_in': true,
      'routine_days': [1, 3, 5],
    };
  }

  @override
  Future<Map<String, dynamic>> checkInClientAttendance() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final created = !_fakeAttendance.containsKey(today);
    final checkedInAt = _fakeAttendance.putIfAbsent(today, () => now);
    return {
      'created': created,
      'date': today.toIso8601String().substring(0, 10),
      'checked_in_at': checkedInAt.toIso8601String(),
      'source': 'app',
    };
  }

  @override
  Future<Map<String, dynamic>> getClientRoutine({required int day}) async => {
        'assigned': true,
        'routine_id': 'demo-routine-1',
        'routine_name': 'Hipertrofia 6D',
        'goal': 'Masa muscular',
        'days_per_week': 6,
        'phase_id': 'demo-phase-1',
        'phase_number': 1,
        'phase_name': 'Fase 1',
        'phase_status': 'published',
        'completed_today': false,
        'exercises': [
          {
            'id': 'demo-ex-1',
            'name': 'Press banca plano',
            'sets': 4,
            'reps': '8-12',
            'rest_seconds': 60
          },
          {
            'id': 'demo-ex-2',
            'name': 'Remo con barra',
            'sets': 4,
            'reps': '10-12',
            'rest_seconds': 60
          },
        ],
      };

  @override
  Future<Map<String, dynamic>> completeClientExercise(
          {required String exerciseId}) async =>
      {'exercise_id': exerciseId, 'completed': true, 'created': true};

  @override
  Future<List<Map<String, dynamic>>> getClientNotifications() async => [];

  @override
  Future<void> markClientNotificationRead(
      {required String notificationId}) async {}

  @override
  Future<List<Map<String, dynamic>>> getTrainerNotifications() async => [];

  @override
  Future<void> markTrainerNotificationRead(
      {required String notificationId}) async {}

  @override
  Future<Map<String, dynamic>> completeClientWorkout(
      {int? durationSeconds}) async {
    _fakeCompletedWorkouts++;
    return {
      'completed': true,
      'exercise_count': 5,
      'duration_seconds': durationSeconds,
      'sessions_this_week': _fakeCompletedWorkouts,
      'sessions_total': _fakeCompletedWorkouts,
    };
  }

  @override
  Future<void> requestAccountDeletion() async {}

  @override
  Future<List<Map<String, dynamic>>> getStaffRequests() async =>
      _staffRequests.map((e) => Map<String, dynamic>.from(e)).toList();

  @override
  Future<void> reviewStaffRequest(
      {required String userId, required bool approved, String? reason}) async {
    _staffRequests.removeWhere((request) => request['id'] == userId);
  }

  @override
  Future<List<Map<String, dynamic>>> getAccountDeletionRequests() async => [];

  @override
  Future<void> reviewAccountDeletionRequest(
      {required String requestId,
      required bool approved,
      String? note}) async {}

  @override
  Future<Session> signIn({
    required String identifier,
    required String password,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final id = identifier.trim().toLowerCase();
    // If the identifier matches a memberNumber that was deactivated via the
    // fake admin flow, return the stored deactivated session.
    if (_deactivated.containsKey(id.toUpperCase()))
      return _deactivated[id.toUpperCase()]!;
    if (id.startsWith('offline')) {
      throw const AuthException(AuthErrorType.offline);
    }
    if (id.startsWith('noexiste')) {
      throw const AuthException(AuthErrorType.notFound);
    }
    if (password == 'mala') {
      throw const AuthException(AuthErrorType.invalidCredentials);
    }
    if (id.startsWith('nuevo')) {
      return const Session(
        role: UserRole.client,
        status: AccountStatus.activeNoOnboarding,
      );
    }
    if (id.startsWith('entrenador.activo')) {
      return const Session(
          role: UserRole.trainer, status: AccountStatus.activeOnboarded);
    }
    if (id.startsWith('entrenador')) {
      return const Session(
          role: UserRole.trainer, status: AccountStatus.pending);
    }
    if (id.startsWith('rechazado')) {
      return const Session(
        role: UserRole.trainer,
        status: AccountStatus.rejected,
        reason: 'El certificado adjunto no es legible.',
      );
    }
    if (id.startsWith('baja')) {
      return Session(
        role: UserRole.client,
        status: AccountStatus.deactivated,
        memberNumber: 'MSK-0142',
        reason: 'Membresía vencida sin renovar',
        deactivatedAt: DateTime(2026, 10, 7),
        deactivatedBy: 'Admin MUSKL',
        reactivationUntil: DateTime(2027, 1, 5),
      );
    }
    if (id.startsWith('admin')) {
      return const Session(
          role: UserRole.admin, status: AccountStatus.activeOnboarded);
    }
    return const Session(
      role: UserRole.client,
      status: AccountStatus.activeOnboarded,
      memberNumber: 'MSK-0142',
    );
  }

  @override
  Future<void> sendResetCode(String email) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    // Por seguridad el backend real responde igual exista o no el correo.
  }

  @override
  Future<void> verifyResetCode({
    required String email,
    required String code,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (code != '123456') throw const AuthException(AuthErrorType.invalidCode);
  }

  @override
  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deactivateMember({
    required String memberNumber,
    String? userId,
    required String reason,
    required String by,
    DateTime? at,
    DateTime? reactivationUntil,
  }) async {
    // store a minimal deactivation record so subsequent sign-ins are deactivated
    final when = at ?? DateTime.now();
    _deactivated[memberNumber.toUpperCase()] = Session(
      role: UserRole.client,
      status: AccountStatus.deactivated,
      memberNumber: memberNumber,
      reason: reason,
      deactivatedAt: when,
      deactivatedBy: by,
      reactivationUntil:
          reactivationUntil ?? when.add(const Duration(days: 90)),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  @override
  Future<void> reactivateMember(
      {required String memberNumber,
      String? userId,
      required String by}) async {
    _deactivated.remove(memberNumber.toUpperCase());
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
}

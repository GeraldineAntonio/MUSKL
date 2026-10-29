import 'package:go_router/go_router.dart';

import '../features/auth/auth_controller.dart';
import '../features/auth/auth_models.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/google_client_registration_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/new_password_screen.dart';
import '../features/auth/reset_success_screen.dart';
import '../features/auth/verify_code_screen.dart';
import '../features/auth/verify_registration_email_screen.dart';
import '../features/prototype_screens.dart';
import '../features/status/status_screens.dart';
import '../features/workspace_screens.dart';

const _publicPaths = {
  '/splash',
  '/welcome',
  '/login',
  '/register',
  '/forgot',
  '/forgot/code',
  '/forgot/new',
  '/forgot/success',
  '/verify-email',
  '/pending',
};

bool _isPublicPath(String path) =>
    _publicPaths.contains(path) ||
    path.startsWith('/register/') ||
    path == '/admin/register';

/// A dónde va cada cuenta al iniciar sesión (tabla 2.3 de la especificación).
String destinationFor(Session s) => switch (s.status) {
      // An incomplete client onboarding must remain resumable after app restart
      // so membership, trainer request, and profile details can be completed.
      AccountStatus.activeNoOnboarding => '/onboarding',
      AccountStatus.activeOnboarded => switch (s.role) {
          UserRole.client => '/home',
          UserRole.trainer => '/trainer',
          UserRole.admin => '/admin',
        },
      AccountStatus.pending => '/pending',
      AccountStatus.rejected => '/rejected',
      AccountStatus.deactivated => '/deactivated',
    };

GoRouter buildRouter(AuthController auth) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: auth,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final session = auth.session;

      if (session == null) {
        return _isPublicPath(loc) ? null : '/login';
      }
      // La verificación del correo inicia el onboarding del cliente. Aunque
      // active_no_onboarding normalmente abre el panel, debe poder completar
      // aquí membresía, entrenador y datos físicos antes de volver a iniciar
      // sesión. El siguiente login ya irá al panel para esperar su rutina.
      if (loc == '/onboarding' &&
          session.role == UserRole.client &&
          session.status == AccountStatus.activeNoOnboarding) {
        return null;
      }
      // Email verification creates a session immediately before the verify
      // screen routes the client to onboarding. Avoid racing that redirect to
      // the dashboard and losing the onboarding destination.
      if (loc == '/verify-email' &&
          session.role == UserRole.client &&
          session.status == AccountStatus.activeNoOnboarding) {
        return '/onboarding';
      }
      // Con sesión: fuera de las pantallas públicas y siempre en su destino.
      final dest = destinationFor(session);
      // Los subflujos de onboarding y las pantallas de detalle del rol deben
      // poder abrirse sin que el router los saque de su sección.
      return loc == dest || loc.startsWith('$dest/') ? null : dest;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/welcome', builder: (_, __) => const WelcomeScreen()),
      GoRoute(
        path: '/register',
        builder: (_, state) {
          final extra = state.extra is Map
              ? Map<String, dynamic>.from(state.extra as Map)
              : const <String, dynamic>{};
          return RegisterScreen(
            initialRole: extra['initial_role']?.toString() ?? 'Cliente',
            initialEmail: extra['email']?.toString() ?? '',
            initialName: extra['name']?.toString() ?? '',
          );
        },
      ),
      GoRoute(
        path: '/register/google',
        builder: (_, state) => GoogleClientRegistrationScreen(
          googleData: Map<String, String>.from(state.extra as Map),
        ),
      ),
      GoRoute(
        path: '/verify-email',
        builder: (_, state) => VerifyRegistrationEmailScreen(
            email: state.uri.queryParameters['email'] ?? '',
            emailSent: state.uri.queryParameters['email_sent'] != 'false'),
      ),
      GoRoute(
        path: '/forgot',
        builder: (_, __) => const ForgotPasswordScreen(),
        routes: const [],
      ),
      GoRoute(
        path: '/forgot/code',
        builder: (_, state) => VerifyCodeScreen(email: state.extra as String),
      ),
      GoRoute(
        path: '/forgot/new',
        builder: (_, state) {
          final e = state.extra as ({String email, String code});
          return NewPasswordScreen(email: e.email, code: e.code);
        },
      ),
      GoRoute(
          path: '/forgot/success',
          builder: (_, __) => const ResetSuccessScreen()),
      GoRoute(
          path: '/onboarding',
          builder: (_, __) => const OnboardingStartScreen()),
      GoRoute(path: '/home', builder: (_, __) => const ClientDashboardScreen()),
      GoRoute(
          path: '/home/password',
          builder: (_, __) => const ChangePasswordScreen()),
      GoRoute(
          path: '/home/email',
          builder: (_, state) => ChangeEmailScreen(
              currentEmail: state.uri.queryParameters['email'] ?? '')),
      GoRoute(
          path: '/home/trainers',
          builder: (_, __) => const ClientTrainerSelectionScreen()),
      GoRoute(
          path: '/home/routine',
          builder: (_, __) => const ClientRoutineScreen()),
      GoRoute(
          path: '/home/exercise',
          builder: (_, state) => ExerciseDetailScreen(
              id: state.uri.queryParameters['id'] ?? '1',
              name: state.uri.queryParameters['name'] ?? 'Ejercicio',
              mediaUrl: state.uri.queryParameters['media_url'] ?? '',
              muscleGroup:
                  state.uri.queryParameters['muscle_group'] ?? 'Rutina',
              instructions: state.uri.queryParameters['instructions'] ?? '',
              sets: state.uri.queryParameters['sets'] ?? '4',
              reps: state.uri.queryParameters['reps'] ?? '8-12',
              restSeconds: state.uri.queryParameters['rest_seconds'] ?? '60',
              canMarkComplete:
                  state.uri.queryParameters['can_complete'] == 'true',
              alreadyCompleted:
                  state.uri.queryParameters['already_completed'] == 'true',
              setsCompleted: int.tryParse(
                      state.uri.queryParameters['sets_completed'] ?? '0') ??
                  0)),
      GoRoute(
          path: '/home/complete',
          builder: (_, state) => RoutineCompleteScreen(
              exerciseCount:
                  int.tryParse(state.uri.queryParameters['exercise_count'] ?? '') ??
                      0,
              sessionsThisWeek:
                  int.tryParse(state.uri.queryParameters['sessions_this_week'] ?? '') ??
                      1,
              sessionsTotal:
                  int.tryParse(state.uri.queryParameters['sessions_total'] ?? '') ??
                      1,
              fullyCompleted:
                  state.uri.queryParameters['fully_completed'] != 'false',
              scheduledExerciseCount: int.tryParse(
                      state.uri.queryParameters['scheduled_exercise_count'] ??
                          '') ??
                  0,
              durationSeconds:
                  int.tryParse(state.uri.queryParameters['duration_seconds'] ?? ''),
              date: state.uri.queryParameters['date'])),
      GoRoute(
          path: '/home/attendance',
          builder: (_, __) => const AttendanceScreen()),
      GoRoute(
          path: '/home/profile',
          builder: (_, __) => const ClientProfileWorkspaceScreen()),
      GoRoute(
          path: '/home/phase-available',
          builder: (_, __) => const NewPhaseScreen()),
      GoRoute(
          path: '/trainer', builder: (_, __) => const TrainerDashboardScreen()),
      GoRoute(
          path: '/trainer/client',
          builder: (_, state) => TrainerClientDetailScreen(
              name: state.uri.queryParameters['name'] ?? 'Cliente',
              clientId: state.uri.queryParameters['id'] ?? '')),
      GoRoute(
          path: '/trainer/routines',
          builder: (_, __) => const TrainerRoutinesScreen()),
      GoRoute(
          path: '/trainer/routine/new',
          builder: (_, state) => CreateRoutineScreen(
              routineId: state.uri.queryParameters['routine_id'])),
      GoRoute(
          path: '/trainer/settings',
          builder: (_, __) => const TrainerSettingsScreen()),
      GoRoute(
          path: '/trainer/password',
          builder: (_, __) => const ChangePasswordScreen()),
      GoRoute(
          path: '/trainer/email',
          builder: (_, state) => ChangeEmailScreen(
              currentEmail: state.uri.queryParameters['email'] ?? '')),
      GoRoute(
          path: '/trainer/phases',
          builder: (_, state) => TrainerPhasesScreen(
              routineId: state.uri.queryParameters['id'] ?? '')),
      GoRoute(path: '/admin', builder: (_, __) => const AdminDashboardScreen()),
      GoRoute(
          path: '/admin/password',
          builder: (_, __) => const ChangePasswordScreen()),
      GoRoute(
          path: '/admin/email',
          builder: (_, state) => ChangeEmailScreen(
              currentEmail: state.uri.queryParameters['email'] ?? '')),
      GoRoute(
          path: '/admin/users', builder: (_, __) => const AdminUsersScreen()),
      GoRoute(
          path: '/admin/routines',
          builder: (_, __) => const AdminRoutinesScreen()),
      GoRoute(
          path: '/admin/routine',
          builder: (_, state) => AdminRoutineDetailScreen(
              name: state.uri.queryParameters['name'] ?? 'Rutina',
              routineId: state.uri.queryParameters['id'] ?? '')),
      GoRoute(
          path: '/admin/settings',
          builder: (_, __) => const AdminSettingsScreen()),
      GoRoute(
          path: '/admin/requests',
          builder: (_, __) => const AdminRequestsScreen()),
      GoRoute(
          path: '/admin/register',
          builder: (_, __) => const RegisterScreen(initialRole: 'Admin')),
      GoRoute(
          path: '/register/trainer',
          builder: (_, __) => const RegisterScreen(initialRole: 'Entrenador')),
      GoRoute(
          path: '/admin/member',
          builder: (_, state) => AdminMemberDetailScreen(
              deactivated:
                  state.uri.queryParameters['status'] == 'deactivated' ||
                      state.uri.queryParameters['deactivated'] == 'true',
              userId: state.uri.queryParameters['id'],
              memberNumber: state.uri.queryParameters['member'] ?? '',
              name: state.uri.queryParameters['name'] ?? 'Socio',
              email: state.uri.queryParameters['email'] ?? '',
              phone: state.uri.queryParameters['phone'] ?? '',
              plan: state.uri.queryParameters['plan'] ?? '',
              role: state.uri.queryParameters['role'] ?? 'client',
              status: state.uri.queryParameters['status'] ?? 'active',
              deactivatedBy: state.uri.queryParameters['deactivated_by'] ?? '',
              trainerId: state.uri.queryParameters['trainer_id'] ?? '',
              trainerName: state.uri.queryParameters['trainer_name'] ?? '',
              trainerReassignmentRequired:
                  state.uri.queryParameters['trainer_reassignment_required'] ==
                      'true',
              reactivationUntil:
                  state.uri.queryParameters['reactivation_until'] ?? '')),
      GoRoute(
          path: '/admin/deactivate',
          builder: (_, state) => DeactivateMemberScreen(
              memberNumber: state.uri.queryParameters['member'] ?? '',
              userId: state.uri.queryParameters['id']?.isEmpty == true
                  ? null
                  : state.uri.queryParameters['id'],
              name: state.uri.queryParameters['name'] ?? 'Socio',
              role: state.uri.queryParameters['role'] ?? 'client')),
      GoRoute(path: '/pending', builder: (_, __) => const PendingScreen()),
      GoRoute(path: '/rejected', builder: (_, __) => const RejectedScreen()),
      GoRoute(
          path: '/deactivated', builder: (_, __) => const DeactivatedScreen()),
    ],
  );
}

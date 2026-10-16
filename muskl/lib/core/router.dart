import 'package:go_router/go_router.dart';

import '../features/auth/auth_controller.dart';
import '../features/auth/auth_models.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/new_password_screen.dart';
import '../features/auth/reset_success_screen.dart';
import '../features/auth/verify_code_screen.dart';
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
  '/pending',
};

bool _isPublicPath(String path) =>
    _publicPaths.contains(path) ||
    path.startsWith('/register/') ||
    path == '/admin/register';

/// A dónde va cada cuenta al iniciar sesión (tabla 2.3 de la especificación).
String destinationFor(Session s) => switch (s.status) {
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
        builder: (_, __) => const RegisterScreen(),
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
          path: '/home/routine',
          builder: (_, __) => const ClientRoutineScreen()),
      GoRoute(
          path: '/home/exercise',
          builder: (_, state) => ExerciseDetailScreen(
              id: state.uri.queryParameters['id'] ?? '1',
              name: state.uri.queryParameters['name'] ?? 'Ejercicio',
              mediaUrl: state.uri.queryParameters['media_url'] ?? '',
              muscleGroup: state.uri.queryParameters['muscle_group'] ?? 'Rutina',
              instructions: state.uri.queryParameters['instructions'] ?? '',
              sets: state.uri.queryParameters['sets'] ?? '4',
              reps: state.uri.queryParameters['reps'] ?? '8-12',
              restSeconds: state.uri.queryParameters['rest_seconds'] ?? '60')),
      GoRoute(
          path: '/home/complete',
          builder: (_, state) => RoutineCompleteScreen(
              exerciseCount: int.tryParse(
                      state.uri.queryParameters['exercise_count'] ?? '') ??
                  0,
              durationSeconds: int.tryParse(
                  state.uri.queryParameters['duration_seconds'] ?? ''),
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
          builder: (_, __) => const CreateRoutineScreen()),
      GoRoute(
          path: '/trainer/settings',
          builder: (_, __) => const TrainerSettingsScreen()),
      GoRoute(
          path: '/trainer/phases',
          builder: (_, state) => TrainerPhasesScreen(
              routineId: state.uri.queryParameters['id'] ?? '')),
      GoRoute(path: '/admin', builder: (_, __) => const AdminDashboardScreen()),
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
              deactivatedBy: state.uri.queryParameters['deactivated_by'] ?? '',
              reactivationUntil:
                  state.uri.queryParameters['reactivation_until'] ?? '')),
      GoRoute(
          path: '/admin/deactivate',
          builder: (_, state) => DeactivateMemberScreen(
              memberNumber: state.uri.queryParameters['member'] ?? '',
              userId: state.uri.queryParameters['id']?.isEmpty == true
                  ? null
                  : state.uri.queryParameters['id'],
              name: state.uri.queryParameters['name'] ?? 'Socio')),
      GoRoute(path: '/pending', builder: (_, __) => const PendingScreen()),
      GoRoute(path: '/rejected', builder: (_, __) => const RejectedScreen()),
      GoRoute(
          path: '/deactivated', builder: (_, __) => const DeactivatedScreen()),
    ],
  );
}

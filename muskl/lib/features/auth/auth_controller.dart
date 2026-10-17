import 'package:flutter/foundation.dart';

import 'auth_models.dart';
import 'auth_repository.dart';

/// Guarda la sesión actual. El router escucha este objeto para redirigir.
class AuthController extends ChangeNotifier {
  AuthController(this.repository);

  final AuthRepository repository;
  Session? _session;

  Session? get session => _session;
  bool get isSignedIn => _session != null;

  Future<void> restoreSession() async {
    _session = await repository.restoreSession();
    notifyListeners();
  }

  void updateSessionFromRepository(Session? session) {
    _session = session;
    notifyListeners();
  }

  Future<void> registerClient(
      {required String firstName,
      required String lastName,
      required String email,
      String? phone,
      required String password}) async {
    _session = await repository.registerClient(
        firstName: firstName,
        lastName: lastName,
        email: email,
        phone: phone,
        password: password);
    notifyListeners();
  }

  Future<Map<String, dynamic>> registerClientGroupMembers(
          {required String planId,
          required List<Map<String, String>> members}) =>
      repository.registerClientGroupMembers(planId: planId, members: members);

  Future<Map<String, dynamic>> clientOnboardingOptions() =>
      repository.getClientOnboardingOptions();

  Future<List<Map<String, dynamic>>> clientOnboardingRoutines(
          {required String goal,
          required int daysPerWeek,
          String? trainerId}) =>
      repository.getClientOnboardingRoutines(
          goal: goal, daysPerWeek: daysPerWeek, trainerId: trainerId);

  Future<List<Map<String, dynamic>>> adminUsers(
          {String search = '', String? role, String? status}) =>
      repository.getAdminUsers(search: search, role: role, status: status);

  Future<List<Map<String, dynamic>>> adminRoutines(
          {String search = '', String? goal}) =>
      repository.getAdminRoutines(search: search, goal: goal);

  Future<Map<String, dynamic>> adminRoutine({required String routineId}) =>
      repository.getAdminRoutine(routineId: routineId);

  Future<Map<String, dynamic>> adminDashboard() =>
      repository.getAdminDashboard();

  Future<Map<String, dynamic>> adminGym() => repository.getAdminGym();

  Future<Map<String, dynamic>> updateAdminGym(
          {required String name,
          required String address,
          required String phone,
          required String openingHours}) =>
      repository.updateAdminGym(
          name: name,
          address: address,
          phone: phone,
          openingHours: openingHours);

  Future<Map<String, dynamic>> adminPreferences() =>
      repository.getAdminPreferences();

  Future<Map<String, dynamic>> updateAdminPreferences(
          {required bool newRequests}) =>
      repository.updateAdminPreferences(newRequests: newRequests);

  Future<List<Map<String, dynamic>>> adminNotifications() =>
      repository.getAdminNotifications();

  Future<void> markAdminNotificationRead({required String notificationId}) =>
      repository.markAdminNotificationRead(notificationId: notificationId);

  Future<List<Map<String, dynamic>>> adminPlans() => repository.getAdminPlans();

  Future<Map<String, dynamic>> saveAdminPlan(
          {String? id,
          required String name,
          required double priceMxn,
          required int durationDays,
          required bool active}) =>
      repository.saveAdminPlan(
          id: id,
          name: name,
          priceMxn: priceMxn,
          durationDays: durationDays,
          active: active);

  Future<List<Map<String, dynamic>>> adminInvites() =>
      repository.getAdminInvites();

  Future<Map<String, dynamic>> createAdminInvite() =>
      repository.createAdminInvite();

  Future<void> revokeAdminInvite({required String inviteId}) =>
      repository.revokeAdminInvite(inviteId: inviteId);

  Future<Map<String, dynamic>> trainerProfile() =>
      repository.getTrainerProfile();

  Future<Map<String, dynamic>> updateTrainerProfile(
          {required String firstName,
          required String lastName,
          required String email,
          required String phone,
          required String specialty,
          required String bio,
          required Map<String, bool> notificationPreferences}) =>
      repository.updateTrainerProfile(
          firstName: firstName,
          lastName: lastName,
          email: email,
          phone: phone,
          specialty: specialty,
          bio: bio,
          notificationPreferences: notificationPreferences);

  Future<void> changePassword(
          {required String currentPassword, required String newPassword}) =>
      repository.changePassword(
          currentPassword: currentPassword, newPassword: newPassword);

  Future<List<Map<String, dynamic>>> trainerClients({String search = ''}) =>
      repository.getTrainerClients(search: search);

  Future<Map<String, dynamic>> trainerClient({required String clientId}) =>
      repository.getTrainerClient(clientId: clientId);

  Future<List<Map<String, dynamic>>> trainerRoutines() =>
      repository.getTrainerRoutines();

  Future<Map<String, dynamic>> trainerRoutine({required String routineId}) =>
      repository.getTrainerRoutine(routineId: routineId);

  Future<List<Map<String, dynamic>>> trainerExerciseCatalog(
          {String search = ''}) =>
      repository.getTrainerExerciseCatalog(search: search);

  Future<void> createTrainerPhase(
          {required String routineId,
          required String name,
          required List<int> days,
          required List<String> exercises}) =>
      repository.createTrainerPhase(
          routineId: routineId, name: name, days: days, exercises: exercises);

  Future<void> publishTrainerPhase(
          {required String routineId, required String phaseId}) =>
      repository.publishTrainerPhase(routineId: routineId, phaseId: phaseId);

  Future<void> createTrainerRoutine(
          {required String name,
          required String goal,
          required List<int> days,
          required List<Map<String, dynamic>> exercises}) =>
      repository.createTrainerRoutine(
          name: name, goal: goal, days: days, exercises: exercises);

  Future<void> publishTrainerRoutine({required String routineId}) =>
      repository.publishTrainerRoutine(routineId: routineId);

  Future<void> assignTrainerRoutine(
          {required String routineId,
          required String phaseId,
          required String clientId}) =>
      repository.assignTrainerRoutine(
          routineId: routineId, phaseId: phaseId, clientId: clientId);

  Future<Map<String, dynamic>> clientDashboard() =>
      repository.getClientDashboard();

  Future<Map<String, dynamic>> updateClientProfile(
          {String? firstName,
          String? lastName,
          String? email,
          String? phone,
          String? photoData,
          String? photoMime,
          bool removePhoto = false}) =>
      repository.updateClientProfile(
          firstName: firstName,
          lastName: lastName,
          email: email,
          phone: phone,
          photoData: photoData,
          photoMime: photoMime,
          removePhoto: removePhoto);

  Future<Map<String, dynamic>> clientAttendance(
          {required int year, required int month}) =>
      repository.getClientAttendance(year: year, month: month);

  Future<Map<String, dynamic>> checkInClientAttendance() =>
      repository.checkInClientAttendance();

  Future<Map<String, dynamic>> clientRoutine({required int day}) =>
      repository.getClientRoutine(day: day);

  Future<List<Map<String, dynamic>>> clientNotifications() =>
      repository.getClientNotifications();

  Future<void> markClientNotificationRead({required String notificationId}) =>
      repository.markClientNotificationRead(notificationId: notificationId);

  Future<List<Map<String, dynamic>>> trainerNotifications() =>
      repository.getTrainerNotifications();

  Future<void> markTrainerNotificationRead({required String notificationId}) =>
      repository.markTrainerNotificationRead(notificationId: notificationId);

  Future<Map<String, dynamic>> completeClientWorkout({int? durationSeconds}) =>
      repository.completeClientWorkout(durationSeconds: durationSeconds);

  Future<void> requestAccountDeletion() => repository.requestAccountDeletion();

  Future<List<Map<String, dynamic>>> staffRequests() =>
      repository.getStaffRequests();

  Future<void> reviewStaffRequest(
          {required String userId, required bool approved, String? reason}) =>
      repository.reviewStaffRequest(
          userId: userId, approved: approved, reason: reason);

  Future<List<Map<String, dynamic>>> accountDeletionRequests() =>
      repository.getAccountDeletionRequests();

  Future<void> reviewAccountDeletionRequest(
          {required String requestId, required bool approved, String? note}) =>
      repository.reviewAccountDeletionRequest(
          requestId: requestId, approved: approved, note: note);

  Future<void> saveClientOnboarding(
      {required String planId,
      String? trainerId,
      String? routineId,
      required String goal,
      required String experienceLevel,
      required int daysPerWeek,
      String? limitations}) async {
    _session = await repository.completeClientOnboarding(
        planId: planId,
        trainerId: trainerId,
        routineId: routineId,
        goal: goal,
        experienceLevel: experienceLevel,
        daysPerWeek: daysPerWeek,
        limitations: limitations);
    notifyListeners();
  }

  Future<void> signIn(String identifier, String password) async {
    _session =
        await repository.signIn(identifier: identifier, password: password);
    notifyListeners();
  }

  Future<void> signOut() async {
    await repository.signOut();
    _session = null;
    notifyListeners();
  }
}

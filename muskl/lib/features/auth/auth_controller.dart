import 'dart:typed_data';

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

  Future<bool> registerClient(
      {required String firstName,
      required String lastName,
      required String email,
      String? phone,
      required String memberNumber,
      String? memberRegistryId,
      required DateTime birthDate,
      required String password,
      Uint8List? profilePhotoBytes,
      String? profilePhotoMime}) async {
    return repository.registerClient(
        firstName: firstName,
        lastName: lastName,
        email: email,
        phone: phone,
        memberNumber: memberNumber,
        memberRegistryId: memberRegistryId,
        birthDate: birthDate,
        password: password,
        profilePhotoBytes: profilePhotoBytes,
        profilePhotoMime: profilePhotoMime);
  }

  Future<Map<String, dynamic>> lookupMemberNumber(
          {required String memberNumber}) =>
      repository.lookupMemberNumber(memberNumber: memberNumber);

  Future<void> resendRegistrationEmailCode(String email) =>
      repository.resendRegistrationEmailCode(email);

  Future<void> verifyRegistrationEmail(
      {required String email, required String code}) async {
    _session =
        await repository.verifyRegistrationEmail(email: email, code: code);
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

  Future<void> reassignClientTrainer(
          {required String clientId, required String trainerId}) =>
      repository.reassignClientTrainer(
          clientId: clientId, trainerId: trainerId);

  Future<List<Map<String, dynamic>>> adminRoutines(
          {String search = '', String? goal}) =>
      repository.getAdminRoutines(search: search, goal: goal);

  Future<Map<String, dynamic>> adminRoutine({required String routineId}) =>
      repository.getAdminRoutine(routineId: routineId);

  Future<void> assignAdminRoutine(
          {required String routineId,
          required String phaseId,
          required String clientId}) =>
      repository.assignAdminRoutine(
          routineId: routineId, phaseId: phaseId, clientId: clientId);

  Future<Map<String, dynamic>> adminDashboard() =>
      repository.getAdminDashboard();

  Future<Map<String, dynamic>> adminGym() => repository.getAdminGym();

  Future<Map<String, dynamic>> updateAdminGym(
          {required String name,
          required String address,
          required String phone,
          required Map<String, String> openingHours}) =>
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
          int minGroupSize = 1,
          int maxGroupSize = 1,
          required bool active}) =>
      repository.saveAdminPlan(
          id: id,
          name: name,
          priceMxn: priceMxn,
          durationDays: durationDays,
          minGroupSize: minGroupSize,
          maxGroupSize: maxGroupSize,
          active: active);

  Future<List<Map<String, dynamic>>> adminInvites() =>
      repository.getAdminInvites();

  Future<Map<String, dynamic>> createAdminInvite() =>
      repository.createAdminInvite();

  Future<void> revokeAdminInvite({required String inviteId}) =>
      repository.revokeAdminInvite(inviteId: inviteId);

  Future<Map<String, dynamic>> trainerProfile() =>
      repository.getTrainerProfile();

  Future<Map<String, dynamic>> ownProfile() => repository.getOwnProfile();

  Future<Map<String, dynamic>> updateOwnProfile({
    required String firstName,
    required String lastName,
    required String phone,
    required String bio,
  }) =>
      repository.updateOwnProfile(
          firstName: firstName, lastName: lastName, phone: phone, bio: bio);

  Future<Map<String, dynamic>> updateOwnProfilePhoto(
          {String? photoData, String? photoMime, bool removePhoto = false}) =>
      repository.updateOwnProfilePhoto(
          photoData: photoData, photoMime: photoMime, removePhoto: removePhoto);

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
          {required String currentPassword,
          required String newPassword,
          required String code}) =>
      repository.changePassword(
          currentPassword: currentPassword,
          newPassword: newPassword,
          code: code);

  Future<String?> sendPasswordChangeCode({required String currentPassword}) =>
      repository.sendPasswordChangeCode(currentPassword: currentPassword);

  Future<void> verifyPasswordChangeCode(
          {required String currentPassword, required String code}) =>
      repository.verifyPasswordChangeCode(
          currentPassword: currentPassword, code: code);

  Future<void> requestEmailChangeCode({required String newEmail}) =>
      repository.requestEmailChangeCode(newEmail: newEmail);

  Future<void> confirmEmailChange(
          {required String currentPassword, required String code}) =>
      repository.confirmEmailChange(
          currentPassword: currentPassword, code: code);

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
          required List<Map<String, dynamic>> exercises}) =>
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

  Future<Map<String, dynamic>> clientTrainers() =>
      repository.getClientTrainers();

  Future<void> requestClientTrainer({required String trainerId}) =>
      repository.requestClientTrainer(trainerId: trainerId);

  Future<List<Map<String, dynamic>>> trainerAssignmentRequests() =>
      repository.getTrainerAssignmentRequests();

  Future<void> reviewTrainerAssignmentRequest(
          {required String requestId,
          required bool accept,
          String? routineId,
          String? phaseId}) =>
      repository.reviewTrainerAssignmentRequest(
          requestId: requestId,
          accept: accept,
          routineId: routineId,
          phaseId: phaseId);

  Future<Map<String, dynamic>> updateClientProfile(
          {String? firstName,
          String? lastName,
          String? email,
          String? phone,
          String? bio,
          String? photoData,
          String? photoMime,
          bool removePhoto = false}) =>
      repository.updateClientProfile(
          firstName: firstName,
          lastName: lastName,
          email: email,
          phone: phone,
          bio: bio,
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

  Future<Map<String, dynamic>> completeClientExercise(
          {required String exerciseId, required int setsCompleted}) =>
      repository.completeClientExercise(
          exerciseId: exerciseId, setsCompleted: setsCompleted);

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

  Future<String> ownTrainerCertificationDownloadUrl({
    required String certificationId,
  }) =>
      repository.getOwnTrainerCertificationDownloadUrl(
          certificationId: certificationId);

  Future<void> replaceOwnTrainerCertification({
    required String certificationId,
    required String filename,
    required Uint8List bytes,
  }) =>
      repository.replaceOwnTrainerCertification(
          certificationId: certificationId, filename: filename, bytes: bytes);

  Future<String> trainerCertificationDownloadUrl({
    required String trainerId,
    required String certificationId,
  }) =>
      repository.getTrainerCertificationDownloadUrl(
          trainerId: trainerId, certificationId: certificationId);

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
      required String goal,
      required String experienceLevel,
      required int daysPerWeek,
      required double weightKg,
      double? heightCm,
      String? limitations}) async {
    await repository.completeClientOnboarding(
        planId: planId,
        trainerId: trainerId,
        goal: goal,
        experienceLevel: experienceLevel,
        daysPerWeek: daysPerWeek,
        weightKg: weightKg,
        heightCm: heightCm,
        limitations: limitations);
  }

  Future<void> signIn(String identifier, String password) async {
    _session =
        await repository.signIn(identifier: identifier, password: password);
    notifyListeners();
  }

  Future<void> signOut() async {
    try {
      await repository.signOut();
    } finally {
      _session = null;
      notifyListeners();
    }
  }
}

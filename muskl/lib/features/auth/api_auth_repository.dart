import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_models.dart';
import 'auth_repository.dart';

/// REST implementation for the PostgreSQL-backed MUSKL API.
/// Set MUSKL_API_URL at build time; the fake repository remains for UI demos.
class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(String baseUrl)
      : _baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), '');

  final String _baseUrl;
  final HttpClient _client = HttpClient()
    // The Render free instance can need up to about a minute to wake after
    // idling. Leave enough time for its first request to reach the API.
    ..connectionTimeout = const Duration(seconds: 90);
  static const _secureStorage = FlutterSecureStorage();
  static const _tokenKey = 'muskl_access_token';
  static const _refreshTokenKey = 'muskl_refresh_token';
  static const _sessionKey = 'muskl_cached_session';
  String? _accessToken;
  String? _refreshToken;
  Future<bool>? _refreshing;
  void Function(Session? session)? onSessionChanged;

  @override
  Future<Session?> restoreSession() async {
    try {
      _accessToken = await _secureStorage.read(key: _tokenKey);
      _refreshToken = await _secureStorage.read(key: _refreshTokenKey);
      final cached = await _secureStorage.read(key: _sessionKey);
      if (cached == null) {
        await _clearStoredSession();
        return null;
      }
      final cachedSession =
          _sessionFromJson(jsonDecode(cached) as Map<String, dynamic>);
      if (_accessToken == null && _refreshToken == null) {
        if (cachedSession.status == AccountStatus.deactivated) {
          return cachedSession;
        }
        await _clearStoredSession();
        return null;
      }
      if (_accessToken == null) {
        final response = await _request('POST', '/api/v1/auth/refresh',
            body: {'refresh_token': _refreshToken});
        return await _sessionFromResponse(
            Map<String, dynamic>.from(response as Map));
      }
      final response =
          await _request('GET', '/api/v1/auth/me', authenticated: true) as Map;
      return await _saveSessionFromUser(
          Map<String, dynamic>.from(response['user'] as Map));
    } on AuthException catch (error) {
      final cached = await _secureStorage.read(key: _sessionKey);
      if (cached != null) {
        final session =
            _sessionFromJson(jsonDecode(cached) as Map<String, dynamic>);
        if (error.type == AuthErrorType.offline ||
            session.status == AccountStatus.deactivated) {
          return session;
        }
      }
      try {
        await _clearStoredSession();
      } catch (_) {}
      onSessionChanged?.call(null);
      return null;
    } catch (_) {
      try {
        await _clearStoredSession();
      } catch (_) {}
      return null;
    }
  }

  Future<void> _clearStoredSession() async {
    _accessToken = null;
    _refreshToken = null;
    await _secureStorage.delete(key: _tokenKey);
    await _secureStorage.delete(key: _refreshTokenKey);
    await _secureStorage.delete(key: _sessionKey);
  }

  Future<void> _storeDeactivatedSession(Session session) async {
    _accessToken = null;
    _refreshToken = null;
    await _secureStorage.delete(key: _tokenKey);
    await _secureStorage.delete(key: _refreshTokenKey);
    await _secureStorage.write(
        key: _sessionKey, value: jsonEncode(_sessionToJson(session)));
  }

  Future<Session> _saveSessionFromUser(Map<String, dynamic> user) async {
    final session = _sessionFromUser(user);
    if (_accessToken != null) {
      await _secureStorage.write(key: _tokenKey, value: _accessToken);
      if (_refreshToken != null) {
        await _secureStorage.write(key: _refreshTokenKey, value: _refreshToken);
      }
      await _secureStorage.write(
          key: _sessionKey, value: jsonEncode(_sessionToJson(session)));
    }
    return session;
  }

  Session _sessionFromJson(Map<String, dynamic> json) => Session(
        role: UserRole.values.byName(json['role'] as String),
        status: AccountStatus.values.byName(json['status'] as String),
        memberNumber: json['member_number'] as String?,
        reason: json['reason'] as String?,
        deactivatedAt:
            DateTime.tryParse(json['deactivated_at']?.toString() ?? ''),
        deactivatedBy: json['deactivated_by'] as String?,
        reactivationUntil:
            DateTime.tryParse(json['reactivation_until']?.toString() ?? ''),
      );

  Map<String, dynamic> _sessionToJson(Session session) => {
        'role': session.role.name,
        'status': session.status.name,
        'member_number': session.memberNumber,
        'reason': session.reason,
        'deactivated_at': session.deactivatedAt?.toIso8601String(),
        'deactivated_by': session.deactivatedBy,
        'reactivation_until': session.reactivationUntil?.toIso8601String(),
      };

  @override
  Future<Session> registerClient(
      {required String firstName,
      required String lastName,
      required String email,
      String? phone,
      required String password,
      Uint8List? profilePhotoBytes,
      String? profilePhotoMime}) async {
    final result =
        await _request('POST', '/api/v1/auth/register/client', body: {
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'phone': phone,
      'password': password,
      if (profilePhotoBytes != null && profilePhotoMime != null)
        'photo_data': base64Encode(profilePhotoBytes),
      if (profilePhotoMime != null) 'photo_mime': profilePhotoMime,
    });
    return _sessionFromResponse(Map<String, dynamic>.from(result as Map));
  }

  @override
  Future<Map<String, dynamic>> registerClientGroupMembers(
      {required String planId,
      required List<Map<String, String>> members}) async {
    final result = await _request('POST', '/api/v1/client/group-members',
        body: {'plan_id': planId, 'members': members});
    return Map<String, dynamic>.from(result as Map);
  }

  @override
  Future<void> registerAdmin(
      {required String firstName,
      required String lastName,
      required String email,
      String? phone,
      required String password,
      required String inviteToken,
      Uint8List? profilePhotoBytes,
      String? profilePhotoMime}) async {
    await _request('POST', '/api/v1/auth/register/admin', body: {
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'phone': phone,
      'password': password,
      'invite_token': inviteToken,
      if (profilePhotoBytes != null && profilePhotoMime != null)
        'photo_data': base64Encode(profilePhotoBytes),
      if (profilePhotoMime != null) 'photo_mime': profilePhotoMime,
    });
  }

  @override
  Future<void> registerTrainer(
      {required String firstName,
      required String lastName,
      required String email,
      String? phone,
      required String password,
      required String specialty,
      required String certificationName,
      required Uint8List certificationBytes,
      Uint8List? profilePhotoBytes,
      String? profilePhotoMime}) async {
    final boundary = 'muskl-${DateTime.now().microsecondsSinceEpoch}';
    final request = await _client
        .postUrl(Uri.parse('$_baseUrl/api/v1/auth/register/trainer'));
    request.headers.set(HttpHeaders.contentTypeHeader,
        'multipart/form-data; boundary=$boundary');
    void field(String name, String value) {
      request.write(
          '--$boundary\r\nContent-Disposition: form-data; name="$name"\r\n\r\n$value\r\n');
    }

    field('first_name', firstName);
    field('last_name', lastName);
    field('email', email);
    field('password', password);
    field('specialty', specialty);
    if (phone != null && phone.isNotEmpty) field('phone', phone);
    if (profilePhotoBytes != null && profilePhotoMime != null) {
      field('photo_data', base64Encode(profilePhotoBytes));
      field('photo_mime', profilePhotoMime);
    }
    final extension = certificationName.split('.').last.toLowerCase();
    final mime = switch (extension) {
      'pdf' => 'application/pdf',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      _ => 'application/octet-stream',
    };
    request.write(
        '--$boundary\r\nContent-Disposition: form-data; name="certification"; filename="$certificationName"\r\nContent-Type: $mime\r\n\r\n');
    request.add(certificationBytes);
    request.write('\r\n--$boundary--\r\n');
    final response = await request.close().timeout(const Duration(seconds: 30));
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 400) {
      final decoded = text.isEmpty ? null : jsonDecode(text);
      final detail = decoded is Map ? decoded['detail'] : null;
      final message =
          detail is Map ? detail['message']?.toString() : detail?.toString();
      throw AuthException(AuthErrorType.server, message);
    }
  }

  @override
  Future<Map<String, dynamic>> getClientOnboardingOptions() async =>
      Map<String, dynamic>.from(await _request(
              'GET', '/api/v1/client/onboarding/options', authenticated: true)
          as Map);

  @override
  Future<List<Map<String, dynamic>>> getClientOnboardingRoutines(
      {required String goal,
      required int daysPerWeek,
      String? trainerId}) async {
    final path =
        Uri(path: '/api/v1/client/onboarding/routines', queryParameters: {
      'goal': goal,
      'days_per_week': '$daysPerWeek',
      if (trainerId != null) 'trainer_id': trainerId,
    }).toString();
    final rows = await _request('GET', path, authenticated: true) as List;
    return rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  @override
  Future<Session> completeClientOnboarding(
      {required String planId,
      String? trainerId,
      String? routineId,
      required String goal,
      required String experienceLevel,
      required int daysPerWeek,
      String? limitations}) async {
    final result = await _request('POST', '/api/v1/client/onboarding', body: {
      'plan_id': planId,
      'trainer_id': trainerId,
      'routine_id': routineId,
      'goal': goal,
      'experience_level': experienceLevel,
      'days_per_week': daysPerWeek,
      'limitations': limitations,
    });
    return _sessionFromResponse(Map<String, dynamic>.from(result as Map));
  }

  @override
  Future<List<Map<String, dynamic>>> getAdminUsers(
      {String search = '', String? role, String? status}) async {
    final query = <String, String>{};
    if (search.trim().isNotEmpty) query['search'] = search.trim();
    if (role != null) query['role'] = role;
    if (status != null) query['status'] = status;
    final path =
        Uri(path: '/api/v1/admin/users', queryParameters: query).toString();
    final rows = await _request('GET', path, authenticated: true) as List;
    return rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  @override
  Future<void> reassignClientTrainer(
      {required String clientId, required String trainerId}) async {
    await _request('POST', '/api/v1/admin/trainers/reassign',
        authenticated: true,
        body: {'client_id': clientId, 'new_trainer_id': trainerId});
  }

  @override
  Future<List<Map<String, dynamic>>> getAdminRoutines(
      {String search = '', String? goal}) async {
    final query = <String, String>{};
    if (search.trim().isNotEmpty) query['search'] = search.trim();
    if (goal != null) query['goal'] = goal;
    final path = Uri(
            path: '/api/v1/admin/routines',
            queryParameters: query.isEmpty ? null : query)
        .toString();
    final rows = await _request('GET', path, authenticated: true) as List;
    return rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  @override
  Future<Map<String, dynamic>> getAdminRoutine(
          {required String routineId}) async =>
      Map<String, dynamic>.from(await _request(
          'GET', '/api/v1/admin/routines/${Uri.encodeComponent(routineId)}',
          authenticated: true) as Map);

  @override
  Future<Map<String, dynamic>> getAdminDashboard() async =>
      Map<String, dynamic>.from(
          await _request('GET', '/api/v1/admin/dashboard', authenticated: true)
              as Map);

  @override
  Future<Map<String, dynamic>> getAdminGym() async => Map<String, dynamic>.from(
      await _request('GET', '/api/v1/admin/gym', authenticated: true) as Map);

  @override
  Future<Map<String, dynamic>> updateAdminGym(
          {required String name,
          required String address,
          required String phone,
          required String openingHours}) async =>
      Map<String, dynamic>.from(await _request('PATCH', '/api/v1/admin/gym',
          authenticated: true,
          body: {
            'name': name,
            'address': address,
            'phone': phone,
            'opening_hours': {'display': openingHours},
            'timezone': 'America/Mexico_City',
          }) as Map);

  @override
  Future<Map<String, dynamic>> getAdminPreferences() async =>
      Map<String, dynamic>.from(await _request(
          'GET', '/api/v1/admin/preferences',
          authenticated: true) as Map);

  @override
  Future<Map<String, dynamic>> updateAdminPreferences(
      {required bool newRequests}) async {
    return Map<String, dynamic>.from(await _request(
        'PATCH', '/api/v1/admin/preferences',
        authenticated: true, body: {'new_requests': newRequests}) as Map);
  }

  @override
  Future<List<Map<String, dynamic>>> getAdminNotifications() async {
    final rows = await _request('GET', '/api/v1/admin/notifications',
        authenticated: true) as List;
    return rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  @override
  Future<void> markAdminNotificationRead(
      {required String notificationId}) async {
    await _request('POST',
        '/api/v1/admin/notifications/${Uri.encodeComponent(notificationId)}/read',
        authenticated: true);
  }

  @override
  Future<List<Map<String, dynamic>>> getAdminPlans() async {
    final rows = await _request('GET', '/api/v1/admin/membership-plans',
        authenticated: true) as List;
    return rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  @override
  Future<Map<String, dynamic>> saveAdminPlan(
      {String? id,
      required String name,
      required double priceMxn,
      required int durationDays,
      required bool active}) async {
    final result = await _request(
        id == null ? 'POST' : 'PUT',
        id == null
            ? '/api/v1/admin/membership-plans'
            : '/api/v1/admin/membership-plans/${Uri.encodeComponent(id)}',
        authenticated: true,
        body: {
          'name': name,
          'price_mxn': priceMxn,
          'duration_days': durationDays,
          'active': active,
        }) as Map;
    return Map<String, dynamic>.from(result);
  }

  @override
  Future<List<Map<String, dynamic>>> getAdminInvites() async {
    final rows =
        await _request('GET', '/api/v1/admin/invite-codes', authenticated: true)
            as List;
    return rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  @override
  Future<Map<String, dynamic>> createAdminInvite() async =>
      Map<String, dynamic>.from(await _request(
          'POST', '/api/v1/admin/invite-codes',
          authenticated: true) as Map);

  @override
  Future<void> revokeAdminInvite({required String inviteId}) async {
    await _request(
        'DELETE', '/api/v1/admin/invite-codes/${Uri.encodeComponent(inviteId)}',
        authenticated: true);
  }

  @override
  Future<Map<String, dynamic>> getTrainerProfile() async =>
      Map<String, dynamic>.from(
          await _request('GET', '/api/v1/trainer/profile', authenticated: true)
              as Map);

  @override
  Future<Map<String, dynamic>> getOwnProfile() async =>
      Map<String, dynamic>.from(
          await _request('GET', '/api/v1/profile', authenticated: true) as Map);

  @override
  Future<Map<String, dynamic>> updateOwnProfilePhoto(
      {String? photoData,
      String? photoMime,
      bool removePhoto = false}) async {
    final body = <String, dynamic>{
      if (photoData != null) 'photo_data': photoData,
      if (photoMime != null) 'photo_mime': photoMime,
      if (removePhoto) 'remove_photo': true,
    };
    return Map<String, dynamic>.from(await _request(
            'PATCH', '/api/v1/profile/photo', authenticated: true, body: body)
        as Map);
  }

  @override
  Future<Map<String, dynamic>> updateTrainerProfile(
          {required String firstName,
          required String lastName,
          required String email,
          required String phone,
          required String specialty,
          required String bio,
          required Map<String, bool> notificationPreferences}) async =>
      Map<String, dynamic>.from(await _request(
          'PATCH', '/api/v1/trainer/profile',
          authenticated: true,
          body: {
            'first_name': firstName,
            'last_name': lastName,
            'email': email,
            'phone': phone,
            'specialty': specialty,
            'bio': bio,
            'notification_preferences': notificationPreferences,
          }) as Map);

  @override
  Future<void> changePassword(
      {required String currentPassword,
      required String newPassword,
      required String code}) async {
    await _request('PATCH', '/api/v1/auth/password',
        authenticated: true,
        body: {
          'current_password': currentPassword,
          'new_password': newPassword,
          'code': code,
        });
  }

  @override
  Future<String?> sendPasswordChangeCode() async {
    final result = await _request('POST', '/api/v1/auth/password/change-code',
        authenticated: true) as Map;
    return result['channel']?.toString();
  }

  @override
  Future<void> requestEmailChangeCode({required String newEmail}) async {
    await _request('POST', '/api/v1/auth/email-change/code',
        authenticated: true, body: {'new_email': newEmail});
  }

  @override
  Future<void> confirmEmailChange(
      {required String currentPassword, required String code}) async {
    await _request('POST', '/api/v1/auth/email-change/confirm',
        authenticated: true,
        body: {'current_password': currentPassword, 'code': code});
  }

  @override
  Future<List<Map<String, dynamic>>> getTrainerClients(
      {String search = ''}) async {
    final path = Uri(
            path: '/api/v1/trainer/clients',
            queryParameters:
                search.trim().isEmpty ? null : {'search': search.trim()})
        .toString();
    final rows = await _request('GET', path, authenticated: true) as List;
    return rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  @override
  Future<Map<String, dynamic>> getTrainerClient(
          {required String clientId}) async =>
      Map<String, dynamic>.from(await _request(
          'GET', '/api/v1/trainer/clients/${Uri.encodeComponent(clientId)}',
          authenticated: true) as Map);

  @override
  Future<List<Map<String, dynamic>>> getTrainerRoutines() async {
    final rows =
        await _request('GET', '/api/v1/trainer/routines', authenticated: true)
            as List;
    return rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  @override
  Future<Map<String, dynamic>> getTrainerRoutine(
          {required String routineId}) async =>
      Map<String, dynamic>.from(await _request(
          'GET', '/api/v1/trainer/routines/${Uri.encodeComponent(routineId)}',
          authenticated: true) as Map);

  @override
  Future<List<Map<String, dynamic>>> getTrainerExerciseCatalog(
      {String search = ''}) async {
    final path = Uri(
      path: '/api/v1/trainer/exercises',
      queryParameters: search.trim().isEmpty ? null : {'search': search.trim()},
    ).toString();
    final rows = await _request('GET', path, authenticated: true) as List;
    return rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  @override
  Future<void> createTrainerPhase(
      {required String routineId,
      required String name,
      required List<int> days,
      required List<String> exercises}) async {
    await _request('POST',
        '/api/v1/trainer/routines/${Uri.encodeComponent(routineId)}/phases',
        authenticated: true,
        body: {
          'name': name,
          'days': days,
          'exercises': exercises
              .map((exercise) => {
                    'name': exercise,
                    'sets': 4,
                    'reps': '8-12',
                    'rest_seconds': 60,
                  })
              .toList(),
        });
  }

  @override
  Future<void> publishTrainerPhase(
      {required String routineId, required String phaseId}) async {
    await _request('POST',
        '/api/v1/trainer/routines/${Uri.encodeComponent(routineId)}/phases/${Uri.encodeComponent(phaseId)}/publish',
        authenticated: true);
  }

  @override
  Future<void> createTrainerRoutine(
      {required String name,
      required String goal,
      required List<int> days,
      required List<Map<String, dynamic>> exercises}) async {
    await _request('POST', '/api/v1/trainer/routines',
        authenticated: true,
        body: {
          'name': name,
          'goal': goal,
          'days': days,
          'exercises': exercises
              .map((exercise) => {
                    'catalog_id': exercise['id'],
                    'name': exercise['name'],
                    'sets': 4,
                    'reps': '8-12',
                    'rest_seconds': 60
                  })
              .toList(),
        });
  }

  @override
  Future<void> publishTrainerRoutine({required String routineId}) async {
    await _request('POST',
        '/api/v1/trainer/routines/${Uri.encodeComponent(routineId)}/publish',
        authenticated: true);
  }

  @override
  Future<void> assignTrainerRoutine(
      {required String routineId,
      required String phaseId,
      required String clientId}) async {
    await _request('POST',
        '/api/v1/trainer/routines/${Uri.encodeComponent(routineId)}/assign',
        authenticated: true,
        body: {'phase_id': phaseId, 'client_id': clientId});
  }

  @override
  Future<List<Map<String, dynamic>>> getStaffRequests() async {
    final rows = await _request('GET', '/api/v1/admin/staff-requests',
        authenticated: true) as List;
    return rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  @override
  Future<String> getOwnTrainerCertificationDownloadUrl({
    required String certificationId,
  }) async {
    final result = await _request('GET',
        '/api/v1/trainer/certifications/${Uri.encodeComponent(certificationId)}/download',
        authenticated: true) as Map;
    return result['url'].toString();
  }

  @override
  Future<void> replaceOwnTrainerCertification({
    required String certificationId,
    required String filename,
    required Uint8List bytes,
  }) =>
      _uploadOwnTrainerCertification(
          certificationId: certificationId,
          filename: filename,
          bytes: bytes,
          retriedAfterRefresh: false);

  Future<void> _uploadOwnTrainerCertification({
    required String certificationId,
    required String filename,
    required Uint8List bytes,
    required bool retriedAfterRefresh,
  }) async {
    final path =
        '/api/v1/trainer/certifications/${Uri.encodeComponent(certificationId)}';
    final boundary = 'muskl-${DateTime.now().microsecondsSinceEpoch}';
    try {
      final request = await _client.putUrl(Uri.parse('$_baseUrl$path'));
      request.headers.set(HttpHeaders.contentTypeHeader,
          'multipart/form-data; boundary=$boundary');
      if (_accessToken != null) {
        request.headers
            .set(HttpHeaders.authorizationHeader, 'Bearer $_accessToken');
      }
      final safeName = filename
          .split(RegExp(r'[/\\]'))
          .last
          .replaceAll('"', '')
          .replaceAll('\r', '')
          .replaceAll('\n', '');
      final extension = safeName.split('.').last.toLowerCase();
      final mime = switch (extension) {
        'pdf' => 'application/pdf',
        'png' => 'image/png',
        'jpg' || 'jpeg' => 'image/jpeg',
        _ => 'application/octet-stream',
      };
      request.write(
          '--$boundary\r\nContent-Disposition: form-data; name="certification"; filename="$safeName"\r\nContent-Type: $mime\r\n\r\n');
      request.add(bytes);
      request.write('\r\n--$boundary--\r\n');
      final response =
          await request.close().timeout(const Duration(seconds: 90));
      final responseText = await response.transform(utf8.decoder).join();
      if (response.statusCode >= 400) {
        final decoded = responseText.isEmpty ? null : jsonDecode(responseText);
        final detail = decoded is Map ? decoded['detail'] : null;
        final code = detail is Map ? detail['code']?.toString() : null;
        if (response.statusCode == 401 &&
            !retriedAfterRefresh &&
            _refreshToken != null) {
          if (await _refreshAccessToken()) {
            return _uploadOwnTrainerCertification(
                certificationId: certificationId,
                filename: filename,
                bytes: bytes,
                retriedAfterRefresh: true);
          }
        }
        final message =
            detail is Map ? detail['message']?.toString() : detail?.toString();
        final type = switch (code) {
          'INVALID_CREDENTIALS' => AuthErrorType.invalidCredentials,
          'NOT_FOUND' => AuthErrorType.notFound,
          _ => AuthErrorType.server,
        };
        throw AuthException(type, message);
      }
    } on SocketException catch (error) {
      throw AuthException(AuthErrorType.offline, error.message);
    } on TimeoutException {
      throw const AuthException(AuthErrorType.offline);
    } on FormatException catch (error) {
      throw AuthException(AuthErrorType.server,
          'Respuesta inválida del servidor: ${error.message}');
    }
  }

  @override
  Future<String> getTrainerCertificationDownloadUrl({
    required String trainerId,
    required String certificationId,
  }) async {
    final result = await _request('GET',
        '/api/v1/admin/trainers/${Uri.encodeComponent(trainerId)}/certifications/${Uri.encodeComponent(certificationId)}/download',
        authenticated: true) as Map;
    return result['url'].toString();
  }

  @override
  Future<void> reviewStaffRequest(
      {required String userId, required bool approved, String? reason}) async {
    await _request('POST',
        '/api/v1/admin/staff-requests/${Uri.encodeComponent(userId)}/review',
        authenticated: true, body: {'approved': approved, 'reason': reason});
  }

  @override
  Future<List<Map<String, dynamic>>> getAccountDeletionRequests() async {
    final rows = await _request(
        'GET', '/api/v1/admin/account-deletion-requests',
        authenticated: true) as List;
    return rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  @override
  Future<void> reviewAccountDeletionRequest(
      {required String requestId, required bool approved, String? note}) async {
    await _request('POST',
        '/api/v1/admin/account-deletion-requests/${Uri.encodeComponent(requestId)}/review',
        authenticated: true, body: {'approved': approved, 'note': note});
  }

  Future<dynamic> _request(String method, String path,
      {Object? body,
      bool authenticated = false,
      bool retriedAfterRefresh = false}) async {
    try {
      final request =
          await _client.openUrl(method, Uri.parse('$_baseUrl$path'));
      request.headers.contentType = ContentType.json;
      if (authenticated && _accessToken != null) {
        request.headers
            .set(HttpHeaders.authorizationHeader, 'Bearer $_accessToken');
      }
      if (body != null) request.write(jsonEncode(body));
      final response =
          await request.close().timeout(const Duration(seconds: 90));
      final text = await response.transform(utf8.decoder).join();
      final decoded = text.isEmpty ? null : jsonDecode(text);
      if (response.statusCode >= 400) {
        final detail = decoded is Map ? decoded['detail'] : null;
        final code = detail is Map ? detail['code']?.toString() : null;
        final message =
            detail is Map ? detail['message']?.toString() : detail?.toString();
        if (response.statusCode == 401 &&
            authenticated &&
            !retriedAfterRefresh &&
            _refreshToken != null) {
          if (await _refreshAccessToken()) {
            return await _request(method, path,
                body: body,
                authenticated: authenticated,
                retriedAfterRefresh: true);
          }
        }
        final errorType = switch (code) {
          'INVALID_CREDENTIALS' => AuthErrorType.invalidCredentials,
          'NOT_FOUND' => AuthErrorType.notFound,
          'INVALID_CODE' => AuthErrorType.invalidCode,
          _ => AuthErrorType.server,
        };
        throw AuthException(errorType, message);
      }
      return decoded;
    } on SocketException catch (e) {
      throw AuthException(AuthErrorType.offline, e.message);
    } on TimeoutException {
      throw const AuthException(AuthErrorType.offline);
    } on FormatException catch (e) {
      throw AuthException(AuthErrorType.server,
          'Respuesta inválida del servidor: ${e.message}');
    }
  }

  Future<bool> _refreshAccessToken() async {
    final running = _refreshing;
    if (running != null) return running;
    final task = _performRefresh();
    _refreshing = task;
    try {
      return await task;
    } finally {
      _refreshing = null;
    }
  }

  Future<bool> _performRefresh() async {
    final refreshToken = _refreshToken;
    if (refreshToken == null) return false;
    try {
      final response = await _request('POST', '/api/v1/auth/refresh',
          body: {'refresh_token': refreshToken});
      final session = await _sessionFromResponse(
          Map<String, dynamic>.from(response as Map));
      onSessionChanged?.call(session);
      return true;
    } on AuthException catch (error) {
      if (error.type == AuthErrorType.offline) rethrow;
      try {
        final status = await _request('POST', '/api/v1/auth/session-status',
            body: {'refresh_token': refreshToken});
        final user = Map<String, dynamic>.from((status as Map)['user'] as Map);
        final session = _sessionFromUser(user);
        if (session.status == AccountStatus.deactivated) {
          await _storeDeactivatedSession(session);
          onSessionChanged?.call(session);
          return false;
        }
      } on AuthException catch (statusError) {
        if (statusError.type == AuthErrorType.offline) rethrow;
      } catch (_) {}
      await _clearStoredSession();
      onSessionChanged?.call(null);
      return false;
    } catch (_) {
      await _clearStoredSession();
      onSessionChanged?.call(null);
      return false;
    }
  }

  Future<Session> _sessionFromResponse(Map<String, dynamic> response) async {
    final user = Map<String, dynamic>.from(response['user'] as Map);
    if (response.containsKey('access_token')) {
      _accessToken = response['access_token'] as String?;
    }
    if (response.containsKey('refresh_token')) {
      _refreshToken = response['refresh_token'] as String?;
    }
    final session = _sessionFromUser(user);
    if (session.status == AccountStatus.deactivated &&
        !response.containsKey('access_token')) {
      await _storeDeactivatedSession(session);
      return session;
    }
    return _saveSessionFromUser(user);
  }

  Session _sessionFromUser(Map<String, dynamic> user) {
    final role = switch (user['role']) {
      'trainer' => UserRole.trainer,
      'admin' => UserRole.admin,
      _ => UserRole.client,
    };
    final status = switch (user['status']) {
      'active_no_onboarding' => AccountStatus.activeNoOnboarding,
      'pending' => AccountStatus.pending,
      'rejected' => AccountStatus.rejected,
      'deactivated' => AccountStatus.deactivated,
      _ => AccountStatus.activeOnboarded,
    };
    return Session(
      role: role,
      status: status,
      memberNumber: user['member_number'] as String?,
      reason: (user['deactivation_reason'] ?? user['status_reason']) as String?,
      deactivatedAt:
          DateTime.tryParse(user['deactivated_at']?.toString() ?? ''),
      deactivatedBy: user['deactivated_by'] as String?,
      reactivationUntil:
          DateTime.tryParse(user['reactivation_until']?.toString() ?? ''),
    );
  }

  @override
  Future<Session> signIn(
      {required String identifier, required String password}) async {
    final result = await _request('POST', '/api/v1/auth/login', body: {
      'identifier': identifier,
      'password': password,
    });
    return _sessionFromResponse(Map<String, dynamic>.from(result as Map));
  }

  @override
  Future<void> sendResetCode(String email) async {
    await _request('POST', '/api/v1/auth/password/reset-code',
        body: {'email': email});
  }

  @override
  Future<void> verifyResetCode(
      {required String email, required String code}) async {
    await _request('POST', '/api/v1/auth/password/verify-code',
        body: {'email': email, 'code': code});
  }

  @override
  Future<void> resetPassword(
      {required String email,
      required String code,
      required String newPassword}) async {
    await _request('POST', '/api/v1/auth/password/reset', body: {
      'email': email,
      'code': code,
      'new_password': newPassword,
    });
    await _clearStoredSession();
  }

  @override
  Future<void> signOut() async {
    try {
      if (_accessToken != null) {
        await _request('POST', '/api/v1/auth/logout', authenticated: true);
      }
    } finally {
      await _clearStoredSession();
    }
  }

  @override
  Future<String?> deactivateMember(
      {required String memberNumber,
      String? userId,
      required String reason,
      required String by,
      DateTime? at,
      DateTime? reactivationUntil}) async {
    final parts = reason.split(':');
    final category = parts.first.trim();
    final path = userId == null
        ? '/api/v1/admin/members/${Uri.encodeComponent(memberNumber)}/deactivate'
        : '/api/v1/admin/users/${Uri.encodeComponent(userId)}/deactivate';
    final result = await _request('PATCH', path, authenticated: true, body: {
      'reason': category,
      'note': parts.length > 1 ? parts.skip(1).join(':').trim() : null,
    }) as Map;
    return result['notification_channel']?.toString();
  }

  @override
  Future<Map<String, dynamic>> getClientDashboard() async =>
      Map<String, dynamic>.from(
          await _request('GET', '/api/v1/client/dashboard', authenticated: true)
              as Map);

  @override
  Future<Map<String, dynamic>> updateClientProfile(
      {String? firstName,
      String? lastName,
      String? email,
      String? phone,
      String? photoData,
      String? photoMime,
      bool removePhoto = false}) async {
    final body = <String, dynamic>{
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      if (email != null) 'email': email,
      if (phone != null) 'phone': phone,
      if (photoData != null) 'photo_data': photoData,
      if (photoMime != null) 'photo_mime': photoMime,
      if (removePhoto) 'remove_photo': true,
    };
    return Map<String, dynamic>.from(await _request(
            'PATCH', '/api/v1/client/profile', authenticated: true, body: body)
        as Map);
  }

  @override
  Future<Map<String, dynamic>> getClientAttendance(
      {required int year, required int month}) async {
    final path = Uri(
        path: '/api/v1/client/attendance',
        queryParameters: {'year': '$year', 'month': '$month'}).toString();
    return Map<String, dynamic>.from(
        await _request('GET', path, authenticated: true) as Map);
  }

  @override
  Future<Map<String, dynamic>> checkInClientAttendance() async =>
      Map<String, dynamic>.from(await _request(
              'POST', '/api/v1/client/attendance/check-in', authenticated: true)
          as Map);

  @override
  Future<Map<String, dynamic>> getClientRoutine({required int day}) async {
    final path =
        Uri(path: '/api/v1/client/routine', queryParameters: {'day': '$day'})
            .toString();
    return Map<String, dynamic>.from(
        await _request('GET', path, authenticated: true) as Map);
  }

  @override
  Future<Map<String, dynamic>> completeClientExercise(
      {required String exerciseId}) async {
    final result = await _request(
      'POST',
      '/api/v1/client/routine/exercises/${Uri.encodeComponent(exerciseId)}/complete',
      authenticated: true,
    );
    return Map<String, dynamic>.from(result as Map);
  }

  @override
  Future<List<Map<String, dynamic>>> getClientNotifications() async {
    final rows = await _request('GET', '/api/v1/client/notifications',
        authenticated: true) as List;
    return rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  @override
  Future<void> markClientNotificationRead(
      {required String notificationId}) async {
    await _request('POST',
        '/api/v1/client/notifications/${Uri.encodeComponent(notificationId)}/read',
        authenticated: true);
  }

  @override
  Future<List<Map<String, dynamic>>> getTrainerNotifications() async {
    final rows = await _request('GET', '/api/v1/trainer/notifications',
        authenticated: true) as List;
    return rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  @override
  Future<void> markTrainerNotificationRead(
      {required String notificationId}) async {
    await _request('POST',
        '/api/v1/trainer/notifications/${Uri.encodeComponent(notificationId)}/read',
        authenticated: true);
  }

  @override
  Future<Map<String, dynamic>> completeClientWorkout(
      {int? durationSeconds}) async {
    final result = await _request('POST', '/api/v1/client/routine/complete',
        authenticated: true, body: {'duration_seconds': durationSeconds});
    return Map<String, dynamic>.from(result as Map);
  }

  @override
  Future<void> requestAccountDeletion() async {
    await _request('POST', '/api/v1/client/account-deletion-request',
        authenticated: true);
  }

  @override
  Future<void> reactivateMember(
      {required String memberNumber,
      String? userId,
      required String by}) async {
    final path = userId == null
        ? '/api/v1/admin/members/${Uri.encodeComponent(memberNumber)}/reactivate'
        : '/api/v1/admin/users/${Uri.encodeComponent(userId)}/reactivate';
    await _request('PATCH', path, authenticated: true);
  }
}

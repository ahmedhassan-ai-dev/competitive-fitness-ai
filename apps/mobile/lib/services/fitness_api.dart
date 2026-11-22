/// Minimal Android HTTP client for the configured FastAPI backend.
/// JWT is intentionally memory-only for this MVP. No credentials or tokens
/// are persisted in SharedPreferences or printed in logs.
import 'dart:convert';
import 'dart:io';

class FitnessApiException implements Exception {
  FitnessApiException(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class FitnessApi {
  FitnessApi._();
  static final FitnessApi instance = FitnessApi._();
  static const baseUrl = String.fromEnvironment('FITNESS_API_BASE_URL');
  String? _token;
  String? _userId;
  String? _username;

  bool get isConfigured => baseUrl.trim().isNotEmpty;
  bool get signedIn => isConfigured && _token != null;
  String? get userId => _userId;
  String? get username => _username;

  void logout() {
    _token = null;
    _userId = null;
    _username = null;
  }

  Future<void> authenticate({required String username, required String password,
      required bool register}) async {
    final json = await _request('POST', '/api/v1/auth/${register ? 'register' : 'token'}',
        body: {'username': username, 'password': password}, authorized: false);
    if (json is! Map || json['access_token'] is! String || json['user_id'] is! String) {
      throw FitnessApiException('Invalid response from authentication server.');
    }
    _token = json['access_token'] as String;
    _userId = json['user_id'] as String;
    _username = username;
  }

  Future<List<Map<String, dynamic>>> listRooms() async {
    final data = await _request('GET', '/api/v1/rooms');
    if (data is! List) throw FitnessApiException('Invalid rooms response.');
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> room(String id) => _object('GET', '/api/v1/rooms/$id');
  Future<Map<String, dynamic>> createRoom(String title) =>
      _object('POST', '/api/v1/rooms', body: {'title': title, 'max_players': 8});
  Future<Map<String, dynamic>> joinRoom(String code) =>
      _object('POST', '/api/v1/rooms/join', body: {'invite_code': code.trim().toUpperCase()});
  Future<Map<String, dynamic>> startRoom(String id) => _object('POST', '/api/v1/rooms/$id/start');
  Future<Map<String, dynamic>> finishRoom(String id) => _object('POST', '/api/v1/rooms/$id/finish');
  Future<Map<String, dynamic>> submitWorkout(String roomId, String workoutId) =>
      _object('POST', '/api/v1/rooms/$roomId/submissions', body: {'workout_id': workoutId});
  Future<Map<String, dynamic>> saveWorkout({required String exercise,
      required int reps, required int holdMs, required int activeMs}) =>
      _object('POST', '/api/v1/workouts', body: {
        'exercise': exercise, 'reps': reps, 'hold_ms': holdMs, 'active_ms': activeMs,
      });

  Future<Map<String, dynamic>> _object(String method, String path, {Object? body}) async {
    final data = await _request(method, path, body: body);
    if (data is! Map) throw FitnessApiException('Invalid server response.');
    return Map<String, dynamic>.from(data);
  }

  Future<dynamic> _request(String method, String path,
      {Object? body, bool authorized = true}) async {
    if (!isConfigured) {
      throw FitnessApiException('Server address missing. Use --dart-define=FITNESS_API_BASE_URL=https://...');
    }
    final uri = Uri.tryParse('${baseUrl.replaceFirst(RegExp(r"/$"), "")}$path');
    if (uri == null || uri.host.isEmpty || !{'http', 'https'}.contains(uri.scheme)) {
      throw FitnessApiException('Invalid server URL.');
    }
    // HTTP is allowed only during local debug builds. Release needs HTTPS.
    if (uri.scheme != 'https' && const bool.fromEnvironment('dart.vm.product')) {
      throw FitnessApiException('Release builds require HTTPS.');
    }
    if (authorized && _token == null) throw FitnessApiException('Log in first.', 401);
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 7);
    try {
      final request = await http.openUrl(method, uri).timeout(const Duration(seconds: 10));
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (authorized) request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close().timeout(const Duration(seconds: 15));
      final text = await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 15));
      dynamic payload;
      try { payload = jsonDecode(text); } on FormatException {
        throw FitnessApiException('Unexpected server response (${response.statusCode}).');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 401 && authorized) logout();
        final detail = payload is Map ? payload['detail'] : null;
        final msg = detail is String ? detail :
            response.statusCode == 401 ? 'Session expired. Log in again.' :
            'Request failed (${response.statusCode}).';
        throw FitnessApiException(msg, response.statusCode);
      }
      return payload;
    } on SocketException {
      throw FitnessApiException('Cannot reach the server. Check Wi-Fi and the server IP.');
    } on HandshakeException {
      throw FitnessApiException('HTTPS certificate error. Check the server certificate.');
    } on FitnessApiException {
      rethrow;
    } catch (_) {
      throw FitnessApiException('The request timed out or the network is unavailable.');
    } finally {
      http.close(force: true);
    }
  }
}

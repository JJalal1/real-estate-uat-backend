import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/local/stage5_device_store.dart';
import '../../../core/local/stage6_secure_session_store.dart';
import '../../../core/network/api_client.dart';
import '../domain/auth_user.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(dioProvider));
});

class AuthRepository {
  AuthRepository(this._dio);

  final Dio _dio;
  final _store = Stage6SecureSessionStore.instance;

  void _requireSession(int epoch) {
    if (_store.sessionEpoch != epoch) throw StateError('ACCOUNT_CHANGED');
  }

  Future<AuthUser?> restoreSession() async {
    final epoch = _store.sessionEpoch;
    final token = await _store.readToken();
    _requireSession(epoch);
    if (token == null) return null;
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/auth/me',
        options: _bearer(token),
      );
      _requireSession(epoch);
      return _userFromData(response.data);
    } on DioException catch (error) {
      _requireSession(epoch);
      if (error.response?.statusCode == 401 ||
          error.response?.statusCode == 403) {
        await _store.deleteTokenIfMatches(token);
        _requireSession(epoch);
        return null;
      }
      rethrow;
    }
  }

  Future<WhatsAppAuthPending> startWhatsApp({required String phone, String? name}) async {
    final epoch = _store.beginSessionChange();
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/whatsapp/start',
      data: {
        'intent': name?.trim().isNotEmpty == true ? 'continue' : 'login',
        'phone': phone.trim(),
        if (name?.trim().isNotEmpty == true) 'name': name!.trim(),
      },
    );
    _requireSession(epoch);
    final data = response.data?['data'];
    if (data is! Map<String, dynamic>) {
      throw StateError('Invalid WhatsApp authentication response.');
    }
    return WhatsAppAuthPending(
      phone: data['phone']?.toString() ?? phone.trim(),
      name: name,
      isNewAccount: data['is_new_account'] == true || data['is_new_account'] == 1,
      debugCode: _nullableText(data['debug_code']),
    );
  }

  Future<AuthResult> verifyWhatsApp(
      WhatsAppAuthPending pending, String code) async {
    final epoch = _store.beginSessionChange();
    if (pending.isEmail) {
      final response = await _dio.post<Map<String, dynamic>>('/auth/email/login', data: {
        'email': pending.email, 'code': code.trim(), if (pending.name != null) 'name': pending.name!.trim(),
      });
      return _acceptLoginResponse(response.data, epoch);
    }
    final legacyKey = await Stage5DeviceStore.instance.ownerKey();
    _requireSession(epoch);
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/whatsapp/verify',
      data: {
        'phone': pending.phone,
        if (pending.name != null) 'name': pending.name!.trim(),
        'code': code.trim(),
        'legacy_owner_key': legacyKey,
      },
    );
    return _acceptLoginResponse(response.data, epoch);
  }

  Future<WhatsAppAuthPending> startEmail({required String email, String? name}) async {
    final epoch = _store.beginSessionChange();
    final response = await _dio.post<Map<String, dynamic>>('/auth/email/start', data: {
      'intent': name?.trim().isNotEmpty == true ? 'continue' : 'login',
      'email': email.trim(), if (name?.trim().isNotEmpty == true) 'name': name!.trim(),
    });
    _requireSession(epoch);
    final data = response.data?['data'];
    if (data is! Map<String, dynamic>) throw StateError('Invalid email authentication response.');
    return WhatsAppAuthPending(phone: '', email: data['email']?.toString() ?? email.trim(), name: name,
      isNewAccount: false, debugCode: _nullableText(data['debug_code']));
  }

  Future<void> requestEmailVerification() async {
    final epoch = _store.sessionEpoch;
    await _dio.post<void>('/auth/email/request', options: await requiredAuthOptions());
    _requireSession(epoch);
  }

  Future<AuthUser> verifyEmail(String code) async {
    final epoch = _store.sessionEpoch;
    final response = await _dio.post<Map<String, dynamic>>('/auth/email/verify',
      data: {'code': code.trim()}, options: await requiredAuthOptions());
    _requireSession(epoch);
    return _userFromData(response.data);
  }

  Future<AuthResult> register({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    final epoch = _store.beginSessionChange();
    final legacyKey = await Stage5DeviceStore.instance.ownerKey();
    _requireSession(epoch);
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/register',
      data: {
        'name': name.trim(),
        'email': email.trim(),
        'phone': phone.trim(),
        'password': password,
        'password_confirmation': password,
        'legacy_owner_key': legacyKey,
      },
    );
    return _acceptLoginResponse(response.data, epoch);
  }

  Future<AuthResult> login({
    required String login,
    required String password,
  }) async {
    final epoch = _store.beginSessionChange();
    final legacyKey = await Stage5DeviceStore.instance.ownerKey();
    _requireSession(epoch);
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {
        'login': login.trim(),
        'password': password,
        'legacy_owner_key': legacyKey,
      },
    );
    return _acceptLoginResponse(response.data, epoch);
  }

  Future<void> logout() async {
    final epoch = _store.beginSessionChange();
    final token = await _store.readToken();
    try {
      if (token != null && epoch == _store.sessionEpoch) {
        await _dio.post<void>('/auth/logout', options: _bearer(token));
      }
    } finally {
      if (token != null) await _store.deleteTokenIfMatches(token);
    }
  }

  Future<String?> requestPhoneVerification() async {
    final epoch = _store.sessionEpoch;
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/phone/request',
      data: const <String, dynamic>{},
      options: await requiredAuthOptions(),
    );
    _requireSession(epoch);
    final data = response.data?['data'];
    if (data is Map<String, dynamic>) {
      final code = data['debug_code']?.toString().trim();
      if (code != null && code.isNotEmpty) return code;
    }
    return null;
  }

  Future<AuthUser> verifyPhone(String code) async {
    final epoch = _store.sessionEpoch;
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/phone/verify',
      data: {'code': code.trim()},
      options: await requiredAuthOptions(),
    );
    _requireSession(epoch);
    return _userFromData(response.data);
  }

  Future<AuthUser> completeProfile(String name) async {
    final epoch = _store.sessionEpoch;
    final response = await _dio.patch<Map<String, dynamic>>(
      '/auth/profile',
      data: {'name': name.trim()},
      options: await requiredAuthOptions(),
    );
    _requireSession(epoch);
    return _userFromData(response.data);
  }

  Future<AuthUser> updateProfile({
    required String name,
    required String phone,
    String? email,
  }) async {
    final epoch = _store.sessionEpoch;
    final response = await _dio.patch<Map<String, dynamic>>(
      '/auth/profile',
      data: {'name': name.trim(), 'phone': phone.trim(), if (email?.trim().isNotEmpty == true) 'email': email!.trim()},
      options: await requiredAuthOptions(),
    );
    _requireSession(epoch);
    return _userFromData(response.data);
  }

  Future<String?> requestPasswordReset(String login) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/password/forgot',
      data: {'login': login.trim()},
    );
    final data = response.data?['data'];
    if (data is Map<String, dynamic>) {
      final code = data['debug_code']?.toString().trim();
      if (code != null && code.isNotEmpty) return code;
    }
    return null;
  }

  Future<void> resetPassword({
    required String login,
    required String code,
    required String password,
  }) async {
    final epoch = _store.beginSessionChange();
    final previous = await _store.readToken();
    _requireSession(epoch);
    await _dio.post<void>(
      '/auth/password/reset',
      data: {
        'login': login.trim(),
        'code': code.trim(),
        'password': password,
        'password_confirmation': password,
      },
    );
    _requireSession(epoch);
    if (previous != null) await _store.deleteTokenIfMatches(previous);
    _requireSession(epoch);
  }

  Future<Options> requiredAuthOptions() async {
    final epoch = _store.sessionEpoch;
    final token = await _store.readToken();
    _requireSession(epoch);
    if (token == null) throw StateError('AUTH_REQUIRED');
    return _bearer(token);
  }

  Future<Options?> optionalAuthOptions() async {
    final epoch = _store.sessionEpoch;
    final token = await _store.readToken();
    _requireSession(epoch);
    return token == null ? null : _bearer(token);
  }

  Future<AuthResult> _acceptLoginResponse(Map<String, dynamic>? body, int epoch) async {
    _requireSession(epoch);
    final data = body?['data'];
    if (data is! Map<String, dynamic>) {
      throw StateError('Invalid authentication response.');
    }
    final token = data['token']?.toString().trim();
    final userData = data['user'];
    if (token == null || token.isEmpty || userData is! Map<String, dynamic>) {
      throw StateError('Invalid authentication response.');
    }
    final user = AuthUser.fromJson(userData);
    if (user.id <= 0) throw StateError('Invalid authentication response.');
    final written = await _store.writeTokenIfCurrent(token, epoch);
    if (!written || epoch != _store.sessionEpoch) {
      await _store.deleteTokenIfMatches(token);
      throw StateError('ACCOUNT_CHANGED');
    }
    final raw = data['legacy_listings_claimed'];
    final claimed =
        raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '') ?? 0;
    return AuthResult(
      user: user,
      legacyListingsClaimed: claimed,
    );
  }

  AuthUser _userFromData(Map<String, dynamic>? body) {
    final data = body?['data'];
    if (data is Map<String, dynamic>) {
      final nested = data['user'];
      if (nested is Map<String, dynamic>) return AuthUser.fromJson(nested);
      return AuthUser.fromJson(data);
    }
    throw StateError('Invalid user response.');
  }

  String? _nullableText(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  Options _bearer(String token) => Options(
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
}


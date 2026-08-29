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

  Future<AuthUser?> restoreSession() async {
    final token = await _store.readToken();
    if (token == null) return null;
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/auth/me',
        options: _bearer(token),
      );
      return _userFromData(response.data);
    } on DioException catch (error) {
      if (error.response?.statusCode == 401 ||
          error.response?.statusCode == 403) {
        await _store.deleteToken();
        return null;
      }
      rethrow;
    }
  }

  Future<WhatsAppAuthPending> startWhatsApp({required String phone}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/whatsapp/start',
      data: {
        'intent': 'continue',
        'phone': phone.trim(),
      },
    );
    final data = response.data?['data'];
    if (data is! Map<String, dynamic>) {
      throw StateError('Invalid WhatsApp authentication response.');
    }
    return WhatsAppAuthPending(
      phone: data['phone']?.toString() ?? phone.trim(),
      isNewAccount: data['is_new_account'] == true || data['is_new_account'] == 1,
      debugCode: _nullableText(data['debug_code']),
    );
  }

  Future<AuthResult> verifyWhatsApp(
      WhatsAppAuthPending pending, String code) async {
    final legacyKey = await Stage5DeviceStore.instance.ownerKey();
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/whatsapp/verify',
      data: {
        'phone': pending.phone,
        'code': code.trim(),
        'legacy_owner_key': legacyKey,
      },
    );
    return _acceptLoginResponse(response.data);
  }

  Future<AuthResult> register({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    final legacyKey = await Stage5DeviceStore.instance.ownerKey();
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
    return _acceptLoginResponse(response.data);
  }

  Future<AuthResult> login({
    required String login,
    required String password,
  }) async {
    final legacyKey = await Stage5DeviceStore.instance.ownerKey();
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {
        'login': login.trim(),
        'password': password,
        'legacy_owner_key': legacyKey,
      },
    );
    return _acceptLoginResponse(response.data);
  }

  Future<void> logout() async {
    final token = await _store.readToken();
    try {
      if (token != null) {
        await _dio.post<void>('/auth/logout', options: _bearer(token));
      }
    } finally {
      await _store.deleteToken();
    }
  }

  Future<String?> requestPhoneVerification() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/phone/request',
      data: const <String, dynamic>{},
      options: await requiredAuthOptions(),
    );
    final data = response.data?['data'];
    if (data is Map<String, dynamic>) {
      final code = data['debug_code']?.toString().trim();
      if (code != null && code.isNotEmpty) return code;
    }
    return null;
  }

  Future<AuthUser> verifyPhone(String code) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/phone/verify',
      data: {'code': code.trim()},
      options: await requiredAuthOptions(),
    );
    return _userFromData(response.data);
  }

  Future<AuthUser> completeProfile(String name) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/auth/profile',
      data: {'name': name.trim()},
      options: await requiredAuthOptions(),
    );
    return _userFromData(response.data);
  }

  Future<AuthUser> updateProfile({
    required String name,
    required String phone,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/auth/profile',
      data: {'name': name.trim(), 'phone': phone.trim()},
      options: await requiredAuthOptions(),
    );
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
    await _dio.post<void>(
      '/auth/password/reset',
      data: {
        'login': login.trim(),
        'code': code.trim(),
        'password': password,
        'password_confirmation': password,
      },
    );
    await _store.deleteToken();
  }

  Future<Options> requiredAuthOptions() async {
    final token = await _store.readToken();
    if (token == null) throw StateError('AUTH_REQUIRED');
    return _bearer(token);
  }

  Future<Options?> optionalAuthOptions() async {
    final token = await _store.readToken();
    return token == null ? null : _bearer(token);
  }

  Future<AuthResult> _acceptLoginResponse(Map<String, dynamic>? body) async {
    final data = body?['data'];
    if (data is! Map<String, dynamic>) {
      throw StateError('Invalid authentication response.');
    }
    final token = data['token']?.toString().trim();
    final userData = data['user'];
    if (token == null || token.isEmpty || userData is! Map<String, dynamic>) {
      throw StateError('Invalid authentication response.');
    }
    await _store.writeToken(token);
    final raw = data['legacy_listings_claimed'];
    final claimed =
        raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '') ?? 0;
    return AuthResult(
      user: AuthUser.fromJson(userData),
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

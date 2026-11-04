import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/local/stage6_secure_session_store.dart';
import '../../account/data/auth_repository.dart';

final pushRegistrationRepositoryProvider = Provider<PushRegistrationRepository>((ref) {
  final repository = PushRegistrationRepository(
    ref.watch(dioProvider),
    ref.watch(authRepositoryProvider),
  );
  ref.onDispose(repository.invalidate);
  return repository;
});

final pushCapabilityProvider = FutureProvider<bool>((ref) {
  return ref.watch(pushRegistrationRepositoryProvider).isConfigured();
});

class PushRegistrationRepository {
  PushRegistrationRepository(this._dio, this._auth);

  static const MethodChannel _channel = MethodChannel('real_estate/push');
  static const int _appBuild = int.fromEnvironment('APP_BUILD_NUMBER', defaultValue: 1);

  final Dio _dio;
  final AuthRepository _auth;
  int _revision = 0;
  void invalidate() => ++_revision;

  void _verify(int epoch, int revision) {
    if (epoch != Stage6SecureSessionStore.instance.sessionEpoch || revision != _revision) {
      throw StateError('ACCOUNT_CHANGED');
    }
  }

  String _sessionToken(Options options) {
    final authorization = options.headers?['Authorization'];
    if (authorization is! String || !authorization.startsWith('Bearer ')) {
      throw StateError('AUTH_REQUIRED');
    }
    return authorization.substring(7);
  }

  Future<bool> isConfigured() async {
    final value = await _channel.invokeMethod<bool>('isConfigured');
    return value == true;
  }

  Future<bool> syncIfGranted() => _syncRegistration('currentRegistration');

  Future<bool> requestAndRegister() => _syncRegistration('requestRegistration');

  Future<bool> _syncRegistration(String nativeMethod) async {
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    final revision = _revision;
    // Capture the bearer before native permission/token work; a late result
    // must never obtain the next account's credentials.
    final options = await _auth.requiredAuthOptions();
    _verify(epoch, revision);
    final sessionToken = _sessionToken(options);
    final registration = await _registration(nativeMethod, {'session_token': sessionToken});
    _verify(epoch, revision);
    if (!registration.configured) return false;
    if (!registration.canRegister) {
      // A disabled permission or malformed native token must never create a
      // server registration. Revoke a previous registration only when we have
      // a valid installation identifier to target.
      if (registration.hasUsableInstallationId) {
        await _removeServerRegistration(registration.installationId, options);
        _verify(epoch, revision);
      }
      return false;
    }
    final response = await _register(registration, options);
    _verify(epoch, revision);
    final data = response.data?['data'];
    if (data is! Map || data['registered'] != true || data['user_id'] is! num ||
        (data['user_id'] as num).toInt() <= 0 || registration.generation.isEmpty) {
      throw StateError('Invalid push registration receipt');
    }
    final confirmed = await _channel.invokeMethod<bool>('confirmRegistration', {
      'session_token': sessionToken, 'generation': registration.generation,
      'token': registration.token, 'user_id': '${data['user_id']}',
    });
    _verify(epoch, revision);
    return confirmed == true;
  }

  Future<void> unregister() => _unregister(false);
  Future<void> disable() => _unregister(true);

  Future<void> _unregister(bool requireLocal) async {
    ++_revision;
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    // Native invalidates consent, queued callbacks and tray notifications
    // synchronously, even if either the API or Firebase is unreachable.
    PushNativeRegistration registration;
    try {
      registration = await _registration('deleteToken');
      if (requireLocal && !registration.hasUsableInstallationId) {
        throw StateError('Missing native revocation receipt');
      }
    } catch (_) {
      if (requireLocal) rethrow;
      return;
    }
    try {
      if (registration.hasUsableInstallationId && epoch == Stage6SecureSessionStore.instance.sessionEpoch) {
        final options = await _auth.requiredAuthOptions();
        if (epoch == Stage6SecureSessionStore.instance.sessionEpoch) {
          await _removeServerRegistration(registration.installationId, options);
        }
      }
    } catch (_) {
      // Server logout also revokes devices. Local fencing does not wait for it.
    }
  }

  Future<void> _removeServerRegistration(String installationId, Options options) async {
    if (installationId.length < 16 || installationId.length > 200) return;
    await _dio.delete<void>(
      '/push/devices',
      data: {'installation_id': installationId},
      options: options,
    );
  }

  Future<Response<Map<String, dynamic>>> _register(PushNativeRegistration registration, Options options) {
    return _dio.post<Map<String, dynamic>>(
      '/push/devices',
      data: {
        'platform': 'android',
        'token': registration.token,
        'installation_id': registration.installationId,
        'app_build': _appBuild,
      },
      options: options,
    );
  }

  Future<PushNativeRegistration> _registration(String method, [Map<String, dynamic>? arguments]) async {
    final raw = await _channel.invokeMapMethod<String, dynamic>(method, arguments);
    return PushNativeRegistration.fromMap(raw ?? const <String, dynamic>{});
  }
}

class PushNativeRegistration {
  const PushNativeRegistration({
    required this.configured,
    required this.granted,
    required this.installationId,
    this.token,
    this.generation = '',
  });

  final bool configured;
  final bool granted;
  final String installationId;
  final String? token;
  final String generation;

  // Match Laravel's bounded registration contract before sending sensitive
  // Firebase token material. Native Android supplies a stable UUID.
  bool get hasUsableInstallationId =>
      installationId.length >= 16 && installationId.length <= 200;
  bool get hasUsableToken =>
      token != null && token!.length >= 20 && token!.length <= 4096;
  bool get canRegister =>
      configured && granted && hasUsableInstallationId && hasUsableToken &&
      RegExp(r'^[A-Za-z0-9-]{16,64}$').hasMatch(generation);

  factory PushNativeRegistration.fromMap(Map<String, dynamic> json) {
    // The native bridge contract is String, never coerce another type into a
    // token or installation ID that could be sent to the backend.
    final rawToken = json['token'];
    final rawInstallationId = json['installation_id'];
    final token = rawToken is String ? rawToken.trim() : null;
    return PushNativeRegistration(
      configured: json['configured'] == true,
      granted: json['granted'] == true,
      installationId: rawInstallationId is String ? rawInstallationId.trim() : '',
      token: token == null || token.isEmpty ? null : token,
      generation: json['generation'] is String ? json['generation'] as String : '',
    );
  }
}

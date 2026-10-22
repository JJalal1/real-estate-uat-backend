import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../account/data/auth_repository.dart';

final pushRegistrationRepositoryProvider = Provider<PushRegistrationRepository>((ref) {
  return PushRegistrationRepository(
    ref.watch(dioProvider),
    ref.watch(authRepositoryProvider),
  );
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

  Future<bool> isConfigured() async {
    final value = await _channel.invokeMethod<bool>('isConfigured');
    return value == true;
  }

  Future<bool> syncIfGranted() async {
    final registration = await _registration('currentRegistration');
    if (!registration.configured || !registration.granted || registration.token == null) {
      return false;
    }
    await _register(registration);
    return true;
  }

  Future<bool> requestAndRegister() async {
    final registration = await _registration('requestRegistration');
    if (!registration.configured || !registration.granted || registration.token == null) {
      return false;
    }
    await _register(registration);
    return true;
  }

  Future<void> unregister() async {
    PushNativeRegistration? registration;
    try {
      registration = await _registration('currentRegistration');
      if (registration.configured && registration.installationId.isNotEmpty) {
        await _dio.delete<void>(
          '/push/devices',
          data: {'installation_id': registration.installationId},
          options: await _auth.requiredAuthOptions(),
        );
      }
    } catch (_) {
      // Logout must still clear the local Firebase token if the API is offline.
    } finally {
      try {
        await _channel.invokeMethod<void>('deleteToken');
      } catch (_) {
        // A missing/disabled native push provider must never block logout.
      }
    }
  }

  Future<void> _register(PushNativeRegistration registration) async {
    await _dio.post<void>(
      '/push/devices',
      data: {
        'platform': 'android',
        'token': registration.token,
        'installation_id': registration.installationId,
        'app_build': _appBuild,
      },
      options: await _auth.requiredAuthOptions(),
    );
  }

  Future<PushNativeRegistration> _registration(String method) async {
    final raw = await _channel.invokeMapMethod<String, dynamic>(method);
    return PushNativeRegistration.fromMap(raw ?? const <String, dynamic>{});
  }
}

class PushNativeRegistration {
  const PushNativeRegistration({
    required this.configured,
    required this.granted,
    required this.installationId,
    this.token,
  });

  final bool configured;
  final bool granted;
  final String installationId;
  final String? token;

  factory PushNativeRegistration.fromMap(Map<String, dynamic> json) {
    final token = json['token']?.toString().trim();
    return PushNativeRegistration(
      configured: json['configured'] == true,
      granted: json['granted'] == true,
      installationId: json['installation_id']?.toString().trim() ?? '',
      token: token == null || token.isEmpty ? null : token,
    );
  }
}

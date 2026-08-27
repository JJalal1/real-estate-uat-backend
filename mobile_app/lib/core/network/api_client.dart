import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ApiEnvironmentConfig {
  const ApiEnvironmentConfig._();

  static const environment = String.fromEnvironment(
    'APP_ENVIRONMENT',
    defaultValue: 'local',
  );

  static const configuredBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000/api',
  );

  static bool get isUat => environment.trim().toLowerCase() == 'uat';

  static String resolveBaseUrl({
    String? environmentOverride,
    String? baseUrlOverride,
  }) {
    final env = (environmentOverride ?? environment).trim().toLowerCase();
    final raw = (baseUrlOverride ?? configuredBaseUrl).trim();
    final uri = Uri.tryParse(raw);

    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw StateError('API_BASE_URL is not a valid absolute URL.');
    }

    if (env == 'uat') {
      final host = uri.host.toLowerCase();
      final isLoopback = host == '127.0.0.1' ||
          host == 'localhost' ||
          host == '10.0.2.2' ||
          host == '::1';
      if (uri.scheme.toLowerCase() != 'https' || isLoopback) {
        throw StateError(
          'UAT API_BASE_URL must be a non-loopback HTTPS URL.',
        );
      }
    }

    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  static Duration connectTimeoutFor([String? environmentOverride]) {
    final env = (environmentOverride ?? environment).trim().toLowerCase();
    // Free-tier UAT hosts may cold-start after inactivity.
    return env == 'uat'
        ? const Duration(seconds: 75)
        : const Duration(seconds: 15);
  }

  static Duration receiveTimeoutFor([String? environmentOverride]) {
    final env = (environmentOverride ?? environment).trim().toLowerCase();
    return env == 'uat'
        ? const Duration(seconds: 45)
        : const Duration(seconds: 15);
  }
}

final dioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      baseUrl: ApiEnvironmentConfig.resolveBaseUrl(),
      connectTimeout: ApiEnvironmentConfig.connectTimeoutFor(),
      receiveTimeout: ApiEnvironmentConfig.receiveTimeoutFor(),
      headers: {'Accept': 'application/json'},
    ),
  );
});

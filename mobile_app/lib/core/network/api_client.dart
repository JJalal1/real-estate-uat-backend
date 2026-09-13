import 'dart:developer' as developer;

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
  final dio = Dio(
    BaseOptions(
      baseUrl: ApiEnvironmentConfig.resolveBaseUrl(),
      connectTimeout: ApiEnvironmentConfig.connectTimeoutFor(),
      receiveTimeout: ApiEnvironmentConfig.receiveTimeoutFor(),
      headers: {'Accept': 'application/json'},
    ),
  );
  dio.interceptors.add(_NearbyRequestCacheInterceptor());
  dio.interceptors.add(_RequestTimingInterceptor());
  return dio;
});

class _NearbyRequestCacheInterceptor extends Interceptor {
  static const _ttl = Duration(seconds: 8);
  final Map<String, _CachedNearbyResponse> _cache = {};

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!options.path.endsWith('/properties/nearby')) {
      handler.next(options);
      return;
    }

    final params = Map<String, dynamic>.from(options.queryParameters);
    for (final key in const ['latitude', 'longitude']) {
      final value = _asDouble(params[key]);
      if (value != null) {
        params[key] = (value * 1000).round() / 1000;
      }
    }
    options.queryParameters = params;

    final key = options.uri.toString();
    final cached = _cache[key];
    final now = DateTime.now();
    if (cached != null && now.difference(cached.createdAt) <= _ttl) {
      handler.resolve(
        Response<dynamic>(
          requestOptions: options,
          data: cached.data,
          statusCode: cached.statusCode,
          statusMessage: 'OK (nearby cache)',
        ),
      );
      return;
    }
    if (cached != null) _cache.remove(key);
    options.extra['_nearby_cache_key'] = key;
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final key = response.requestOptions.extra['_nearby_cache_key'];
    final status = response.statusCode ?? 0;
    if (key is String && status >= 200 && status < 300) {
      _cache[key] = _CachedNearbyResponse(
        data: response.data,
        statusCode: status,
        createdAt: DateTime.now(),
      );
      if (_cache.length > 32) {
        final oldest = _cache.entries.reduce(
          (a, b) => a.value.createdAt.isBefore(b.value.createdAt) ? a : b,
        );
        _cache.remove(oldest.key);
      }
    }
    handler.next(response);
  }

  double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}

class _RequestTimingInterceptor extends Interceptor {
  static const _startedAtKey = '_request_started_at_us';
  static const _slowRequestMs = 1500;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startedAtKey] = DateTime.now().microsecondsSinceEpoch;
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _report(
      response.requestOptions,
      statusCode: response.statusCode,
      requestId: response.headers.value('x-request-id'),
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _report(
      err.requestOptions,
      statusCode: err.response?.statusCode,
      requestId: err.response?.headers.value('x-request-id'),
      failed: true,
    );
    handler.next(err);
  }

  void _report(
    RequestOptions options, {
    int? statusCode,
    String? requestId,
    bool failed = false,
  }) {
    if (!ApiEnvironmentConfig.isUat) return;
    final startedAt = options.extra[_startedAtKey];
    if (startedAt is! int) return;
    final durationMs =
        ((DateTime.now().microsecondsSinceEpoch - startedAt) / 1000).round();
    if (!failed && durationMs < _slowRequestMs && (statusCode ?? 0) < 500) {
      return;
    }
    developer.log(
      'api_request method=${options.method} path=${options.path} '
      'status=${statusCode ?? 0} duration_ms=$durationMs '
      'request_id=${requestId ?? '-'}',
      name: 'real_estate.network',
      level: failed || (statusCode ?? 0) >= 500 ? 1000 : 900,
    );
  }
}

class _CachedNearbyResponse {
  const _CachedNearbyResponse({
    required this.data,
    required this.statusCode,
    required this.createdAt,
  });

  final dynamic data;
  final int statusCode;
  final DateTime createdAt;
}

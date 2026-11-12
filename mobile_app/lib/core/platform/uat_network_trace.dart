import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

/// Opt-in measurements on the disposable UAT device. Never emits request URLs,
/// search text, headers, tokens, response bodies or account identifiers.
abstract final class UatNetworkTrace {
  static const requested = bool.fromEnvironment('AQER_NATIVE_NETWORK_TRACE');
  static bool get enabled => requested &&
      const String.fromEnvironment('APP_ENVIRONMENT').trim().toLowerCase() == 'uat';
  static const _channel = MethodChannel('real_estate/network');
  static const variants = {'thumb', 'card', 'preview', 'detail', 'gallery', 'zoom'};
  static int _nextImageSequence = 0;

  static void emit(Map<String, Object> measurement) {
    if (!enabled) return;
    unawaited(_channel.invokeMethod<void>('uatNetworkTrace', measurement)
        .catchError((Object _) {}));
  }

  static Uri? _imageUri(Uri origin, String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.userInfo.isNotEmpty || uri.hasFragment ||
        uri.scheme != origin.scheme || uri.host != origin.host || uri.port != origin.port ||
        !RegExp(r'^/api/property-media/[1-9][0-9]*$').hasMatch(uri.path) ||
        uri.queryParametersAll.values.any((values) => values.length != 1) ||
        uri.queryParameters.keys.any((key) => key != 'variant' && key != 'v') ||
        !variants.contains(uri.queryParameters['variant'])) {
      return null;
    }
    final identity = int.tryParse(uri.pathSegments.last);
    if (identity == null || identity > 1000000000) return null;
    return uri;
  }

  static int? startImage(Uri origin, String url) {
    if (!enabled) return null;
    final uri = _imageUri(origin, url);
    if (uri == null) return null;
    final seq = ++_nextImageSequence;
    // Do not expose an image identifier before a public response is verified.
    emit({'resource':2,'phase':1,'seq':seq,'media':0,'variant':uri.queryParameters['variant']!,
      'bytes':0,'elapsedMs':0,'status':0});
    return seq;
  }

  static Map<String, Object>? publicImageMeasurement({
    required Uri origin, required String url, required bool publicResponse,
    required int bytes, required int elapsedMs, required int status,
  }) {
    final uri = _imageUri(origin, url);
    if (!publicResponse || uri == null ||
        bytes < 0 || bytes > 8 * 1024 * 1024 || elapsedMs < 0 || elapsedMs > 120000 ||
        (status != 200 && status != 304)) {
      return null;
    }
    return {'resource': 2, 'phase': 2, 'media': int.parse(uri.pathSegments.last),
      'variant': uri.queryParameters['variant']!, 'bytes': bytes,
      'elapsedMs': elapsedMs, 'status': status};
  }
}

/// Measures only actual public collection requests. Opaque scope/sequence
/// numbers distinguish overlapping requests without exposing their criteria.
class PublicNetworkTraceInterceptor extends Interceptor {
  PublicNetworkTraceInterceptor(this.origin) : scope = ++_nextScope;
  final Uri origin;
  final int scope;
  static int _nextScope = 0;
  int _nextSequence = 0;
  static const _key = '_uat_public_trace';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final uri = options.uri;
    if (UatNetworkTrace.enabled && options.method == 'GET' &&
        uri.scheme == origin.scheme && uri.host == origin.host && uri.port == origin.port &&
        const {'/api/properties', '/api/properties/nearby', '/api/properties/suggestions'}.contains(uri.path)) {
      final rawPage = options.queryParameters['page'];
      final page = int.tryParse('$rawPage') ?? 1;
      final measurement = <String, Object>{'resource': 1, 'scope': scope,
        'seq': ++_nextSequence, 'phase': 1, 'page': page.clamp(1, 10000).toInt(),
        'elapsedMs': 0, 'status': 0};
      options.extra[_key] = (Stopwatch()..start(), measurement);
      UatNetworkTrace.emit(measurement);
    }
    handler.next(options);
  }

  void _complete(RequestOptions options, int status, {bool cancelled = false}) {
    final trace = options.extra.remove(_key);
    if (trace is! (Stopwatch, Map<String, Object>)) return;
    UatNetworkTrace.emit({...trace.$2, 'phase': cancelled ? 3 : 2,
      'status': status, 'elapsedMs': trace.$1.elapsedMilliseconds});
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _complete(response.requestOptions, response.statusCode ?? 0);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _complete(err.requestOptions, err.response?.statusCode ?? 0,
      cancelled: err.type == DioExceptionType.cancel);
    handler.next(err);
  }
}

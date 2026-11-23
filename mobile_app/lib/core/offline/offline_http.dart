import 'dart:convert';
import 'package:dio/dio.dart';
import '../local/stage6_secure_session_store.dart';
import '../platform/uat_network_trace.dart';
import 'offline_connection.dart';
import 'offline_store.dart';

String offlineRequestIdentity(RequestOptions r) {
  final query = Map<String, dynamic>.from(r.queryParameters);
  if (r.uri.path.endsWith('/properties/nearby')) {
    for (final key in const ['latitude', 'longitude']) {
      final value = double.tryParse(query[key]?.toString() ?? '');
      if (value != null) query[key] = (value * 1000).round() / 1000;
    }
  }
  final keys = query.keys.toList()..sort();
  return '${r.uri.origin}${r.uri.path}|${jsonEncode({
        for (final key in keys) key: query[key]
      })}|${r.headers['Authorization'] ?? r.headers['authorization'] ?? ''}';
}

class OfflineHttpInterceptor extends Interceptor {
  OfflineHttpInterceptor(this.store, this.connection);
  final OfflineStore store;
  final OfflineConnectionController connection;
  bool eligible(RequestOptions r) {
    if (r.method != 'GET' ||
        r.responseType == ResponseType.bytes ||
        r.uri.origin != Uri.parse(r.baseUrl).origin) {
      return false;
    }
    final path = r.uri.path.replaceFirst(Uri.parse(r.baseUrl).path, '');
    return const [
          '/marketplace',
          '/marketplace/locations',
          '/properties',
          '/properties/nearby',
          '/properties/mine/list',
          '/auth/me',
          '/messages/threads',
          '/listing-access',
          '/listing-editor-drafts'
        ].contains(path) ||
        RegExp(r'^/(properties|messages/threads)/[1-9][0-9]*$')
            .hasMatch(path) ||
        RegExp(r'^/listing-editor-drafts/[a-fA-F0-9-]{36}$').hasMatch(path);
  }

  bool _preferSnapshot(RequestOptions request) =>
      connection.current == OfflineConnection.offline ||
      connection.current == OfflineConnection.unknown ||
      (connection.current == OfflineConnection.unavailable && !private(request) &&
          const {'/marketplace', '/properties', '/properties/nearby'}.contains(
              request.uri.path.replaceFirst(Uri.parse(request.baseUrl).path, '')));

  String identity(RequestOptions r) => offlineRequestIdentity(r);
  bool private(RequestOptions r) =>
      r.headers.keys.any((k) => k.toLowerCase() == 'authorization');
  String space(RequestOptions r) => 'http_snapshots';
  bool _current(RequestOptions r) =>
      r.extra['offline_epoch'] ==
          Stage6SecureSessionStore.instance.sessionEpoch &&
      r.cancelToken?.isCancelled != true;
  Map<String, dynamic> _semantics(RequestOptions r) {
    final values = Map<String, dynamic>.from(r.queryParameters)
      ..removeWhere((key, _) => const [
            'latitude',
            'longitude',
            'accuracy_m',
            'governorate',
            'governorate_code'
          ].contains(key));
    final keys = values.keys.toList()..sort();
    return {for (final key in keys) key: values[key]};
  }

  Future<Map<String, dynamic>?> _cached(RequestOptions r) async {
    final exact = await store.read(space(r), identity(r), private: true);
    if (exact != null || !r.uri.path.endsWith('/marketplace')) return exact;
    final latest =
        await store.read(space(r), 'latest_marketplace', private: true);
    if (latest == null ||
        jsonEncode(latest['semantics']) != jsonEncode(_semantics(r))) {
      return null;
    }
    final savedLocation = latest['request_location'] as Map? ?? const {};
    for (final key in const ['latitude', 'longitude']) {
      if (r.queryParameters.containsKey(key) &&
          r.queryParameters[key] != savedLocation[key]) {
        return null;
      }
    }
    final context =
        ((latest['body'] as Map?)?['data'] as Map?)?['context'] as Map?;
    final code = r.queryParameters['governorate_code'],
        name = r.queryParameters['governorate'];
    if (code != null && context?['governorate_code'] != code) return null;
    if (code == null && name != null && context?['governorate'] != name) {
      return null;
    }
    return latest;
  }

  Response<dynamic> _response(RequestOptions r, Map<String, dynamic> cache) {
    connection.usedSnapshot = true;
    return Response<dynamic>(
        requestOptions: r,
        data: cache['body'],
        statusCode: 200,
        headers: Headers.fromMap((cache['headers'] as Map? ?? const {}).map(
            (k, v) => MapEntry(
                k.toString(), (v as List).map((x) => x.toString()).toList()))),
        extra: {'offline_snapshot': true, 'snapshot_at': cache['at']});
  }

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    options.extra['offline_epoch'] =
        Stage6SecureSessionStore.instance.sessionEpoch;
    options.extra['offline_connection_revision'] = connection.revision;
    if (eligible(options) &&
        _preferSnapshot(options) &&
        options.extra['offline_bypass'] != true) {
      final row = await _cached(options);
      if (_current(options) &&
          row != null &&
          _preferSnapshot(options)) {
        handler.resolve(_response(options, row));
        return;
      }
    }
    if (connection.current == OfflineConnection.offline &&
        options.extra['offline_bypass'] != true) {
      options.extra['offline_rejected'] = true;
      handler.reject(DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          message: 'لا يوجد اتصال. البيانات غير المحفوظة تحتاج إلى الإنترنت.'));
      return;
    }
    UatMapRequestTiming.of(options.cancelToken)?.mark(UatMapPhase.httpStarted);
    handler.next(options);
  }

  @override
  void onResponse(
      Response<dynamic> response, ResponseInterceptorHandler handler) async {
    final r = response.requestOptions;
    UatMapRequestTiming.of(r.cancelToken)?.mark(UatMapPhase.httpDecoded,
      status: response.statusCode ?? 0);
    if (_current(r) &&
        response.extra['offline_snapshot'] != true &&
        response.extra['http_memory_cache'] != true &&
        r.uri.origin == Uri.parse(r.baseUrl).origin) {
      connection.reachable(r.extra['offline_connection_revision'] as int? ??
          connection.revision);
    }
    if (response.extra['offline_snapshot'] != true &&
        response.extra['http_memory_cache'] != true &&
        response.statusCode == 200 &&
        eligible(r) &&
        response.data is Map &&
        _current(r)) {
      final headers = <String, List<String>>{
        for (final e in response.headers.map.entries)
          if (e.key.toLowerCase().startsWith('x-aqer-')) e.key: e.value
      };
      // Capture plain JSON now; a repository cannot mutate the saved snapshot.
      final body = jsonDecode(jsonEncode(response.data));
      final record = {
        'body': body,
        'headers': headers,
        'at': DateTime.now().toIso8601String(),
        'semantics': _semantics(r),
        'request_location': {
          for (final key in const ['latitude', 'longitude'])
            if (r.queryParameters.containsKey(key)) key: r.queryParameters[key]
        }
      };
      // Complete the atomic checkpoint before exposing the response to the UI.
      // Cache/storage failure still cannot turn a successful API read into an error.
      try {
        await store.write(space(r), identity(r), record,
            private: true, current: () => _current(r));
        if (r.uri.path.endsWith('/marketplace') && !private(r)) {
          await store.write(space(r), 'latest_marketplace', record,
              private: true, current: () => _current(r));
        }
      } catch (_) {}
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final r = err.requestOptions;
    if (err.response != null) {
      UatMapRequestTiming.of(r.cancelToken)?.mark(UatMapPhase.httpDecoded, status: err.response!.statusCode ?? 0);
    }
    if (_current(r) &&
        r.extra['offline_rejected'] != true &&
        r.uri.origin == Uri.parse(r.baseUrl).origin) {
      final started =
          r.extra['offline_connection_revision'] as int? ?? connection.revision;
      if (err.response != null && r.uri.origin == Uri.parse(r.baseUrl).origin) {
        connection.reachable(started);
      } else if (offlineTransportFailure(err)) {
        connection.transportFailure(started);
      }
    }
    if (eligible(r) && _current(r)) {
      if (const [401, 403, 404, 410].contains(err.response?.statusCode)) {
        try {
          await store.forget(space(r), identity(r));
          if (r.uri.path.endsWith('/auth/me') &&
              const [401, 403].contains(err.response?.statusCode)) {
            await store.clear('http_snapshots');
          }
        } catch (_) {
          /* Disk failure cannot hide an authoritative API failure. */
        }
      } else if (offlineTransportFailure(err)) {
        final row = await _cached(r);
        if (_current(r) && row != null) {
          handler.resolve(_response(r, row));
          return;
        }
      }
    }
    handler.next(err);
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/platform/uat_network_trace.dart';

class _Adapter implements HttpClientAdapter {
  final entered = Completer<void>();
  final release = Completer<void>();
  bool delay = false;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? stream,
      Future<void>? cancelFuture) async {
    if (delay) {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    }
    return ResponseBody.fromString('{"data":[]}', 200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }
  @override
  void close({bool force = false}) {
    if (!release.isCompleted) release.complete();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final origin = Uri.parse('https://uat.example/api');

  test('compiled trace requires both explicit opt-in and UAT', () {
    final uat = const String.fromEnvironment('APP_ENVIRONMENT').trim().toLowerCase() == 'uat';
    expect(UatNetworkTrace.enabled,
      uat && const bool.fromEnvironment('AQER_NATIVE_NETWORK_TRACE'));
    if (!uat) expect(UatNetworkTrace.enabled, isFalse);
  });

  test('public image trace refuses credentials, private media and foreign origins', () {
    Map<String, Object>? measurement(String url, {bool public = true}) =>
      UatNetworkTrace.publicImageMeasurement(origin: origin, url: url,
        publicResponse: public, bytes: 17000, elapsedMs: 125, status: 200);
    const safe = 'https://uat.example/api/property-media/176?variant=card&v=reviewed';
    expect(measurement(safe), {'resource': 2, 'phase': 2, 'media': 176,
      'variant': 'card', 'bytes': 17000, 'elapsedMs': 125, 'status': 200});
    expect(measurement(safe, public: false), isNull);
    for (final url in [
      'https://uat.example/api/property-media/176?variant=card&token=PRIVATE',
      'https://uat.example/api/property-media/176?variant=card&variant=zoom',
      'https://other.example/api/property-media/176?variant=card',
      'https://PRIVATE@uat.example/api/property-media/176?variant=card',
      'https://uat.example/api/property-media/176?variant=card#PRIVATE',
      'https://uat.example/api/listing-editor-drafts/PRIVATE/images/1?variant=card',
    ]) {
      expect(measurement(url), isNull, reason: url);
    }
  });

  test('actual request tracing omits search text and authorization and excludes private APIs', () async {
    final events = <Map<String, dynamic>>[];
    const channel = MethodChannel('real_estate/network');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'uatNetworkTrace');
      events.add(Map<String, dynamic>.from(call.arguments as Map));
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final adapter = _Adapter();
    final dio = Dio(BaseOptions(baseUrl: origin.toString()))..httpClientAdapter = adapter;
    dio.interceptors.add(PublicNetworkTraceInterceptor(origin));
    addTearDown(() => dio.close(force: true));
    for (final path in ['/properties', '/auth/me', '/listing-editor-drafts/PRIVATE', '/messages/threads/37']) {
      await dio.get<Object>(path, queryParameters: {'search': 'PRIVATE_TEXT', 'page': 2},
        options: Options(headers: {'Authorization': 'Bearer PRIVATE_TOKEN'}));
    }
    await Future<void>.delayed(Duration.zero);
    expect(events.length, UatNetworkTrace.enabled ? 2 : 0);
    if (events.isNotEmpty) {
      expect(events.map((e) => e['phase']), [1, 2]);
      expect(events.last['page'], 2);
      expect(events.last['status'], 200);
      expect(jsonEncode(events), isNot(contains('PRIVATE')));
      expect(events.last.keys.toSet(), {'resource','scope','seq','phase','page','elapsedMs','status'});
    }
  });

  test('cancelled in-flight request has its own terminal trace', () async {
    final events = <Map<String, dynamic>>[];
    const channel = MethodChannel('real_estate/network');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      events.add(Map<String, dynamic>.from(call.arguments as Map));
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final adapter = _Adapter()..delay = true;
    final dio = Dio(BaseOptions(baseUrl: origin.toString()))..httpClientAdapter = adapter;
    dio.interceptors.add(PublicNetworkTraceInterceptor(origin));
    addTearDown(() => dio.close(force: true));
    final cancel = CancelToken();
    final request = dio.get<Object>('/properties', cancelToken: cancel);
    final rejected = expectLater(request, throwsA(isA<DioException>()));
    await adapter.entered.future.timeout(const Duration(seconds: 5));
    cancel.cancel('replacement request');
    await rejected;
    await Future<void>.delayed(Duration.zero);
    expect(events.length, UatNetworkTrace.enabled ? 2 : 0);
    if (events.isNotEmpty) {
      expect(events.map((e) => e['phase']), [1, 3]);
      expect(events.first['seq'], events.last['seq']);
    }
  });
}

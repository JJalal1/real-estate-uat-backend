import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/phase23_private_pages_main.dart';

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  Map<String, dynamic> body = {'data': <dynamic>[], 'meta': {'current_page': 1, 'last_page': 1, 'total': 0}};
  bool fail = false;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<dynamic>? cancelFuture) async {
    requests.add(options);
    if (fail) throw DioException(requestOptions: options, type: DioExceptionType.connectionError);
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }
  @override
  void close({bool force = false}) {}
}

void main() {
  late PrivatePagesGate gate;
  late Dio dio;
  late _Adapter adapter;
  final logs = <String>[];
  DebugPrintCallback? previous;
  setUp(() {
    previous = debugPrint;
    debugPrint = (String? text, {int? wrapWidth}) { if (text != null) logs.add(text); };
    logs.clear();
    gate = PrivatePagesGate()..actor = (() => 2)..epoch = (() => 1);
    adapter = _Adapter();
    dio = Dio(BaseOptions(baseUrl: privatePagesApi))..httpClientAdapter = adapter;
    dio.interceptors.add(PrivatePagesTransport(gate));
  });
  tearDown(() { dio.close(); debugPrint = previous!; });

  test('target is explicitly pinned to UAT and preserves fixed customer contract', () {
    expect(privatePagesAllowed(enabled: true, environment: 'uat', api: privatePagesApi), isTrue);
    for (final environment in ['production','local','UAT','']) {
      expect(privatePagesAllowed(enabled: true, environment: environment, api: privatePagesApi), isFalse);
    }
    expect(privatePagesAllowed(enabled: false, environment: 'uat', api: privatePagesApi), isFalse);
    expect(privatePagesAllowed(enabled: true, environment: 'uat', api: 'https://other.invalid/api'), isFalse);
    expect(privatePageSizes['/broker/customers']!.$2, 0);
  });
  test('business writes and AI stop before transport; ordinary pinned auth remains real', () async {
    for (final path in ['/account/erase','/listing-editor-drafts','/notifications/read-all','/properties']) {
      for (final method in ['POST','PATCH','PUT','DELETE']) {
        await expectLater(dio.request<dynamic>(path, options: Options(method: method)), throwsA(isA<DioException>()));
      }
    }
    await expectLater(dio.get<dynamic>('/ai/search'), throwsA(isA<DioException>()));
    await expectLater(dio.post<dynamic>('https://other.invalid/api/auth/logout'), throwsA(isA<DioException>()));
    expect(adapter.requests, isEmpty);
    for (final path in ['/auth/whatsapp/start','/auth/whatsapp/verify','/auth/logout']) {
      await dio.post<dynamic>(path);
    }
    expect(adapter.requests, hasLength(3));
    await expectLater(dio.delete<dynamic>('/push/devices'), throwsA(isA<DioException>()));
    expect(gate.pushCleanup, 1);
  });
  test('declared sizes keep page and filters; real response is returned unchanged and telemetry omits content', () async {
    adapter.body = {'data': [{'id': 91, 'private_note': 'PRIVATE_NOTE_SENTINEL'}],
      'meta': {'current_page': 2, 'last_page': 2, 'total': 2}};
    final result = await dio.get<Map<String, dynamic>>('/favorites', queryParameters: {'page': 2, 'per_page': 50, 'status': 'private-filter'});
    expect(adapter.requests.single.queryParameters, {'page': 2, 'per_page': 1, 'status': 'private-filter'});
    expect(result.data, adapter.body);
    expect(logs.last, contains('"original":50'));
    expect(logs.last, contains('"count":1'));
    expect(logs.join(), isNot(contains('PRIVATE_NOTE_SENTINEL')));
    expect(logs.join(), isNot(contains('private-filter')));
    final row = jsonDecode(logs.last.split('AQER_PRIVATE:').last) as Map<String, dynamic>;
    expect(row.values.every((value) => value is int), isTrue);
    expect(row.containsKey('id'), isFalse);
  });
  test('page overlap is measured without rewriting data and resets for the next account', () async {
    Future<void> page(int page, int id) async {
      adapter.body = {'data': [{'id': id}], 'meta': {'current_page': page, 'last_page': 2, 'total': 2}};
      await dio.get<dynamic>('/favorites', queryParameters: {'page': page, 'per_page': 50});
    }
    await page(1, 91); await page(2, 91);
    expect(logs.last, contains('"duplicate":1'));
    gate.actor = () => 3; gate.epoch = () => 2;
    await page(1, 91); await page(2, 92);
    expect(logs.last, contains('"duplicate":0'));
  });
  test('failed native request reports the exact requested page without substituting a success', () async {
    adapter.fail = true;
    await expectLater(dio.get<dynamic>('/favorites', queryParameters: {'page': 2, 'per_page': 50}), throwsA(isA<DioException>()));
    expect(logs.last, contains('"phase":3'));
    expect(logs.last, contains('"page":2'));
  });
  test('unrelated and guest reads are neither resized nor traced', () async {
    await dio.get<dynamic>('/properties', queryParameters: {'per_page': 20});
    expect(adapter.requests.last.queryParameters['per_page'], 20);
    gate.actor = () => 0;
    await dio.get<dynamic>('/favorites', queryParameters: {'per_page': 50});
    expect(adapter.requests.last.queryParameters['per_page'], 50);
    expect(logs, isEmpty);
  });
}

import 'package:flutter/services.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/local/stage6_secure_session_store.dart';
import 'package:real_estate_mobile/core/offline/offline_connection.dart';
import 'package:real_estate_mobile/core/offline/offline_http.dart';
import 'package:real_estate_mobile/core/offline/offline_store.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_repository.dart';

// Opaque in-memory fake for the native cipher contract. Android Keystore itself
// is a separate native/device gate; this fake never claims cryptographic proof.
class _Cipher {
  final values = <String, String>{};
  Future<String> seal(String plain) async {
    final key = 'sealed:${values.length}';
    values[key] = plain;
    return key;
  }

  Future<String> open(String sealed) async => values[sealed]!;
}

class _Wire implements HttpClientAdapter {
  final calls = <RequestOptions>[];
  FutureOr<ResponseBody> Function(RequestOptions)? response;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls.add(options);
    return await (response?.call(options) ??
        ResponseBody.fromString(
            jsonEncode({
              'data': {'id': 7, 'title': 'عقار محفوظ'}
            }),
            200,
            headers: {
              'content-type': ['application/json']
            }));
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late _Cipher cipher;
  late OfflineConnectionController connection;
  late OfflineStore store;
  late _Wire wire;
  late Dio dio;
  OfflineStore storage({int entries = 240, DateTime Function()? clock}) =>
      OfflineStore(
          directory: () async => root,
          seal: cipher.seal,
          open: cipher.open,
          maxEntries: entries,
          clock: clock);
  Dio client(OfflineStore cache, OfflineConnectionController state,
          _Wire adapter) =>
      Dio(BaseOptions(baseUrl: 'https://fixture.invalid/api'))
        ..httpClientAdapter = adapter
        ..interceptors.add(OfflineHttpInterceptor(cache, state));
  setUp(() async {
    root = await Directory.systemTemp.createTemp('aqer-offline-');
    cipher = _Cipher();
    store = storage();
    connection = OfflineConnectionController()..online();
    wire = _Wire();
    dio = client(store, connection, wire);
  });
  tearDown(() async {
    dio.close(force: true);
    connection.dispose();
    await store.idle;
    await root.delete(recursive: true);
  });

  test('Home reads an exact snapshot while a live refresh replaces it', () async {
    const query = HomeFeedQuery(latitude: 14.54, longitude: 44.40,
        governorate: 'ذمار', governorateCode: 'DHAMAR', device: false);
    const other = HomeFeedQuery(latitude: 14.54, longitude: 44.40,
        governorate: 'إب', governorateCode: 'IBB', device: false);
    const filtered = HomeFeedQuery(latitude: 14.54, longitude: 44.40,
        governorate: 'ذمار', governorateCode: 'DHAMAR', purpose: 'rent', device: false);
    ResponseBody marketplace(int id) => ResponseBody.fromString(jsonEncode({
      'data': {
        'context': {'label': 'ذمار', 'governorate': 'ذمار', 'governorate_code': 'DHAMAR'},
        'sections': {'latest': [{'id': id, 'title': 'عقار $id', 'purpose': 'sale', 'type': 'apartment', 'price': 100000}]},
      },
    }), 200, headers: {'content-type': ['application/json']});
    wire.response = (_) => marketplace(1);
    await MarketplaceRepository(dio).feed(query);

    final restartedConnection = OfflineConnectionController();
    final restartedWire = _Wire();
    final restarted = client(storage(), restartedConnection, restartedWire);
    addTearDown(() {
      restarted.close(force: true);
      restartedConnection.dispose();
    });
    final repository = MarketplaceRepository(restarted);
    final pending = Completer<ResponseBody>();
    final requested = Completer<void>();
    restartedWire.response = (_) {
      requested.complete();
      return pending.future;
    };
    final refreshed = repository.feed(query);
    await requested.future.timeout(const Duration(seconds: 2));
    expect((await repository.initialSnapshot(query))?.sections['latest']?.single.id, 1);
    expect(await repository.initialSnapshot(other), isNull);
    expect(await repository.initialSnapshot(filtered), isNull);
    expect(restartedConnection.usedSnapshot, isFalse);

    pending.complete(marketplace(2));
    expect((await refreshed).sections['latest']?.single.id, 2);
    expect((await repository.initialSnapshot(query))?.sections['latest']?.single.id, 2);

    restartedConnection.offline();
    repository.invalidateFeed(query);
    expect((await repository.feed(query)).sections['latest']?.single.id, 2);
    expect(restartedWire.calls, hasLength(1));
  });

  test(
      'private GET survives process recreation; exact token, query and endpoint stay bound',
      () async {
    final auth = Options(headers: {'Authorization': 'Bearer actor-one'});
    for (final path in [
      '/auth/me',
      '/properties/7',
      '/messages/threads',
      '/messages/threads/9'
    ]) {
      await dio.get<dynamic>(path, options: auth);
    }
    final restartedWire = _Wire(),
        restartedConnection = OfflineConnectionController()..offline();
    final restarted = client(storage(), restartedConnection, restartedWire);
    for (final path in [
      '/auth/me',
      '/properties/7',
      '/messages/threads',
      '/messages/threads/9'
    ]) {
      final response = await restarted.get<dynamic>(path, options: auth);
      expect(response.extra['offline_snapshot'], true);
      expect(response.data['data']['id'], 7);
    }
    await expectLater(restarted.get<dynamic>('/properties/8', options: auth),
        throwsA(isA<DioException>()));
    await expectLater(
        restarted.get<dynamic>('/messages/threads/9',
            options: Options(headers: {'Authorization': 'Bearer actor-two'})),
        throwsA(isA<DioException>()));
    await expectLater(
        restarted.get<dynamic>('/messages/threads',
            queryParameters: {'unread_only': 1}, options: auth),
        throwsA(isA<DioException>()));
    expect(restartedWire.calls, isEmpty);
    final files = await root
        .list(recursive: true)
        .where((e) => e is File)
        .cast<File>()
        .toList();
    for (final file in files) {
      final payload = await file.readAsString();
      expect(payload, startsWith('sealed:'));
      expect(payload, isNot(contains('actor-one')));
      expect(payload, isNot(contains('عقار')));
    }
    restarted.close();
    restartedConnection.dispose();
  });

  test(
      'transport failure restores data; 404 and 503 are never disguised as empty results or offline success',
      () async {
    await dio.get<dynamic>('/properties/7');
    wire.response = (r) => throw DioException(
        requestOptions: r, type: DioExceptionType.connectionError);
    expect((await dio.get<dynamic>('/properties/7')).extra['offline_snapshot'],
        true);
    await connection.check(force: true);
    // No failing health probe or lost Android route confirmed an outage.
    expect(connection.current, OfflineConnection.online);
    wire.response = (_) =>
        ResponseBody.fromString('{"message":"unavailable"}', 503, headers: {
          'content-type': ['application/json']
        });
    await expectLater(
        dio.get<dynamic>('/properties/7'),
        throwsA(isA<DioException>()
            .having((e) => e.response?.statusCode, 'status', 503)));
    expect(connection.current, OfflineConnection.online);
    wire.response = (_) => ResponseBody.fromString('{}', 404, headers: {
          'content-type': ['application/json']
        });
    await expectLater(
        dio.get<dynamic>('/properties/7'), throwsA(isA<DioException>()));
    connection.offline();
    await expectLater(
        dio.get<dynamic>('/properties/7'), throwsA(isA<DioException>()));
  });

  test(
      'no mutation, financial or privileged response enters the offline snapshot allowlist',
      () async {
    final interceptor = OfflineHttpInterceptor(store, connection);
    for (final path in [
      '/properties/7/sai',
      '/admin/messages/reports',
      '/auth/otp',
      '/private-documents/3',
      '/financial-summary'
    ]) {
      expect(
          interceptor.eligible(
              RequestOptions(path: path, baseUrl: dio.options.baseUrl)),
          false);
    }
    expect(
        interceptor.eligible(RequestOptions(
            path: '/properties/7',
            baseUrl: dio.options.baseUrl,
            method: 'POST')),
        false);
    connection.offline();
    await expectLater(
        dio.post<dynamic>('/properties'), throwsA(isA<DioException>()));
    expect(wire.calls, isEmpty);
  });

  test(
      'query key order cannot break cache; a changed filter never receives another result set',
      () async {
    await dio.get<dynamic>('/properties',
        queryParameters: {'purpose': 'sale', 'page': 2, 'min_bedrooms': 3});
    connection.offline();
    final response = await dio.get<dynamic>('/properties',
        queryParameters: {'min_bedrooms': 3, 'page': 2, 'purpose': 'sale'});
    expect(response.extra['offline_snapshot'], true);
    await expectLater(
        dio.get<dynamic>('/properties',
            queryParameters: {'purpose': 'rent', 'page': 2, 'min_bedrooms': 3}),
        throwsA(isA<DioException>()));
  });

  test('new session fences late network delivery from persisted snapshots',
      () async {
    final started = Completer<void>(), reply = Completer<ResponseBody>();
    wire.response = (_) {
      started.complete();
      return reply.future;
    };
    final request = dio.get<dynamic>('/properties/7');
    await started.future;
    Stage6SecureSessionStore.instance.beginSessionChange();
    reply
        .complete(ResponseBody.fromString('{"data":{"id":999}}', 200, headers: {
      'content-type': ['application/json']
    }));
    await request;
    connection.offline();
    await expectLater(
        dio.get<dynamic>('/properties/7'), throwsA(isA<DioException>()));
  });

  test(
      'retention and strict bounded snapshots; outbox never expires without delivery',
      () async {
    var now = DateTime.utc(2026, 11, 17);
    final bounded = storage(entries: 2, clock: () => now);
    for (var i = 0; i < 3; i++) {
      await bounded.write('test_cache', '$i', {'id': i}, private: true);
      now = now.add(const Duration(seconds: 1));
    }
    expect(await bounded.read('test_cache', '0', private: true), isNull);
    expect(await bounded.read('test_cache', '2', private: true), isNotNull);
    await bounded.write(
        'outbox',
        'actor:7',
        {
          'messages': ['retained']
        },
        private: true);
    now = now.add(const Duration(days: 31));
    expect(await bounded.read('test_cache', '2', private: true), isNull);
    expect(await bounded.read('outbox', 'actor:7', private: true), isNotNull);
  });

  test(
      'last feed restores a default reopen but never an uncached governorate or GPS area',
      () async {
    wire.response = (_) => ResponseBody.fromString(
            jsonEncode({
              'data': {
                'context': {'governorate': 'ذمار', 'governorate_code': 'YE-DH'}
              }
            }),
            200,
            headers: {
              'content-type': ['application/json']
            });
    await dio.get<dynamic>('/marketplace',
        queryParameters: {'latitude': 14.54, 'longitude': 44.40});
    connection.offline();
    expect(
        (await dio.get<dynamic>('/marketplace')).data['data']['context']
            ['governorate'],
        'ذمار');
    await expectLater(
        dio.get<dynamic>('/marketplace',
            queryParameters: {'governorate_code': 'YE-IB'}),
        throwsA(isA<DioException>()));
    await expectLater(
        dio.get<dynamic>('/marketplace',
            queryParameters: {'latitude': 13.96, 'longitude': 44.18}),
        throwsA(isA<DioException>()));
  });
  test('authoritative auth revocation removes private HTTP snapshots',
      () async {
    final auth = Options(headers: {'Authorization': 'Bearer actor-one'});
    await dio.get<dynamic>('/auth/me', options: auth);
    await dio.get<dynamic>('/messages/threads/9', options: auth);
    wire.response = (_) => ResponseBody.fromString('{}', 401, headers: {
          'content-type': ['application/json']
        });
    await expectLater(dio.get<dynamic>('/auth/me', options: auth),
        throwsA(isA<DioException>()));
    connection.offline();
    await expectLater(dio.get<dynamic>('/messages/threads/9', options: auth),
        throwsA(isA<DioException>()));
  });

  test(
      'first successful login and profile update restore offline before any auth-me GET',
      () async {
    const channel = MethodChannel('real_estate/secure_store');
    String? token;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'writeToken') {
        token = (call.arguments as Map)['token'] as String;
      }
      if (call.method == 'deleteToken') {
        token = null;
      }
      return call.method == 'readToken' ? token : null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    wire.response = (request) => ResponseBody.fromString(
            jsonEncode({
              'data': request.path == '/auth/email/login'
                  ? {
                      'token': 'synthetic-new-login',
                      'user': {
                        'id': 7,
                        'name': 'First login',
                        'account_status': 'active'
                      }
                    }
                  : {
                      'id': 7,
                      'name': 'Updated profile',
                      'account_status': 'active'
                    }
            }),
            200,
            headers: {
              'content-type': ['application/json']
            });
    final repository = AuthRepository(dio, offlineStore: store);
    await repository.verifyWhatsApp(
        const WhatsAppAuthPending(
            phone: '', email: 'synthetic@fixture.invalid', isNewAccount: false),
        '000000');
    expect(wire.calls.where((request) => request.path == '/auth/me'), isEmpty);
    connection.offline();
    expect((await repository.restoreSession())?.name, 'First login');
    connection.online();
    await repository.completeProfile('Updated profile');
    connection.offline();
    expect(
        (await AuthRepository(dio, offlineStore: storage()).restoreSession())
            ?.name,
        'Updated profile');
    expect(wire.calls.where((request) => request.path == '/auth/me'), isEmpty);
  });

  test(
      'native encryption failure has no plaintext fallback and queue remains usable',
      () async {
    final broken = OfflineStore(
        directory: () async => root,
        seal: (_) async => throw StateError('native unavailable'));
    await expectLater(
        broken.write('outbox', 'actor:7', {'body': 'secret'}, private: true),
        throwsStateError);
    expect(await root.list(recursive: true).where((f) => f is File).length, 0);
    await store.write('outbox', 'actor:7', {'messages': []}, private: true);
    final badReader = OfflineStore(
        directory: () async => root,
        open: (_) async => throw StateError('native unavailable'));
    await expectLater(
        badReader.read('outbox', 'actor:7', private: true, strict: true),
        throwsStateError);
    expect(await store.read('outbox', 'actor:7', private: true), isNotNull);
  });
}

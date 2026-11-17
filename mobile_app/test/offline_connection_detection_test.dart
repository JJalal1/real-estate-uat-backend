import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/offline/offline_connection.dart';
import 'package:real_estate_mobile/core/offline/offline_http.dart';
import 'package:real_estate_mobile/core/offline/offline_store.dart';

const _origin = 'https://synthetic.invalid/api';
const _activeUnvalidated = <String, dynamic>{
  'networkAvailable': true,
  'connected': false,
  'validated': false,
};

ResponseBody _json(Object value, [int status = 200]) =>
    ResponseBody.fromString(jsonEncode(value), status, headers: {
      'content-type': ['application/json']
    });

class _Wire implements HttpClientAdapter {
  final calls = <RequestOptions>[];
  final started = Completer<void>();
  FutureOr<ResponseBody> Function(RequestOptions)? reply;
  bool closed = false;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls.add(options);
    if (!started.isCompleted) started.complete();
    return await (reply?.call(options) ?? _json({'status': 'ok'}));
  }

  @override
  void close({bool force = false}) => closed = true;
}

// No filesystem/native cipher in these detection tests. Snapshot content and
// actual Android storage remain covered by their existing independent suites.
class _MemoryStore extends OfflineStore {
  final rows = <String, Map<String, dynamic>>{};
  int writes = 0;
  String _key(String space, String identity) => '$space|$identity';

  @override
  Future<Map<String, dynamic>?> read(String space, String identity,
          {bool private = false, bool strict = false}) async =>
      rows[_key(space, identity)];

  @override
  Future<void> write(String space, String identity, Map<String, dynamic> data,
      {bool private = false, bool Function()? current}) async {
    if (current?.call() != false) {
      writes++;
      rows[_key(space, identity)] = data;
    }
  }
}

class _DelayedCachedStore extends _MemoryStore {
  final started = Completer<void>();
  final cached = Completer<Map<String, dynamic>?>();

  @override
  Future<Map<String, dynamic>?> read(String space, String identity,
      {bool private = false, bool strict = false}) {
    if (!started.isCompleted) started.complete();
    return cached.future;
  }
}

Dio _client(_Wire wire) =>
    Dio(BaseOptions(baseUrl: _origin))..httpClientAdapter = wire;

OfflineConnectionController _controller(Dio probe,
    {Future<Map<String, dynamic>?> Function()? snapshot}) {
  final controller = OfflineConnectionController(
      probe: probe,
      networkSnapshot: snapshot ?? () async => _activeUnvalidated);
  controller.configure(_origin,
      connectTimeout: const Duration(seconds: 75),
      receiveTimeout: const Duration(seconds: 45));
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('unvalidated active WiFi can reach the real API and becomes online',
      () async {
    final wire = _Wire();
    final connection = _controller(_client(wire));
    await connection.check(force: true);
    expect(connection.current, OfflineConnection.online);
    expect(wire.calls, hasLength(1));
    expect(wire.calls.single.uri.path, '/api/health');
  });

  test('legacy validation-only false is advisory rather than no route',
      () async {
    final wire = _Wire();
    final connection =
        _controller(_client(wire), snapshot: () async => {'connected': false});
    await connection.check(force: true);
    expect(wire.calls, hasLength(1));
    expect(connection.current, OfflineConnection.online);
  });

  testWidgets('health can wait beyond the old four second false offline cutoff',
      (tester) async {
    final wire = _Wire(), response = Completer<ResponseBody>();
    wire.reply = (_) => response.future;
    final probe = _client(wire);
    final monitor = _controller(probe);
    final checking = monitor.check(force: true);
    var completed = false;
    unawaited(checking.then<void>((_) {
      completed = true;
    }));
    // Dio schedules request interception/dispatch through a zero-delay event.
    // Advance fake time in a bounded setup loop before measuring the delay.
    for (var frame = 0; frame < 50 && !wire.started.isCompleted; frame++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(wire.calls, hasLength(1));
    expect(probe.options.connectTimeout, const Duration(seconds: 75));
    expect(probe.options.receiveTimeout, const Duration(seconds: 45));
    await tester.pump(const Duration(seconds: 5));
    expect(monitor.current, OfflineConnection.unknown);
    response.complete(_json({'status': 'ok'}));
    for (var frame = 0; frame < 50 && !completed; frame++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(completed, true);
    await checking;
    expect(monitor.current, OfflineConnection.online);
  });

  test('503 is temporary service unavailability and an API receipt recovers it',
      () async {
    final wire = _Wire()..reply = (_) => _json({'message': 'starting'}, 503);
    final connection = _controller(_client(wire));
    await connection.check(force: true);
    expect(connection.current, OfflineConnection.unavailable);
    connection.reachable(connection.revision);
    expect(connection.current, OfflineConnection.online);
  });

  test('unexpected health content cannot claim there is no Internet', () async {
    final wire = _Wire()..reply = (_) => _json({'unexpected': true});
    final connection = _controller(_client(wire));
    await connection.check(force: true);
    expect(connection.current, OfflineConnection.unavailable);
  });

  test('a real API success fences a late failing health probe', () async {
    final wire = _Wire(), response = Completer<ResponseBody>();
    wire.reply = (_) => response.future;
    final connection = _controller(_client(wire));
    final checking = connection.check(force: true);
    await wire.started.future;
    connection.reachable(connection.revision);
    response.completeError(DioException(
        requestOptions: wire.calls.single,
        type: DioExceptionType.receiveTimeout));
    await checking;
    expect(connection.current, OfflineConnection.online);
  });

  test('late native snapshot cannot overwrite a newer successful API receipt',
      () async {
    final snapshot = Completer<Map<String, dynamic>?>();
    final wire = _Wire();
    final connection =
        _controller(_client(wire), snapshot: () => snapshot.future);
    final checking = connection.check(force: true);
    connection.reachable(connection.revision);
    snapshot.complete({'networkAvailable': false, 'connected': false});
    await checking;
    expect(connection.current, OfflineConnection.online);
  });

  test('confirmed loss of the active route is offline without a health request',
      () async {
    final wire = _Wire();
    final connection = _controller(_client(wire),
        snapshot: () async => {'networkAvailable': false, 'connected': false});
    await connection.check(force: true);
    expect(connection.current, OfflineConnection.offline);
    expect(wire.calls, isEmpty);
  });

  test('native snapshot failure still permits an API reachability check',
      () async {
    final wire = _Wire();
    final connection = _controller(_client(wire),
        snapshot: () async => throw StateError('Synthetic native unavailable'));
    await connection.check(force: true);
    expect(wire.calls, hasLength(1));
    expect(connection.current, OfflineConnection.online);
  });

  test(
      'an online controller still observes confirmed route loss on periodic checks',
      () async {
    final wire = _Wire();
    var available = true;
    final connection = _controller(_client(wire),
        snapshot: () async => {
              'networkAvailable': available,
              'connected': available,
            });
    connection.online();
    available = false;
    await connection.check();
    expect(connection.current, OfflineConnection.offline);
    expect(wire.calls, isEmpty);
    available = true;
    await connection.check();
    expect(connection.current, OfflineConnection.online);
    expect(wire.calls, hasLength(1));
  });

  test('a response started before a confirmed disconnect cannot revive online',
      () async {
    final connection = _controller(_client(_Wire()));
    final requestRevision = connection.revision;
    connection.offline();
    connection.reachable(requestRevision);
    expect(connection.current, OfflineConnection.offline);
  });

  test('old transport failure cannot downgrade a newer successful request',
      () async {
    final wire = _Wire();
    final connection = _controller(_client(wire));
    final requestRevision = connection.revision;
    connection.reachable(requestRevision);
    connection.transportFailure(requestRevision);
    await Future<void>.delayed(Duration.zero);
    expect(connection.current, OfflineConnection.online);
    expect(wire.calls, isEmpty);
  });

  test('concurrent forced checks share a single health request', () async {
    final wire = _Wire(), response = Completer<ResponseBody>();
    wire.reply = (_) => response.future;
    final connection = _controller(_client(wire));
    final first = connection.check(force: true);
    final second = connection.check(force: true);
    await wire.started.future;
    expect(wire.calls, hasLength(1));
    response.complete(_json({'status': 'ok'}));
    await Future.wait([first, second]);
    expect(connection.current, OfflineConnection.online);
  });

  test('disposal closes the probe and late completion is safe', () async {
    final wire = _Wire(), response = Completer<ResponseBody>();
    wire.reply = (_) => response.future;
    final connection = OfflineConnectionController(
        probe: _client(wire), networkSnapshot: () async => _activeUnvalidated);
    connection.configure(_origin);
    final checking = connection.check(force: true);
    await wire.started.future;
    connection.dispose();
    response.complete(_json({'status': 'ok'}));
    await expectLater(checking, completes);
    expect(wire.closed, true);
  });

  test(
      'uncached requests can escape service unavailable instead of self locking',
      () async {
    final health = _Wire()..reply = (_) => _json({'message': 'starting'}, 503);
    final connection = _controller(_client(health));
    await connection.check(force: true);
    expect(connection.current, OfflineConnection.unavailable);
    final live = _Wire()
      ..reply = (_) => _json({
            'data': {'id': 7}
          });
    final dio = _client(live)
      ..interceptors.add(OfflineHttpInterceptor(_MemoryStore(), connection));
    addTearDown(() => dio.close(force: true));
    final response = await dio.get<dynamic>('/properties/7');
    expect(live.calls, hasLength(1));
    expect(response.data['data']['id'], 7);
    expect(response.extra['offline_snapshot'], isNot(true));
    expect(connection.current, OfflineConnection.online);
  });

  test('cold uncached launch reaches wire despite unvalidated WiFi hint',
      () async {
    final health = _Wire(), healthReply = Completer<ResponseBody>();
    health.reply = (_) => healthReply.future;
    final connection = _controller(_client(health));
    final checking = connection.check(force: true);
    await health.started.future;
    final live = _Wire()
      ..reply = (_) => _json({
            'data': {'id': 8}
          });
    final dio = _client(live)
      ..interceptors.add(OfflineHttpInterceptor(_MemoryStore(), connection));
    addTearDown(() => dio.close(force: true));
    await dio.get<dynamic>('/properties/8');
    expect(live.calls, hasLength(1));
    expect(connection.current, OfflineConnection.online);
    healthReply.complete(_json({'status': 'ok'}));
    await checking;
    expect(connection.current, OfflineConnection.online);
  });

  test('a delayed startup cache cannot replace newer live connection evidence',
      () async {
    final connection = _controller(_client(_Wire()));
    final store = _DelayedCachedStore();
    final live = _Wire()
      ..reply = (_) => _json({
            'data': {'id': 7}
          });
    final dio = _client(live)
      ..interceptors.add(OfflineHttpInterceptor(store, connection));
    addTearDown(() => dio.close(force: true));
    final request = dio.get<dynamic>('/properties/7');
    await store.started.future;
    connection.reachable(connection.revision);
    store.cached.complete({
      'body': {
        'data': {'id': 999}
      },
      'headers': <String, dynamic>{},
      'at': '2026-11-17T00:00:00Z'
    });
    final response = await request;
    expect(live.calls, hasLength(1));
    expect(response.data['data']['id'], 7);
    expect(response.extra['offline_snapshot'], isNot(true));
    expect(connection.current, OfflineConnection.online);
    expect(connection.usedSnapshot, false);
  });

  test('HTTP memory cache cannot prove connectivity or renew durable snapshots',
      () async {
    final connection = _controller(_client(_Wire()));
    final store = _MemoryStore(), wire = _Wire();
    var followingResponseHandlers = 0;
    final dio = _client(wire)
      ..interceptors.addAll([
        OfflineHttpInterceptor(store, connection),
        InterceptorsWrapper(onRequest: (request, handler) {
          handler.resolve(
              Response<dynamic>(
                  requestOptions: request,
                  statusCode: 200,
                  data: {
                    'data': {'id': 7}
                  },
                  extra: {
                    'http_memory_cache': true
                  }),
              true);
        }, onResponse: (response, handler) {
          followingResponseHandlers++;
          handler.next(response);
        }),
      ]);
    addTearDown(() => dio.close(force: true));
    final response = await dio.get<dynamic>('/properties/nearby');
    expect(response.extra['http_memory_cache'], true);
    expect(followingResponseHandlers, 1);
    expect(wire.calls, isEmpty);
    expect(connection.current, OfflineConnection.unknown);
    expect(store.writes, 0);
    expect(store.rows, isEmpty);
  });
}

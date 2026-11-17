import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/offline/offline_store.dart';
import 'package:real_estate_mobile/features/messages/data/message_outbox.dart';

void main() {
  late Directory directory;
  late OfflineStore store;
  late bool online, current;
  late List<(int, String, String)> sent;
  late List<MessageOutbox> boxes;
  MessageOutbox box(
      {int actor = 7,
      Future<void> Function(int, String, String)? send,
      Future<int> Function(String, int)? resolve}) {
    final result = MessageOutbox(
        actor: actor,
        store: store,
        current: () => current,
        connected: () => online,
        resolveThread: resolve ?? (_, id) async => id + 100,
        sendMessage: send ??
            (thread, body, key) async {
              sent.add((thread, body, key));
            });
    boxes.add(result);
    return result;
  }

  DioException failure({int? status}) => DioException(
      requestOptions: RequestOptions(path: '/messages/threads/107/messages'),
      type: status == null
          ? DioExceptionType.connectionError
          : DioExceptionType.badResponse,
      response: status == null
          ? null
          : Response(
              requestOptions: RequestOptions(path: '/messages'),
              statusCode: status));
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('aqer-outbox-');
    // Deterministic opaque encoding is test transport only, not an AES claim.
    store = OfflineStore(
        directory: () async => directory,
        seal: (s) async => base64Encode(utf8.encode(s)),
        open: (s) async => utf8.decode(base64Decode(s)));
    online = false;
    current = true;
    sent = [];
    boxes = [];
  });
  tearDown(() async {
    for (final item in boxes) {
      item.dispose();
    }
    await store.idle;
    await directory.delete(recursive: true);
  });

  test(
      'offline enqueue persists before UI receipt; restart flushes in order and ACK alone marks sent',
      () async {
    final first = box();
    await first.enqueue('thread', 9, 'الأولى');
    await first.enqueue('thread', 9, 'الثانية');
    expect(sent, isEmpty);
    final keys = first.state.map((m) => m.id).toList();
    final restarted = box();
    await restarted.initialize();
    expect(restarted.state.map((m) => m.body), ['الأولى', 'الثانية']);
    online = true;
    await restarted.flush();
    expect(sent.map((m) => m.$2), ['الأولى', 'الثانية']);
    expect(sent.map((m) => m.$3), keys);
    expect(restarted.state.map((m) => m.status), everyElement('sent'));
    await restarted.flush();
    expect(sent.length, 2);
    await restarted.reconcile(9, keys.toSet());
    expect(restarted.state, isEmpty);
  });
  test(
      'lost HTTP acknowledgement reuses resolved thread and the same client ID',
      () async {
    final attempts = <String>[];
    var resolveCalls = 0, dropped = true;
    final first = box(resolve: (_, id) async {
      resolveCalls++;
      return 107;
    }, send: (thread, body, key) async {
      attempts.add(key);
      if (dropped) {
        dropped = false;
        throw failure();
      }
      sent.add((thread, body, key));
    });
    await first.enqueue('property', 7, 'عن هذا العقار');
    final id = first.state.single.id;
    online = true;
    await first.flush();
    expect(first.state.single.status, 'queued');
    expect(first.state.single.threadId, 107);
    online = false;
    final restarted = box(resolve: (_, id) async {
      resolveCalls++;
      return 999;
    }, send: (thread, body, key) async {
      attempts.add(key);
      sent.add((thread, body, key));
    });
    await restarted.initialize();
    online = true;
    await restarted.flush();
    expect(attempts, [id, id]);
    expect(resolveCalls, 1);
    expect(sent.single.$1, 107);
    expect(restarted.state.single.status, 'sent');
  });
  test(
      'account change during destination resolution cannot send under another session',
      () async {
    final resolve = Completer<int>();
    final first = box(resolve: (_, id) => resolve.future);
    await first.enqueue('property', 7, 'حسابي فقط');
    online = true;
    final transfer = first.flush();
    await Future<void>.delayed(Duration.zero);
    current = false;
    resolve.complete(107);
    await transfer;
    expect(sent, isEmpty);
    current = true;
    online = false;
    final differentActor = box(actor: 8);
    await differentActor.initialize();
    expect(differentActor.state, isEmpty);
    final sameActor = box();
    await sameActor.initialize();
    expect(sameActor.state.single.body, 'حسابي فقط');
    expect(sameActor.state.single.status, 'queued');
  });
  test(
      '403 is visibly failed and never auto-retried; cancel removes only pending work',
      () async {
    var calls = 0;
    final first = box(send: (_, body, key) async {
      calls++;
      throw failure(status: 403);
    });
    await first.enqueue('thread', 9, 'رسالة');
    online = true;
    await first.flush();
    await first.flush();
    expect(calls, 1);
    expect(first.state.single.status, 'failed');
    expect(first.state.single.error, isNotNull);
    await first.cancel(first.state.single.id);
    expect(first.state, isEmpty);
  });
  test('cancel offline and empty text cause no later delivery', () async {
    final first = box();
    await first.enqueue('thread', 9, 'تراجع');
    await first.cancel(first.state.single.id);
    await expectLater(first.enqueue('thread', 9, '  '), throwsArgumentError);
    online = true;
    await first.flush();
    expect(sent, isEmpty);
  });
  test('concurrent reconnect signals coalesce into one send', () async {
    final reply = Completer<void>();
    var calls = 0;
    final first = box(send: (_, body, key) async {
      calls++;
      await reply.future;
    });
    await first.enqueue('thread', 9, 'واحدة');
    online = true;
    final a = first.flush(), b = first.flush();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(calls, 1);
    reply.complete();
    await Future.wait([a, b]);
    expect(first.state.single.status, 'sent');
  });
}

import 'dart:async';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/offline/offline_connection.dart';
import '../../../core/offline/offline_store.dart';
import '../../account/data/account_request_scope.dart';
import '../../account/data/auth_controller.dart';
import '../../../core/local/stage6_secure_session_store.dart';
import 'message_repository.dart';

class PendingMessage {
  const PendingMessage(
      {required this.id,
      required this.target,
      required this.targetId,
      required this.body,
      required this.createdAt,
      this.status = 'queued',
      this.threadId,
      this.error});
  final String id, target, body, status;
  final int targetId;
  final int? threadId;
  final DateTime createdAt;
  final String? error;
  PendingMessage copy({String? status, int? threadId, String? error}) =>
      PendingMessage(
          id: id,
          target: target,
          targetId: targetId,
          body: body,
          createdAt: createdAt,
          status: status ?? this.status,
          threadId: threadId ?? this.threadId,
          error: error);
  Map<String, dynamic> toJson() => {
        'id': id,
        'target': target,
        'target_id': targetId,
        'body': body,
        'created_at': createdAt.toIso8601String(),
        'status': status == 'sending' ? 'queued' : status,
        'thread_id': threadId,
        'error': error
      };
  factory PendingMessage.fromJson(Map<String, dynamic> r) => PendingMessage(
      id: r['id'] as String,
      target: r['target'] as String,
      targetId: r['target_id'] as int,
      body: r['body'] as String,
      createdAt: DateTime.parse(r['created_at'] as String),
      status: const ['failed', 'sent'].contains(r['status'])
          ? r['status'] as String
          : 'queued',
      threadId: r['thread_id'] as int?,
      error: r['error'] as String?);
}

/// Enqueue is durable before UI acknowledgement. Retries always reuse the
/// server's existing client_message_id; HTTP acknowledgement loss cannot duplicate a message.
class MessageOutbox extends StateNotifier<List<PendingMessage>> {
  MessageOutbox(
      {required this.actor,
      required this.store,
      required this.current,
      required this.connected,
      required this.resolveThread,
      required this.sendMessage,
      this.onDelivered})
      : super(const []);
  final int actor;
  final OfflineStore store;
  final bool Function() current, connected;
  final Future<int> Function(String target, int id) resolveThread;
  final Future<void> Function(int thread, String body, String id) sendMessage;
  final void Function()? onDelivered;
  Future<void> _tail = Future.value();
  Future<void>? _initializing, _sending;
  bool _disposed = false;
  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    final saved = await store.read('outbox', 'actor:$actor', private: true, strict: true);
    if (_disposed || !current()) return;
    state = (saved?['messages'] as List? ?? const [])
        .whereType<Map>()
        .map((x) => PendingMessage.fromJson(Map<String, dynamic>.from(x)))
        .take(150)
        .toList();
  }

  Future<void> _edit(
      List<PendingMessage> Function(List<PendingMessage>) update) {
    final operation = _tail.then((_) async {
      if (_disposed || !current()) throw StateError('ACCOUNT_CHANGED');
      final next = update(List.of(state));
      final sent = next.where((row) => row.status == 'sent').toList();
      if (sent.length > 50) {
        final remove = sent.take(sent.length - 50).map((row) => row.id).toSet();
        next.removeWhere((row) => remove.contains(row.id));
      }
      await store.write('outbox', 'actor:$actor',
          {'messages': next.map((x) => x.toJson()).toList()},
          private: true, current: () => !_disposed && current());
      if (!_disposed && current()) state = next;
    });
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return operation;
  }

  Future<void> enqueue(String target, int id, String body) async {
    await initialize();
    final text = body.trim();
    if (!const ['thread', 'property', 'broker'].contains(target) ||
        id <= 0 ||
        text.isEmpty ||
        text.length > 2000) throw ArgumentError('Invalid pending message');
    if (state.where((row) => row.status != 'sent').length >= 100)
      throw StateError('لديك 100 رسالة معلقة. أعد الاتصال أو احذف بعضها.');
    final random = Random.secure();
    final key =
        'offline-${DateTime.now().microsecondsSinceEpoch}-${List.generate(12, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    final message = PendingMessage(
        id: key,
        target: target,
        targetId: id,
        body: text,
        createdAt: DateTime.now(),
        threadId: target == 'thread' ? id : null);
    await _edit((rows) {
      if (rows.where((row) => row.status != 'sent').length >= 100) throw StateError('لديك 100 رسالة معلقة.');
      return [...rows, message];
    });
    if (connected()) unawaited(flush().catchError((Object _) {}));
  }

  Future<void> reconcile(int thread, Set<String> deliveredIds) async {
    await initialize();
    if (!state
        .any((row) => row.threadId == thread && deliveredIds.contains(row.id)))
      return;
    await _edit((rows) => rows
        .where(
            (row) => row.threadId != thread || !deliveredIds.contains(row.id))
        .toList());
  }

  Future<void> cancel(String id) => _edit((rows) {
        if (rows.any((x) => x.id == id && x.status == 'sending'))
          throw StateError('الرسالة قيد الإرسال.');
        return rows.where((x) => x.id != id).toList();
      });
  Future<void> retry(String id) async {
    await _edit((rows) =>
        rows.map((x) => x.id == id ? x.copy(status: 'queued') : x).toList());
    if (connected()) await flush();
  }

  Future<void> flush() =>
      _sending ??= _flush().whenComplete(() => _sending = null);
  Future<void> _flush() async {
    await initialize();
    while (!_disposed && current() && connected()) {
      PendingMessage? next;
      for (final row in state) {
        if (row.status == 'queued') {
          next = row;
          break;
        }
      }
      if (next == null) return;
      final item = next;
      await _edit((rows) => rows
          .map((x) => x.id == item.id ? x.copy(status: 'sending') : x)
          .toList());
      try {
        final thread =
            item.threadId ?? await resolveThread(item.target, item.targetId);
        if (_disposed || !current() || !connected()) {
          if (!_disposed && current())
            await _edit((rows) => rows
                .map((x) => x.id == item.id
                    ? x.copy(status: 'queued', threadId: thread)
                    : x)
                .toList());
          return;
        }
        // Persist the resolved destination before sending the original client ID.
        await _edit((rows) => rows
            .map((x) => x.id == item.id
                ? x.copy(status: 'sending', threadId: thread)
                : x)
            .toList());
        await sendMessage(thread, item.body, item.id);
        if (_disposed || !current()) return;
        await _edit((rows) => rows
            .map((x) =>
                x.id == item.id ? x.copy(status: 'sent', threadId: thread) : x)
            .toList());
        onDelivered?.call();
      } catch (error) {
        if (_disposed || !current()) return;
        final status =
            error is DioException ? error.response?.statusCode : null;
        final retryable = offlineTransportFailure(error) ||
            status == 429 ||
            (status != null && status >= 500);
        await _edit((rows) => rows
            .map((x) => x.id == item.id
                ? x.copy(
                    status: retryable ? 'queued' : 'failed',
                    error: retryable
                        ? null
                        : 'لم تُرسل. تحقق من صلاحية المحادثة ثم أعد المحاولة.')
                : x)
            .toList());
        if (retryable) return;
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final messageOutboxProvider = StateNotifierProvider.autoDispose
    .family<MessageOutbox, List<PendingMessage>, int>((ref, actor) {
  final scope = ref.watch(accountRequestScopeProvider);
  final repository = ref.watch(messageRepositoryProvider);
  final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
  bool current() =>
      scope.isCurrent &&
      Stage6SecureSessionStore.instance.sessionEpoch == epoch &&
      ref.read(authControllerProvider).asData?.value?.id == actor;
  final box = MessageOutbox(
      actor: actor,
      store: ref.watch(offlineStoreProvider),
      current: current,
      connected: () =>
          ref.read(offlineConnectionProvider) == OfflineConnection.online,
      resolveThread: (target, id) async => target == 'property'
          ? (await repository.startForProperty(id)).id
          : (await repository.startForBroker(id)).id,
      sendMessage: (thread, body, id) async {
        await repository.send(thread, body, clientMessageId: id);
      },
      onDelivered: () =>
          ref.read(messageDataRevisionProvider.notifier).state++);
  unawaited(box.initialize().then((_) {
    if (ref.read(offlineConnectionProvider) == OfflineConnection.online &&
        scope.isCurrent) unawaited(box.flush().catchError((Object _) {}));
  }).catchError((Object _) {}));
  return box;
});

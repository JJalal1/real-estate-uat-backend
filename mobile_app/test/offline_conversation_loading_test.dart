import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/offline/offline_store.dart';
import 'package:real_estate_mobile/core/widgets/app_components.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/messages/data/message_outbox.dart';
import 'package:real_estate_mobile/features/messages/data/message_repository.dart';
import 'package:real_estate_mobile/features/messages/domain/message_models.dart';
import 'package:real_estate_mobile/features/messages/presentation/conversation_screen.dart';

const _body = 'Authoritative conversation message';
const _clientId = 'acknowledged-client';

AuthUser _user(int id) => AuthUser.fromJson({
      'id': id,
      'name': 'Synthetic actor $id',
      'account_status': 'active',
      'phone_verified_at': '2026-11-17T00:00:00Z'
    });

class _Auth extends AuthController {
  @override
  Future<AuthUser?> build() async => _user(1);
  void change(int id) => state = AsyncData(_user(id));
}

class _Credentials implements AuthRepository {
  @override
  Future<Options> requiredAuthOptions() async =>
      Options(headers: {'Authorization': 'Bearer synthetic-only'});
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}

class _Messages implements MessageRepository {
  int reads = 0;
  @override
  Future<MessageThreadDetails> details(int threadId, {int? beforeId}) async {
    reads++;
    return const MessageThreadDetails(
        thread: MessageThreadSummary(
            id: 10,
            otherUserId: 41,
            otherUserName: 'Synthetic peer',
            unreadCount: 0),
        messages: [
          PrivateMessageItem(
              id: 5,
              senderUserId: 1,
              senderName: 'Synthetic actor 1',
              body: _body,
              isMine: true,
              clientMessageId: _clientId)
        ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}

// Controlled futures keep these Widget tests independent of real file IO,
// path_provider and native Keystore while retaining the actual outbox provider.
class _DelayedOutboxStore extends OfflineStore {
  final pending = Completer<Map<String, dynamic>?>();
  int reads = 0, writes = 0;
  Map<String, dynamic>? saved;

  @override
  Future<Map<String, dynamic>?> read(String space, String identity,
      {bool private = false, bool strict = false}) {
    if (space != 'outbox') throw StateError('Unexpected store $space');
    reads++;
    return pending.future;
  }

  @override
  Future<void> write(String space, String identity, Map<String, dynamic> data,
      {bool private = false, bool Function()? current}) async {
    if (current?.call() == false) return;
    writes++;
    saved = data;
  }

  void restoreAcknowledgedMessage() => pending.complete({
        'messages': [
          {
            'id': _clientId,
            'target': 'thread',
            'target_id': 10,
            'thread_id': 10,
            'body': _body,
            'created_at': '2026-11-17T00:00:00Z',
            'status': 'sent'
          }
        ]
      });
}

class _Harness {
  final store = _DelayedOutboxStore();
  final messages = _Messages();
  final auth = _Auth();
  late final ProviderContainer container;

  Future<void> open(WidgetTester tester) async {
    container = ProviderContainer(overrides: [
      authControllerProvider.overrideWith(() => auth),
      authRepositoryProvider.overrideWithValue(_Credentials()),
      messageRepositoryProvider.overrideWithValue(messages),
      offlineStoreProvider.overrideWithValue(store),
    ]);
    addTearDown(() {
      if (!store.pending.isCompleted) store.pending.complete(null);
      container.dispose();
    });
    await container.read(authControllerProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ConversationScreen(threadId: 10))));
    await tester.pumpAndSettle();
  }

  void expectReceivedConversation() {
    expect(messages.reads, 1);
    expect(find.text('Synthetic peer'), findsOneWidget);
    expect(find.text(_body), findsOneWidget);
    expect(find.byType(AppLoadingState), findsNothing);
    expect(find.byType(AppErrorState), findsNothing);
    final report = find.byTooltip('بلاغ');
    expect(report, findsOneWidget);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is IconButton &&
            widget.tooltip == 'بلاغ' &&
            widget.onPressed != null),
        findsOneWidget);
  }
}

void main() {
  testWidgets('received conversation renders before delayed outbox restoration',
      (tester) async {
    final h = _Harness();
    await h.open(tester);
    expect(h.store.reads, 1);
    expect(h.store.pending.isCompleted, false);
    h.expectReceivedConversation();

    h.store.restoreAcknowledgedMessage();
    await tester.pumpAndSettle();
    h.expectReceivedConversation();
    expect(h.store.writes, 1);
    expect(h.store.saved?['messages'], isEmpty);
    expect(h.container.read(messageOutboxProvider(1)), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed outbox restoration cannot hide a received conversation',
      (tester) async {
    final h = _Harness();
    await h.open(tester);
    h.expectReceivedConversation();

    h.store.pending.completeError(StateError('Synthetic local cipher failure'));
    await tester.pumpAndSettle();
    h.expectReceivedConversation();
    expect(h.store.writes, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('late outbox restoration cannot revive a previous actor page',
      (tester) async {
    final h = _Harness();
    await h.open(tester);
    h.expectReceivedConversation();

    h.auth.change(2);
    await tester.pumpAndSettle();
    expect(find.text('تغيّر الحساب'), findsOneWidget);
    expect(find.text(_body), findsNothing);
    h.store.restoreAcknowledgedMessage();
    await tester.pumpAndSettle();
    expect(find.text('تغيّر الحساب'), findsOneWidget);
    expect(find.text(_body), findsNothing);
    expect(h.store.writes, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

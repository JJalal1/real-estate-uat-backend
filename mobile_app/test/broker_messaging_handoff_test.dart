import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:real_estate_mobile/core/offline/offline_connection.dart';
import 'package:real_estate_mobile/core/offline/offline_store.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/broker/data/broker_repository.dart';
import 'package:real_estate_mobile/features/messages/data/message_repository.dart';
import 'package:real_estate_mobile/features/messages/data/message_typing_repository.dart';
import 'package:real_estate_mobile/features/messages/domain/message_models.dart';
import 'package:real_estate_mobile/features/messages/presentation/conversation_screen.dart';

const _threadId = 19;
const _propertyId = 37;
const _otherParty = 'عميل الاختبار';

final _property = find.byKey(const ValueKey('conversation-property'));
final _classification =
    find.byKey(const ValueKey('conversation-classification'));
final _followup = find.byKey(const ValueKey('conversation-followup'));
final _send = find.byKey(const ValueKey('broker-conversation-send'));
final _indicator = find.byKey(const ValueKey('conversation-peer-typing'));

class _Session extends AuthController {
  @override
  Future<AuthUser?> build() async => AuthUser.fromJson({
        'id': 1,
        'name': 'الدلال',
        'account_status': 'active',
        'phone_verified_at': '2026-11-10T00:00:00Z',
        'profile_completed_at': '2026-11-10T00:00:00Z',
        'verification_profile': {'type': 'broker', 'status': 'approved'},
      });
}

class _Broker implements BrokerRepository {
  String stage = 'new';
  String note = 'ملاحظة محفوظة';
  DateTime? reminder;
  final updated = <int>[];

  @override
  Future<void> updateCustomer(int threadId, String stage) async {
    expectSync(threadId, _threadId);
    updated.add(threadId);
    this.stage = stage;
  }

  @override
  Future<Map<String, dynamic>> followup(int threadId) async {
    expectSync(threadId, _threadId);
    return {'private_note': note, 'remind_at': reminder?.toIso8601String()};
  }

  @override
  Future<void> saveFollowup(int threadId,
      {required String note, DateTime? remindAt}) async {
    expectSync(threadId, _threadId);
    this.note = note;
    reminder = remindAt;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Messages implements MessageRepository {
  _Messages(this.broker);
  final _Broker broker;
  final sent = <String>[];

  @override
  Future<MessageThreadDetails> details(int threadId, {int? beforeId}) async {
    expectSync(threadId, _threadId);
    return MessageThreadDetails.fromJson({
      'thread': {
        'id': _threadId,
        'property_id': _propertyId,
        'property_title': 'عنوان الإعلان القديم',
        'property_status': 'paused',
        'can_manage_customer': true,
        'lead_stage': broker.stage,
        'customer_stage_classification_v2': true,
        'other_user': {'id': 2, 'name': _otherParty},
      },
      'messages': [
        {
          'id': 1,
          'sender_user_id': 2,
          'sender_name': _otherParty,
          'body': 'هل يتاح الموقع؟',
          'created_at': '2026-11-12T06:00:00Z'
        },
        {
          'id': 2,
          'sender_user_id': 1,
          'sender_name': 'الدلال',
          'body': 'سأرسل التفاصيل',
          'is_mine': true
        },
      ],
    });
  }

  @override
  Future<PrivateMessageItem> send(int threadId, String body,
      {String? clientMessageId}) async {
    expectSync(threadId, _threadId);
    sent.add(body);
    return PrivateMessageItem(
        id: 3,
        senderUserId: 1,
        senderName: 'الدلال',
        body: body,
        isMine: true,
        clientMessageId: clientMessageId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Typing implements MessageTypingRepository {
  bool peer = false;
  int polls = 0;
  final writes = <bool>[];

  @override
  Future<bool> read(int threadId) async {
    expectSync(threadId, _threadId);
    polls++;
    return peer;
  }

  @override
  Future<void> setTyping(int threadId, bool typing) async {
    expectSync(threadId, _threadId);
    writes.add(typing);
  }
}

class _OutboxStore extends OfflineStore {
  Map<String, dynamic>? _data;

  @override
  Future<Map<String, dynamic>?> read(String space, String identity,
          {bool private = false, bool strict = false}) async =>
      _data;

  @override
  Future<void> write(String space, String identity, Map<String, dynamic> data,
      {bool private = false, bool Function()? current}) async {
    if (current?.call() != false) _data = Map.of(data);
  }
}

Future<GoRouter> _mount(
  WidgetTester tester,
  _Broker broker, {
  bool dark = false,
  double scale = 1,
  double width = 390,
  _Typing? typing,
  _Messages? messages,
}) async {
  tester.view.physicalSize = Size(width, 820);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(routes: [
    GoRoute(
        path: '/',
        builder: (_, __) => const ConversationScreen(threadId: _threadId)),
    GoRoute(
        path: '/properties/:id',
        builder: (_, state) =>
            Scaffold(body: Text('property-${state.pathParameters['id']}'))),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(_Session.new),
        brokerRepositoryProvider.overrideWithValue(broker),
        brokerThreadDealProvider.overrideWith((_, __) async => null),
        messageRepositoryProvider
            .overrideWithValue(messages ?? _Messages(broker)),
        offlineStoreProvider.overrideWithValue(_OutboxStore()),
        if (typing != null) ...[
          messageTypingRepositoryProvider.overrideWithValue(typing),
          offlineConnectionProvider
              .overrideWith((_) => OfflineConnectionController()..online()),
        ],
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: dark ? AppTheme.dark : AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      )));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  for (final dark in [false, true]) {
    testWidgets(
        'broker conversation uses the RTL action row, clean bubbles and round send in ${dark ? 'dark' : 'light'} mode',
        (tester) async {
      final broker = _Broker();
      final router =
          await _mount(tester, broker, dark: dark, width: 320, scale: 2.4);
      expect(tester.getCenter(_property).dx,
          greaterThan(tester.getCenter(_classification).dx));
      expect(tester.getCenter(_classification).dx,
          greaterThan(tester.getCenter(_followup).dx));
      expect(find.text('عنوان الإعلان القديم'), findsNothing);
      expect(find.text('غير متاح'), findsNothing);
      expect(find.text('إدارة العميل'), findsNothing);
      expect(find.text(_otherParty), findsOneWidget);
      expect(find.text('الدلال'), findsNothing);
      expect(find.text('هل يتاح الموقع؟'), findsOneWidget);
      expect(find.text('سأرسل التفاصيل'), findsOneWidget);
      final send = tester.widget<IconButton>(_send);
      expect(send.style!.shape!.resolve({}), isA<CircleBorder>());
      final colors = (dark ? AppTheme.dark : AppTheme.light).colorScheme;
      expect(send.style!.foregroundColor!.resolve({}), colors.onPrimary);
      expect(send.style!.backgroundColor!.resolve({}), colors.primary);
      final icon = send.icon as Icon;
      expect(icon.icon, Icons.send_rounded);
      expect(icon.textDirection, TextDirection.rtl);
      await tester.tap(_property);
      await tester.pumpAndSettle();
      expect(find.text('property-$_propertyId'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      await tester.tap(_classification);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('customer-stage-reserved')));
      await tester.pumpAndSettle();
      expect(broker.stage, 'reserved');
      expect(broker.updated, [_threadId]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('private followup restores the note and both reminder choices',
      (tester) async {
    final broker = _Broker();
    await _mount(tester, broker);
    await tester.tap(_followup);
    await tester.pumpAndSettle();
    final note = find.byKey(const ValueKey('broker-private-note'));
    expect(tester.widget<TextField>(note).maxLength, 1500);
    expect(tester.widget<TextField>(note).controller!.text, 'ملاحظة محفوظة');
    await tester.enterText(note, 'موعد خاص بالدلال');
    await tester.tap(find.text('ذكّرني غدًا'));
    await tester.tap(find.text('حفظ المتابعة'));
    await tester.pumpAndSettle();
    expect(broker.note, 'موعد خاص بالدلال');
    expect(broker.reminder?.hour, 9);
    await tester.tap(_followup);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(note).controller!.text, 'موعد خاص بالدلال');
    expect(find.textContaining('موعد المتابعة'), findsOneWidget);
    await tester.tap(find.text('اختيار موعد'));
    await tester.pumpAndSettle();
    final calendar = find.byType(DatePickerDialog);
    expect(calendar, findsOneWidget);
    await tester.tap(find.text(
        MaterialLocalizations.of(tester.element(calendar)).okButtonLabel));
    await tester.pumpAndSettle();
    final clock = find.byType(TimePickerDialog);
    expect(clock, findsOneWidget);
    await tester.tap(find
        .text(MaterialLocalizations.of(tester.element(clock)).okButtonLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ المتابعة'));
    await tester.pumpAndSettle();
    expect(broker.reminder, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'peer typing animates above the composer and clears on idle, send and route loss',
      (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final typing = _Typing();
    final broker = _Broker();
    final messages = _Messages(broker);
    await _mount(tester, broker, typing: typing, messages: messages);
    final field = find.byType(TextField);
    typing.peer = true;
    await tester.pump(const Duration(milliseconds: 1250));
    await tester.pump();
    expect(_indicator, findsOneWidget);
    expect(tester.getCenter(_indicator).dx,
        greaterThan(tester.getCenter(field).dx));
    expect(
        tester.getCenter(_indicator).dy, lessThan(tester.getCenter(field).dy));
    typing.peer = false;
    await tester.pump(const Duration(milliseconds: 1250));
    await tester.pump();
    expect(_indicator, findsNothing);
    await tester.enterText(field, 'رسالة');
    await tester.enterText(field, 'رسالة جديدة');
    await tester.pump();
    expect(typing.writes, [true]);
    await tester.pump(const Duration(seconds: 2));
    expect(typing.writes, [true, false]);
    await tester.enterText(field, 'نص مرسل');
    await tester.pump();
    await tester.tap(_send);
    await tester.pumpAndSettle();
    expect(typing.writes, [true, false, true, false]);
    expect(messages.sent, ['نص مرسل']);
    await tester.enterText(field, 'لم أرسل هذه الرسالة');
    await tester.pump(const Duration(milliseconds: 1900));
    expect(typing.writes.last, isTrue);
    await tester.tap(_property);
    await tester.pumpAndSettle();
    expect(typing.writes.last, isFalse);
    final polls = typing.polls;
    await tester.pump(const Duration(seconds: 5));
    expect(typing.polls, polls);
    await tester.pumpWidget(const SizedBox.shrink());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  });
}

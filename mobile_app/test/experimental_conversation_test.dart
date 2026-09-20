import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/design/app_design.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/agreements/data/agreement_repository.dart';
import 'package:real_estate_mobile/features/agreements/domain/agreement_models.dart';
import 'package:real_estate_mobile/features/bookings/data/booking_repository.dart';
import 'package:real_estate_mobile/features/bookings/domain/booking_models.dart';
import 'package:real_estate_mobile/features/messages/data/message_repository.dart';
import 'package:real_estate_mobile/features/messages/domain/message_models.dart';
import 'package:real_estate_mobile/features/messages/presentation/conversation_screen.dart';

import 'support/capture_design.dart';
import 'support/design_test_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadDesignTestFonts);
  for (final viewport in [
    (const Size(320, 915), 1.0), (const Size(320, 915), 2.4),
    (const Size(412, 915), 2.4), (const Size(600, 280), 2.4),
  ]) {
    testWidgets('conversation RTL $viewport keeps messages, context and composer usable', (tester) async {
      final repository = _Messages();
      final bookings = _Bookings();
      final key = GlobalKey();
      await _open(tester, repository, bookings: bookings, size: viewport.$1, scale: viewport.$2, captureKey: key);
      expect(find.text('جاهزون للاتفاق؟'), findsOneWidget);
      expect(find.text('طلب معاينة مرتبط بهذه المحادثة'), findsOneWidget);
      expect(find.text('رفض'), findsNothing);
      expect(find.text('إلغاء'), findsNothing);
      await _tap(tester, find.text('تأكيد الموعد'));
      expect(bookings.confirmed, 7);
      expect(find.text('مؤكد'), findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.byType(ConversationScreen))).removeCurrentSnackBar();
      await _enter(tester, '  رسالة عربية ABC-12 عن العقار  ');
      await _tap(tester, find.byTooltip('إرسال الرسالة'));
      expect(repository.sent, ['رسالة عربية ABC-12 عن العقار']);
      expect(repository.keys.single, startsWith('m-10-'));
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
      expect(tester.takeException(), isNull);
      await captureDesign(tester, key, 'conversation-${viewport.$1.width.toInt()}-${viewport.$1.height.toInt()}-${viewport.$2}');
    });
  }

  for (final size in [const Size(320, 568), const Size(600, 280)]) {
    testWidgets('report dialog preserves reasons, validation and payload at $size', (tester) async {
      final repository = _Messages();
      final key = GlobalKey();
      await _open(tester, repository, size: size, scale: 2.4, captureKey: key);
      await _tap(tester, find.byTooltip('بلاغ'));
      final field = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
      expect(tester.widget<TextField>(field).maxLength, 5000);
      expect(find.textContaining('لن يفتح فريق الدعم'), findsOneWidget);
      await _reveal(tester, field);
      await tester.enterText(field, 'قصير');
      await _tap(tester, find.text('إرسال البلاغ'));
      expect(repository.reports, isEmpty);
      expect(find.text('اكتب تفاصيل واضحة للبلاغ لا تقل عن 5 أحرف.'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _tap(tester, find.byTooltip('بلاغ'));
      final choices = find.byType(DropdownButtonFormField<String>);
      await _tap(tester, choices);
      await _tap(tester, find.text('خصوصية').last);
      await _reveal(tester, field);
      await tester.enterText(field, '  تفاصيل واضحة لبلاغ الخصوصية  ');
      await tester.pumpAndSettle();
      await captureDesign(tester, key, 'conversation-report-${size.width.toInt()}-${size.height.toInt()}-2.4');
      await _tap(tester, find.text('إرسال البلاغ'));
      expect(repository.reports, [(10, 'privacy', 'تفاصيل واضحة لبلاغ الخصوصية')]);
      expect(tester.takeException(), isNull);

      await _tap(tester, find.byTooltip('بلاغ'));
      expect(tester.widget<DropdownButtonFormField<String>>(choices).initialValue, 'abuse');
      await _reveal(tester, field);
      await tester.enterText(field, 'لا ترسل هذا البلاغ');
      await _tap(tester, find.descendant(of: find.byType(AlertDialog), matching: find.text('إلغاء')));
      expect(repository.reports, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

  for (final action in ['decline', 'cancel']) {
    testWidgets('booking $action reason retains post-dismiss validation and cancellation', (tester) async {
      final repository = _Messages();
      final bookings = _Bookings(reasonAction: action);
      await _open(tester, repository, bookings: bookings, size: const Size(600, 280), scale: 2.4);
      final actionLabel = action == 'decline' ? 'رفض' : 'إلغاء';
      await _tap(tester, find.text(actionLabel));
      final field = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
      expect(tester.widget<TextField>(field).maxLength, 1500);
      await _reveal(tester, field);
      await tester.enterText(field, 'س');
      await _tap(tester, find.text('تأكيد'));
      expect(bookings.reasons, isEmpty);
      expect(tester.takeException(), isNull);
      await _tap(tester, find.text(actionLabel));
      await _reveal(tester, field);
      await tester.enterText(field, 'سبب لن يتم إرساله');
      await _tap(tester, find.descendant(of: find.byType(AlertDialog), matching: find.text('إلغاء')));
      expect(bookings.reasons, isEmpty);
      expect(tester.takeException(), isNull);
      await _tap(tester, find.text(actionLabel));
      await _reveal(tester, field);
      await tester.enterText(field, '  سبب واضح للطلب  ');
      await _tap(tester, find.text('تأكيد'));
      expect(bookings.reasons, [(action, 7, 'سبب واضح للطلب')]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('edited retry gets a new key; identical retry keeps the key', (tester) async {
    final repository = _Messages()..sendFailures = 2;
    await _open(tester, repository);
    await _enter(tester, 'رسالة أولى');
    await _tap(tester, find.byTooltip('إرسال الرسالة'));
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'رسالة أولى');
    // Wait for the existing error SnackBar to leave the composer hit area.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await _enter(tester, 'رسالة ثانية');
    await _tap(tester, find.byTooltip('إرسال الرسالة'));
    expect(repository.keys[0], isNot(repository.keys[1]));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await _tap(tester, find.byTooltip('إرسال الرسالة'));
    expect(repository.keys[1], repository.keys[2]);
    expect(repository.sent, ['رسالة أولى', 'رسالة ثانية', 'رسالة ثانية']);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('older messages deduplicate and retain current-page content', (tester) async {
    final repository = _Messages();
    await _open(tester, repository);
    final scroll = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable));
    await tester.scrollUntilVisible(find.text('تحميل رسائل أقدم'), -250, scrollable: scroll, maxScrolls: 30);
    await tester.pumpAndSettle();
    await _tap(tester, find.text('تحميل رسائل أقدم'));
    expect(repository.beforeId, 2);
    expect(find.text('تحميل رسائل أقدم'), findsNothing);
    expect(find.text('نسخة قديمة يجب ألا تستبدل الرسالة الحالية'), findsNothing);
    expect(repository.detailCalls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unavailable property keeps conversation and hides new agreement', (tester) async {
    final repository = _Messages()..unavailable = true;
    await _open(tester, repository, bookings: _Bookings(empty: true));
    expect(find.text('جاهزون للاتفاق؟'), findsNothing);
    expect(find.textContaining('هذا الإعلان لم يعد منشوراً'), findsOneWidget);
    await _enter(tester, 'تنسيق بشأن المحادثة المحفوظة');
    await _tap(tester, find.byTooltip('إرسال الرسالة'));
    expect(repository.sent.single, 'تنسيق بشأن المحادثة المحفوظة');
    expect(tester.takeException(), isNull);
  });

  testWidgets('conversation loading and retry resolve to empty without disabling composer', (tester) async {
    final initial = Completer<MessageThreadDetails>();
    final repository = _Messages()..pending = initial;
    await _open(tester, repository, size: const Size(600, 280), scale: 2.4, settle: false);
    expect(find.byType(AppLoadingState), findsOneWidget);
    initial.completeError(StateError('fixture failure'));
    await tester.pumpAndSettle();
    repository.pending = null;
    repository.items = [];
    await _tap(tester, find.text('إعادة المحاولة'));
    expect(repository.detailCalls, 2);
    expect(find.text('ابدأ المحادثة برسالة محترمة وواضحة.'), findsOneWidget);
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send)).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });
}

const _thread = MessageThreadSummary(id: 10, otherUserId: 4,
  otherUserName: 'معلن العقار في صنعاء', unreadCount: 0, propertyId: 9,
  propertyTitle: 'شقة في حدة ABC-12', propertyStatus: 'published');
PrivateMessageItem _message(int id, String text, {bool mine = false}) => PrivateMessageItem(
  id: id, senderUserId: mine ? 1 : 4, senderName: mine ? 'أنت' : 'معلن العقار', body: text,
  isMine: mine, createdAt: DateTime(2026, 1, 1, 12, id));
class _Messages extends MessageRepository {
  _Messages() : super(Dio(), AuthRepository(Dio()));
  List<PrivateMessageItem> items = [_message(2, 'رسالة العقار الحالية'), _message(3, 'أهلاً، هل العقار متاح للمعاينة؟', mine: true)];
  final reports = <(int, String, String)>[];
  final sent = <String>[];
  final keys = <String?>[];
  int sendFailures = 0;
  int detailCalls = 0;
  int? beforeId;
  bool unavailable = false;
  Completer<MessageThreadDetails>? pending;
  @override
  Future<MessageThreadDetails> details(int threadId, {int? beforeId}) async {
    detailCalls++;
    this.beforeId = beforeId;
    if (pending != null) return pending!.future;
    final thread = unavailable ? const MessageThreadSummary(id: 10, otherUserId: 4, otherUserName: 'معلن العقار', unreadCount: 0,
      propertyId: 9, propertyStatus: 'archived') : _thread;
    return MessageThreadDetails(thread: thread,
      messages: beforeId == null ? items : [_message(1, 'رسالة أقدم'), _message(2, 'نسخة قديمة يجب ألا تستبدل الرسالة الحالية')],
      hasMore: beforeId == null && items.isNotEmpty, nextBeforeId: beforeId == null ? 2 : null);
  }
  @override
  Future<void> report(int threadId, {required String reason, required String details}) async {
    reports.add((threadId, reason, details));
  }
  @override
  Future<PrivateMessageItem> send(int threadId, String body, {String? clientMessageId}) async {
    sent.add(body); keys.add(clientMessageId);
    if (sendFailures > 0) { sendFailures--; throw StateError('fixture send failure'); }
    final item = _message(4, body, mine: true);
    items = [...items, item];
    return item;
  }
}
class _Bookings extends BookingRepository {
  _Bookings({this.empty = false, this.reasonAction}) : super(Dio(), AuthRepository(Dio()));
  final bool empty;
  final String? reasonAction;
  final reasons = <(String, int, String)>[];
  int? confirmed;
  ViewingBooking _booking({bool confirmed = false}) => ViewingBooking.fromJson({
    'id': 7, 'reference': 'QA-7', 'requester_user_id': 1, 'requester_name': 'طالب المعاينة',
    'host_user_id': 4, 'host_name': 'المعلن', 'message_thread_id': 10, 'target_id': 9,
    'target_title': 'شقة الاختبار', 'starts_at': '2030-01-01T12:00:00Z', 'ends_at': '2030-01-01T13:00:00Z',
    'status': confirmed ? 'confirmed' : 'requested', 'can_confirm': !confirmed, 'can_manage': true,
    'can_decline': reasonAction == 'decline', 'can_cancel': reasonAction == 'cancel',
  });
  @override
  Future<ViewingBooking> decline(int bookingId, String reason) async {
    reasons.add(('decline', bookingId, reason)); return _booking();
  }
  @override
  Future<ViewingBooking> cancel(int bookingId, String reason) async {
    reasons.add(('cancel', bookingId, reason)); return _booking();
  }
  @override
  Future<List<ViewingBooking>> mine() async => empty ? [] : [_booking()];
  @override
  Future<ViewingBooking> confirm(int bookingId, {String? note}) async { confirmed = bookingId; return _booking(confirmed: true); }
}
class _Agreements extends AgreementRepository {
  _Agreements() : super(Dio(), AuthRepository(Dio()));
  @override
  Future<List<PropertyAgreement>> mine() async => [];
}
Future<void> _reveal(WidgetTester tester, Finder target) async {
  await Scrollable.ensureVisible(tester.element(target), alignment: .5);
  await tester.pumpAndSettle();
}
Future<void> _tap(WidgetTester tester, Finder target) async {
  await _reveal(tester, target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}
Future<void> _enter(WidgetTester tester, String text) async {
  final field = find.byType(TextField);
  await _reveal(tester, field);
  await tester.enterText(field, text);
  await tester.pumpAndSettle();
}
Future<void> _open(WidgetTester tester, _Messages repository, {
  _Bookings? bookings, Size size = const Size(412, 915), double scale = 1,
  GlobalKey? captureKey, bool settle = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(overrides: [
    messageRepositoryProvider.overrideWithValue(repository), bookingRepositoryProvider.overrideWithValue(bookings ?? _Bookings(empty: true)),
    agreementRepositoryProvider.overrideWithValue(_Agreements()),
  ], child: RepaintBoundary(key: captureKey, child: MaterialApp(theme: AppTheme.light, debugShowCheckedModeBanner: false,
    builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
    home: const ConversationScreen(threadId: 10),
  ))));
  if (settle) { await tester.pumpAndSettle(); } else { await tester.pump(); }
}

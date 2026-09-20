import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/design/app_design.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/messages/data/message_repository.dart';
import 'package:real_estate_mobile/features/messages/domain/message_models.dart';
import 'package:real_estate_mobile/features/messages/presentation/conversation_screen.dart';
import 'package:real_estate_mobile/features/messages/presentation/messages_screen.dart';

import 'support/capture_design.dart';
import 'support/design_test_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadDesignTestFonts);
  for (final viewport in [
    (const Size(320, 915), 1.0), (const Size(320, 915), 2.4),
    (const Size(412, 915), 2.4), (const Size(600, 280), 2.4),
  ]) {
    testWidgets('inbox RTL $viewport retains unread and unavailable threads', (tester) async {
      final repository = _Repository();
      final key = GlobalKey();
      await _open(tester, repository, size: viewport.$1, scale: viewport.$2, captureKey: key);
      expect(find.text('عندك 2 رسالة غير مقروءة'), findsOneWidget);
      await _reveal(tester, find.text(_name));
      expect(tester.widget<Text>(find.text(_name)).maxLines, isNull);
      await captureDesign(tester, key, 'inbox-${viewport.$1.width.toInt()}-${viewport.$1.height.toInt()}-${viewport.$2}');
      await _reveal(tester, find.text('الإعلان غير متاح حاليًا • المحادثة محفوظة'));
      expect(tester.takeException(), isNull);
      await _tap(tester, find.byType(FilterChip));
      expect(tester.widget<FilterChip>(find.byType(FilterChip)).selected, isTrue);
      await _reveal(tester, find.text(_name));
      expect(find.text('محادثة مقروءة'), findsNothing);
      expect(repository.calls, 1, reason: 'Unread filter remains local.');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('inbox opens original thread and refreshes on return', (tester) async {
    final repository = _Repository();
    await _open(tester, repository);
    await _tap(tester, find.text(_name));
    expect(tester.widget<ConversationScreen>(find.byType(ConversationScreen)).threadId, 10);
    expect(repository.openedId, 10);
    Navigator.of(tester.element(find.byType(ConversationScreen))).pop();
    await tester.pumpAndSettle();
    expect(repository.calls, 2);
    expect(find.byType(MessagesScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inbox loading, error retry and empty are scroll-safe', (tester) async {
    final initial = Completer<List<MessageThreadSummary>>();
    final repository = _Repository()..pending = initial;
    await _open(tester, repository, size: const Size(600, 280), scale: 2.4, settle: false);
    expect(find.byType(AppSkeleton), findsWidgets);
    initial.completeError(StateError('fixture unavailable'));
    await tester.pumpAndSettle();
    expect(find.byType(AppErrorState), findsOneWidget);
    repository.pending = null;
    repository.items = [];
    await _tap(tester, find.text('إعادة المحاولة'));
    expect(repository.calls, 2);
    expect(find.text('لا توجد محادثات بعد'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('read-only inbox retains filtered-empty state and revision reload', (tester) async {
    final repository = _Repository()..items = [_read];
    final container = await _open(tester, repository);
    await _tap(tester, find.byType(FilterChip));
    expect(find.text('ما عندك رسائل غير مقروءة'), findsOneWidget);
    repository.items = [_unread, _read];
    container.read(messageDataRevisionProvider.notifier).state++;
    await tester.pumpAndSettle();
    expect(repository.calls, 2);
    expect(find.text('عندك 2 رسالة غير مقروءة'), findsOneWidget);
    await _reveal(tester, find.text(_name));
    expect(find.text('محادثة مقروءة'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

const _name = 'مكتب عقارات صنعاء باسم عربي طويل ABC-12';
final _unread = MessageThreadSummary(id: 10, otherUserId: 4, otherUserName: _name,
  unreadCount: 2, propertyId: 9, propertyTitle: 'شقة واسعة في حي حدة صنعاء بالقرب من الخدمات', propertyStatus: 'archived',
  lastMessagePreview: 'هل يمكن تنسيق موعد مناسب لزيارة العقار هذا الأسبوع؟', lastMessageAt: DateTime(2026, 1, 1));
const _read = MessageThreadSummary(id: 20, otherUserId: 5, otherUserName: 'محادثة مقروءة', unreadCount: 0);
class _Repository extends MessageRepository {
  _Repository() : super(Dio(), AuthRepository(Dio()));
  List<MessageThreadSummary> items = [_unread, _read];
  Completer<List<MessageThreadSummary>>? pending;
  int calls = 0;
  int? openedId;
  @override
  Future<List<MessageThreadSummary>> threads() async { calls++; return pending == null ? items : pending!.future; }
  @override
  Future<MessageThreadDetails> details(int threadId, {int? beforeId}) async {
    openedId = threadId;
    throw StateError('fixture conversation unavailable');
  }
}
Future<void> _reveal(WidgetTester tester, Finder target) async {
  final scroll = find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first;
  if (target.evaluate().isEmpty) {
    tester.state<ScrollableState>(scroll).position.jumpTo(0);
    await tester.pumpAndSettle();
  }
  await tester.scrollUntilVisible(target, 200, scrollable: scroll, maxScrolls: 100);
  await tester.pumpAndSettle();
}
Future<void> _tap(WidgetTester tester, Finder target) async {
  await _reveal(tester, target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}
Future<ProviderContainer> _open(WidgetTester tester, _Repository repository, {
  Size size = const Size(412, 915), double scale = 1, GlobalKey? captureKey, bool settle = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(overrides: [messageRepositoryProvider.overrideWithValue(repository)],
    child: RepaintBoundary(key: captureKey, child: MaterialApp(theme: AppTheme.light, debugShowCheckedModeBanner: false,
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      home: const MessagesScreen(),
    )),
  ));
  if (settle) { await tester.pumpAndSettle(); } else { await tester.pump(); }
  return ProviderScope.containerOf(tester.element(find.byType(MessagesScreen)));
}

import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:real_estate_mobile/core/local/listing_recovery_store.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/core/widgets/ebroker_card_actions.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/bookings/data/booking_repository.dart';
import 'package:real_estate_mobile/features/bookings/domain/booking_models.dart';
import 'package:real_estate_mobile/features/broker/presentation/broker_activity.dart';
import 'package:real_estate_mobile/features/messages/domain/message_models.dart';
import 'package:real_estate_mobile/features/broker/data/broker_repository.dart';
import 'package:real_estate_mobile/features/broker/domain/broker_models.dart';
import 'package:real_estate_mobile/features/broker/presentation/broker_workspaces.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_editor_screen.dart';
import 'broker_experience_ui_test.dart' show BrokerTestAuth, BrokerTestRepository;

class _Recovery extends ListingRecoveryStore {
  Map<String, dynamic>? snapshot;
  final writes = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>?> read(int userId, int? listingId) async => snapshot;
  @override
  Future<void> write(int userId, int? listingId, Map<String, dynamic> snapshot, List<String> paths) async { writes.add(snapshot); this.snapshot = snapshot; }
  @override
  Future<void> clear(int userId, int? listingId) async { snapshot = null; }
}
class _Customers extends BrokerTestRepository {
  final filters = <String?>[];
  String? savedNote;
  DateTime? savedDate;
  @override
  Future<BrokerPage<BrokerCustomer>> customers({String? stage, int? propertyId, int page = 1, String? filter}) async {
    filters.add(filter);
    return const BrokerPage(items: [BrokerCustomer(threadId: 19, customerName: 'عميل الاختبار', propertyId: 11,
      propertyTitle: 'شقة الاختبار', stage: 'new', unreadCount: 1, privateNote: 'ملاحظة خاصة')], page: 1, lastPage: 1);
  }
  @override
  Future<void> saveFollowup(int threadId, {required String note, DateTime? remindAt}) async { savedNote = note; savedDate = remindAt; }
}
ViewingBooking _viewing(String title, DateTime at) => ViewingBooking.fromJson({
  'id': at.hour, 'reference': 'DAY-${at.hour}', 'requester_user_id': 2, 'requester_name': 'عميل الاختبار',
  'host_user_id': 1, 'host_name': 'دلال الاختبار', 'message_thread_id': 19, 'target_type': 'property', 'target_id': 11,
  'target_title': title, 'starts_at': at.toUtc().toIso8601String(), 'ends_at': at.add(const Duration(hours: 1)).toUtc().toIso8601String(),
  'status': 'requested', 'can_confirm': true, 'can_manage': true, 'can_reschedule': true, 'can_cancel': true,
  'target_latitude': 15.35, 'target_longitude': 44.2,
});
class _Bookings implements BookingRepository {
  DateTime? requestedFrom, requestedBefore;
  @override
  Future<List<ViewingBooking>> mine({DateTime? from, DateTime? before}) async {
    requestedFrom = from; requestedBefore = before;
    final now = DateTime.now();
    return [_viewing('المعاينة المتأخرة', DateTime(now.year, now.month, now.day, 18)),
      _viewing('معاينة الغد', DateTime(now.year, now.month, now.day + 1, 12)),
      _viewing('المعاينة المبكرة', DateTime(now.year, now.month, now.day, 10))];
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
Future<void> _pump(WidgetTester tester, Widget screen, {BrokerTestRepository? repo, ListingRecoveryStore? recovery, BookingRepository? bookings, double scale = 1, GlobalKey? boundary}) async {
  tester.view.physicalSize = const Size(412, 915); tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(overrides: [authControllerProvider.overrideWith(() => BrokerTestAuth(1)),
    brokerRepositoryProvider.overrideWithValue(repo ?? BrokerTestRepository()),
    listingRecoveryStoreProvider.overrideWithValue(recovery ?? _Recovery()),
    if (bookings != null) bookingRepositoryProvider.overrideWithValue(bookings)],
    child: MaterialApp(theme: AppTheme.light, builder: (context, child) => RepaintBoundary(key: boundary, child: MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!)), home: screen)));
  await tester.pumpAndSettle();
}
Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/broker-preview/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fonts = FontLoader('NotoSansArabic')..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
    await fonts.load();
    final primary = FontLoader('PrimaryFont');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) { primary.addFont(rootBundle.load('assets/ebroker/fonts/Manrope-$weight.ttf')); }
    await primary.load();
    final root = Platform.environment['FLUTTER_ROOT']!;
    final icons = await File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytes();
    await (FontLoader('MaterialIcons')..addFont(Future.value(icons.buffer.asByteData()))).load();
    final latin = await File('$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf').readAsBytes();
    for (final name in ['Arial', 'sans-serif']) {
      final font = FontLoader(name)..addFont(Future.value(latin.buffer.asByteData()));
      if (name == 'sans-serif') font.addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
      await font.load();
    }
  });
  test('device recovery isolates accounts/listings and keeps public images after picker cleanup', () async {
    final dir = await Directory.systemTemp.createTemp('listing-recovery-test-');
    addTearDown(() => dir.delete(recursive: true));
    final store = ListingRecoveryStore(directory: () async => dir);
    final photo = File('${dir.path}/picked.jpg'); await photo.writeAsBytes([255, 216, 255, 217]);
    await store.write(1, null, {'step': 3, 'fields': {'title': 'مسودة خاصة'}, 'server_property_id': 11}, [photo.path]);
    await photo.delete();
    final restored = await store.read(1, null);
    expect(restored!['step'], 3); expect(restored['server_property_id'], 11);
    expect(await File((restored['image_paths'] as List).single as String).readAsBytes(), [255, 216, 255, 217]);
    expect(await store.read(2, null), isNull); expect(await store.read(1, 11), isNull);
    await store.write(2, null, {'step': 1}, []); await store.clear(2, null);
    expect(await store.read(1, null), isNotNull);
    await store.clear(1, null); expect(await store.read(1, null), isNull);
  });
  test('queued recovery writes keep the latest progress and tolerate corrupt cache', () async {
    final dir = await Directory.systemTemp.createTemp('listing-recovery-queue-'); addTearDown(() => dir.delete(recursive: true));
    final store = ListingRecoveryStore(directory: () async => dir);
    await Future.wait([store.write(1, null, {'step': 1}, []), store.write(1, null, {'step': 4}, [])]);
    expect((await store.read(1, null))!['step'], 4);
    await File('${dir.path}/listing_recovery/u1/p0/state.json').writeAsString('{broken');
    expect(await store.read(1, null), isNull);
    await store.write(1, null, {'step': 2}, []); expect((await store.read(1, null))!['step'], 2);
  });
  testWidgets('dashboard shortcuts open the exact requested tab and unread filter', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const BrokerDashboardScreen()),
      GoRoute(path: '/broker/activity', builder: (_, state) => Scaffold(body: Text('selected:${state.uri.queryParameters['tab']}'))),
      GoRoute(path: '/broker/customers', builder: (_, state) => Scaffold(body: Text('filter:${state.uri.queryParameters['filter']}'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [authControllerProvider.overrideWith(() => BrokerTestAuth(1)), brokerRepositoryProvider.overrideWithValue(BrokerTestRepository())],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router)));
    await tester.pumpAndSettle();
    expect(find.textContaining('معاينات للمتابعة'), findsNothing);
    await tester.tap(find.textContaining('إجراءات أخرى')); await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('تابع نتائج الصفقات التي تنتظر التأكيد')); await tester.pumpAndSettle();
    await tester.tap(find.text('تابع نتائج الصفقات التي تنتظر التأكيد').hitTestable()); await tester.pumpAndSettle();
    expect(find.text('selected:null'), findsOneWidget);
    router.pop(); await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.textContaining('محادثات تحتاج ردك').hitTestable(), -150, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('محادثات تحتاج ردك').hitTestable()); await tester.pumpAndSettle();
    expect(find.text('filter:unread'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('listing editor restores its actual step and autosaves changed text', (tester) async {
    final recovery = _Recovery()..snapshot = {'step': 0, 'fields': {'title': 'عنوان محفوظ'}, 'purpose': 'sale', 'type': 'apartment'};
    await _pump(tester, const ListingEditorScreen(), recovery: recovery);
    expect(find.text('عنوان محفوظ'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'عنوان جديد'); await tester.pump(const Duration(milliseconds: 750)); await tester.pump();
    expect((recovery.writes.last['fields'] as Map)['title'], 'عنوان جديد');
    await tester.pumpWidget(const SizedBox()); await tester.pump();
    recovery.snapshot = {'step': 3, 'fields': {'price': '125000'}, 'purpose': 'sale', 'type': 'apartment'};
    final boundary = GlobalKey();
    await _pump(tester, const ListingEditorScreen(), recovery: recovery, boundary: boundary);
    await _capture(tester, boundary, 'convenience-restored-step');
    expect(find.text('4/4'), findsOneWidget); expect(find.text('125000'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('customer shortcut applies unread filter and private followup saves through the existing thread', (tester) async {
    final repo = _Customers(); final boundary = GlobalKey();
    await _pump(tester, const BrokerCustomersScreen(initialFilter: 'unread'), repo: repo, boundary: boundary);
    await _capture(tester, boundary, 'convenience-unread-customers');
    expect(repo.filters.last, 'unread'); expect(find.text('ملاحظة خاصة: ملاحظة خاصة'), findsOneWidget);
    await tester.tap(find.byTooltip('خيارات البطاقة')); await tester.pumpAndSettle();
    await tester.tap(find.text('ملاحظة وتذكير')); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'يفضل موعد العصر');
    await tester.tap(find.text('ذكّرني غدًا')); await tester.pumpAndSettle();
    expect(find.textContaining('الملاحظة والتذكير خاصان'), findsOneWidget);
    await _capture(tester, boundary, 'convenience-private-followup');
    await tester.tap(find.text('حفظ المتابعة')); await tester.pumpAndSettle();
    expect(repo.savedNote, 'يفضل موعد العصر'); expect(repo.savedDate, isNotNull); expect(repo.savedDate!.hour, 9);
    expect(tester.takeException(), isNull);
  });
  testWidgets('customer management stays a small action until its sheet opens and never loads bookings', (tester) async {
    final bookings = _Bookings(), boundary = GlobalKey();
    const thread = MessageThreadSummary(id: 19, otherUserId: 2, otherUserName: 'عميل الاختبار', unreadCount: 0,
      propertyId: 11, propertyTitle: 'شقة الاختبار', propertyStatus: 'published', canManageCustomer: true);
    await _pump(tester, const Scaffold(body: Column(children: [Text('المحادثة هي الأساس'), BrokerConversationTools(thread: thread)])),
      bookings: bookings, boundary: boundary);
    expect(find.text('ملاحظة وتذكير'), findsNothing);
    expect(find.text('متابعة العميل'), findsNothing);
    expect(tester.getSize(find.byKey(const ValueKey('conversation-manage-customer'))).height, lessThan(60));
    expect(bookings.requestedFrom, isNull); expect(bookings.requestedBefore, isNull);
    await tester.tap(find.byKey(const ValueKey('conversation-manage-customer'))); await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('ملاحظة وتذكير'), findsOneWidget);
    expect(find.text('متابعة العميل'), findsOneWidget);
    expect(find.text('عرض نتيجة الصفقة'), findsOneWidget);
    expect(find.text('تأكيد الموعد'), findsNothing);
    await _capture(tester, boundary, 'wave4-customer-management');
    expect(tester.takeException(), isNull);
  });
  testWidgets('card secondary actions stay reachable with enlarged Arabic text', (tester) async {
    var chosen = false;
    await _pump(tester, Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: EbrokerCardActions(actions: [
      EbrokerCardAction('تأكيد التوفر', () {}), EbrokerCardAction('المحادثة الخاصة بالعقار', () => chosen = true),
    ]))), scale: 2.4);
    expect(find.text('المحادثة الخاصة بالعقار'), findsNothing);
    await tester.tap(find.byTooltip('خيارات البطاقة')); await tester.pumpAndSettle();
    await tester.tap(find.text('المحادثة الخاصة بالعقار')); await tester.pumpAndSettle();
    expect(chosen, isTrue); expect(tester.takeException(), isNull);
  });
}

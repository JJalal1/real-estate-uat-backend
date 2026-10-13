import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:real_estate_mobile/core/local/listing_recovery_store.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/discovery/domain/assisted_property_search.dart';
import 'package:real_estate_mobile/features/discovery/presentation/assisted_search_screen.dart';
import 'package:real_estate_mobile/features/messages/data/message_repository.dart';
import 'package:real_estate_mobile/features/messages/domain/message_models.dart';
import 'package:real_estate_mobile/features/messages/domain/notification_destination.dart';
import 'package:real_estate_mobile/features/messages/presentation/notifications_screen.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/properties/domain/property_sai.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_editor_screen.dart';
import 'broker_experience_ui_test.dart' show BrokerTestAuth;

const _policy = PropertySaiManagement(configured: false, advertiserType: 'broker',
  fixedRatePercent: 1, brokerMaxRatePercent: 5, professionalPlatformSharePercent: 20,
  platformTermsMessage: 'للتطبيق نسبة مقدارها 20% من مبلغ السعي عند إتمام الصفقة.');

class _Recovery extends ListingRecoveryStore {
  _Recovery(this.snapshot);
  Map<String, dynamic>? snapshot;
  @override
  Future<Map<String, dynamic>?> read(int userId, int? listingId) async => snapshot;
  @override
  Future<void> write(int userId, int? listingId, Map<String, dynamic> value, List<String> paths) async { snapshot = value; }
  @override
  Future<void> clear(int userId, int? listingId) async { snapshot = null; }
}

class _Properties implements PropertyRepository {
  final writes = <String>[];
  Map<String, dynamic>? lastInput, lastQuery;
  String? payer;
  double? rate;
  @override
  Future<PropertySaiManagement> saiPolicy(String purpose) async => purpose == 'sale' ? _policy :
    const PropertySaiManagement(configured: false, advertiserType: 'broker', fixedRatePercent: 20,
      brokerMaxRatePercent: 100, professionalPlatformSharePercent: 20);
  @override
  Future<(List<PropertySummary>, bool)> searchListings(Map<String, dynamic> filters, {int page = 1}) async {
    lastQuery = filters;
    return ([PropertySummary.fromJson({'id': 11, 'title': 'شقة من نتائج الخادم', 'type': 'apartment',
      'purpose': 'rent', 'price': 300000, 'monthly_rent': 100000, 'currency': 'YER', 'latitude': 13.5, 'longitude': 44.0})], false);
  }
  @override
  Future<PropertyDetails> details(int id) async => PropertyDetails.fromJson({'id': id,
    'title': 'مسودة محفوظة', 'purpose': 'sale', 'type': 'house', 'price': 10000000,
    'latitude': 15.3694, 'longitude': 44.1910, 'status': 'draft', 'images': []});
  @override
  Future<PropertySaiEnvelope> saiForEditor(int id) async => const PropertySaiEnvelope(management:
    PropertySaiManagement(configured: true, advertiserType: 'broker', purpose: 'sale',
      requestedBrokerRatePercent: 2, platformTermsStatus: 'accepted'));
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #createListing || invocation.memberName == #updateListing) {
      writes.add('draft');
      final input = invocation.positionalArguments.last as PropertyListingInput;
      lastInput = input.toMap();
      return Future<PropertyDetails>.value(PropertyDetails.fromJson({'id': 500, ...lastInput!, 'status': 'draft', 'review_status': 'draft', 'images': []}));
    }
    if (invocation.memberName == #configureSai) {
      writes.add('sai'); payer = invocation.namedArguments[#payer] as String?;
      rate = invocation.namedArguments[#brokerRatePercent] as double?;
      return Future<PropertySaiEnvelope>.value(const PropertySaiEnvelope(management: _policy));
    }
    throw UnimplementedError('$invocation');
  }
}

class _Messages implements MessageRepository {
  bool read = false;
  @override
  Future<List<AppNotificationItem>> notifications() async => read ? [] : [AppNotificationItem.fromJson({
    'id': 8, 'type': 'broker_availability_due', 'title': 'أكد توفر إعلاناتك',
    'body': 'لديك إعلانات تحتاج تأكيد التوفر.', 'created_at': DateTime.now().toUtc().toIso8601String(),
  })];
  @override
  Future<void> readNotification(int id) async { read = true; }
  @override
  Future<void> readAllNotifications() async { read = true; }
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Map<String, dynamic> _snapshot({int step = 2, String type = 'house'}) => {
  'editor_version': 4, 'step': step, 'type': type, 'purpose': 'sale', 'tenure_type': 'freehold',
  'latitude': 15.3694, 'longitude': 44.1910, 'parking': 'no', 'facade': 'north', 'sai_touched': true, 'sai_terms_accepted': true,
  'fields': {'title': 'منزل اختبار التحسين', 'description': 'وصف العقار', 'price': '10000000',
    'area': '160', 'bedrooms': '3', 'bathrooms': '2', 'governorate': 'صنعاء', 'district': 'حدة',
    'floor_number': type == 'floor' || type == 'apartment' ? '3' : '',
    'unit_number': type == 'apartment' ? 'شمالية' : '', 'broker_sai_rate_percent': '2'},
};

Future<void> _pump(WidgetTester tester, Widget child, {Map<String, dynamic>? snapshot, _Properties? properties,
  _Messages? messages, double scale = 1, GlobalKey? boundary, GoRouter? router}) async {
  tester.view.physicalSize = const Size(412, 915); tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(overrides: [
    authControllerProvider.overrideWith(() => BrokerTestAuth(1)),
    listingRecoveryStoreProvider.overrideWithValue(_Recovery(snapshot)),
    propertyRepositoryProvider.overrideWithValue(properties ?? _Properties()),
    messageRepositoryProvider.overrideWithValue(messages ?? _Messages()),
  ], child: router == null ? MaterialApp(theme: AppTheme.light,
    builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: RepaintBoundary(key: boundary, child: child!)), home: child) : MaterialApp.router(theme: AppTheme.light, routerConfig: router)));
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final out = File('build/broker-preview/refinement-$name.png');
    await out.parent.create(recursive: true); await out.writeAsBytes(bytes!.buffer.asUint8List()); image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final name in ['sans-serif', 'NotoSansArabic']) {
      await (FontLoader(name)..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'))).load();
    }
    final primary = FontLoader('PrimaryFont');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) { primary.addFont(rootBundle.load('assets/ebroker/fonts/Manrope-$weight.ttf')); }
    await primary.load();
    final root = Platform.environment['FLUTTER_ROOT']!;
    final icons = await File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytes();
    await (FontLoader('MaterialIcons')..addFont(Future.value(icons.buffer.asByteData()))).load();
  });

  test('Arabic brief produces real editable rental filters with monthly price basis', () {
    for (final brief in ['أبغى شقة إيجار في تعز، 3 غرف، أقل من 150 ألف', 'شقة إيجار في تعز، ٣ غرف، حتى ١٥٠٬٠٠٠']) {
      final parsed = AssistedPropertySearch.parse(brief.replaceAll('٬', ','));
      expect(parsed.apiFilters, {'type': 'apartment', 'purpose': 'rent', 'search': 'تعز',
        'min_bedrooms': 3, 'max_monthly_rent': 150000.0, 'currency': 'YER'});
      expect(parsed.without('price').apiFilters.containsKey('max_monthly_rent'), isFalse);
      expect(parsed.without('price').apiFilters.containsKey('currency'), isFalse);
    }
    expect(AssistedPropertySearch.parse('ابحث عن مكان مريح قريب من عملي').isEmpty, isTrue);
    expect(AssistedPropertySearch.parse('فيلا أو شقة للبيع').type, isNull);
  });

  test('commission quote follows supplied policy and zero fallback rather than a hardcoded platform percentage', () {
    const alternate = PropertySaiManagement(configured: false, advertiserType: 'broker',
      fixedRatePercent: 1, brokerMaxRatePercent: 5, professionalPlatformSharePercent: 17.5);
    final quote = PropertySaiQuote.calculate(alternate, 2, 10000000)!;
    expect(quote.total, 200000); expect(quote.platform, 35000); expect(quote.net, 165000);
    final fallback = PropertySaiQuote.calculate(alternate, 0, 10000000)!;
    expect(fallback.total, 100000); expect(fallback.net, 0);
    expect(PropertySaiQuote.calculate(alternate, 5.1, 10000000), isNull);
    expect(PropertySaiQuote.calculate(alternate, double.nan, 10000000), isNull);
  });

  for (final type in ['floor', 'building', 'house', 'apartment', 'shop']) {
    testWidgets('$type asks only meaningful unit and floor questions', (tester) async {
      final key = GlobalKey();
      await _pump(tester, const ListingEditorScreen(), snapshot: _snapshot(type: type), boundary: key);
      expect(find.text('اسم أو رقم المبنى *'), findsNothing);
      expect(find.text('رقم الشقة أو موضعها داخل الدور *'), type == 'apartment' ? findsOneWidget : findsNothing);
      expect(find.text('أي دور؟ *'), type == 'apartment' || type == 'floor' ? findsOneWidget : findsNothing);
      if (type == 'floor') await _capture(tester, key, 'floor');
      if (type == 'shop') {
        await tester.tap(find.byType(CheckboxListTile).first); await tester.pumpAndSettle();
        expect(find.text('أي دور؟ *'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('whole floor is a contextual apartment option and preserves recovery', (tester) async {
    final store = _Recovery(_snapshot(type: 'apartment'));
    await _pump(tester, const ListingEditorScreen(), snapshot: store.snapshot);
    expect(find.text('الوحدة تشغل الدور كاملًا'), findsOneWidget);
    expect(find.text('رقم الشقة أو موضعها داخل الدور *'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('unit-whole-floor')));
    await tester.tap(find.byKey(const ValueKey('unit-whole-floor')));
    await tester.pumpAndSettle();
    expect(find.text('رقم الشقة أو موضعها داخل الدور *'), findsNothing);
    expect(find.text('أي دور؟ *'), findsOneWidget);
    expect(find.text('دور كامل'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fourth step shows inline monetary commission and preview never saves', (tester) async {
    final repository = _Properties(), key = GlobalKey();
    await _pump(tester, const ListingEditorScreen(), snapshot: _snapshot(step: 3), properties: repository, boundary: key);
    expect(find.text('4/4'), findsOneWidget); expect(find.text('من يتحمل السعي؟'), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('listing-sai-total'))); await tester.pumpAndSettle();
    expect(find.text('200000 ريال'), findsOneWidget);
    expect(find.textContaining('صافي السعي: 160000 ريال'), findsOneWidget);
    await _capture(tester, key, 'inline-sai');
    await tester.tap(find.byTooltip('خيارات المسودة')); await tester.pumpAndSettle();
    await tester.tap(find.text('معاينة')); await tester.pumpAndSettle();
    expect(find.text('معاينة قبل الإرسال'), findsOneWidget); expect(repository.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('explicit draft save carries v5 fields and customer-paid commission, without submission', (tester) async {
    final repository = _Properties();
    final router = GoRouter(routes: [GoRoute(path: '/', builder: (_, __) => const ListingEditorScreen()),
      GoRoute(path: '/my-listings', builder: (_, __) => const Scaffold(body: Text('saved listing')))]);
    addTearDown(router.dispose);
    await _pump(tester, const SizedBox(), snapshot: _snapshot(step: 3), properties: repository, router: router);
    await tester.tap(find.byTooltip('خيارات المسودة')); await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ مسودة')); await tester.pumpAndSettle();
    expect(repository.writes, ['draft', 'sai']); expect(repository.lastInput!['listing_input_version'], 5);
    expect(repository.payer, 'buyer'); expect(repository.rate, 2);
    expect(find.text('saved listing'), findsOneWidget); expect(tester.takeException(), isNull);
  });

  testWidgets('recovery does not replace an untouched server commission with an uninitialized default', (tester) async {
    final repository = _Properties();
    final recovery = _snapshot(step: 3)..['server_property_id'] = 77..['sai_touched'] = false;
    (recovery['fields'] as Map)['broker_sai_rate_percent'] = '0';
    final router = GoRouter(routes: [GoRoute(path: '/', builder: (_, __) => const ListingEditorScreen()),
      GoRoute(path: '/my-listings', builder: (_, __) => const Scaffold(body: Text('saved listing')))]);
    addTearDown(router.dispose);
    await _pump(tester, const SizedBox(), snapshot: recovery, properties: repository, router: router);
    await tester.tap(find.byTooltip('خيارات المسودة')); await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ مسودة')); await tester.pumpAndSettle();
    expect(repository.writes, ['draft', 'sai']); expect(repository.rate, 2);
    expect(find.text('saved listing'), findsOneWidget); expect(tester.takeException(), isNull);
  });

  testWidgets('smart search proposes chips before querying and uses the existing public API for results', (tester) async {
    final repository = _Properties(), key = GlobalKey();
    await _pump(tester, const AssistedSearchScreen(), properties: repository, boundary: key);
    await tester.enterText(find.byKey(const ValueKey('smart-search-description')), 'شقة إيجار في تعز، 3 غرف، أقل من 150 ألف');
    await tester.tap(find.text('اقتراح الفلاتر')); await tester.pumpAndSettle();
    expect(repository.lastQuery, isNull); expect(find.text('تعز'), findsOneWidget);
    await _capture(tester, key, 'smart-filters');
    await tester.ensureVisible(find.text('عرض النتائج')); await tester.pumpAndSettle();
    await tester.tap(find.text('عرض النتائج')); await tester.pumpAndSettle();
    expect(repository.lastQuery!['max_monthly_rent'], 150000);
    expect(find.text('شقة من نتائج الخادم'), findsOneWidget); expect(tester.takeException(), isNull);
  });

  testWidgets('notification opens due listings directly and a successful server read removes it', (tester) async {
    final messages = _Messages();
    final router = GoRouter(routes: [GoRoute(path: '/', builder: (_, __) => const NotificationsScreen()),
      GoRoute(path: '/broker/availability', builder: (_, state) => Scaffold(body: Text('due:${state.uri.queryParameters['due']}')))]);
    addTearDown(router.dispose);
    await _pump(tester, const SizedBox(), messages: messages, router: router);
    await tester.tap(find.text('أكد توفر إعلاناتك')); await tester.pumpAndSettle();
    expect(messages.read, isTrue); expect(find.text('due:1'), findsOneWidget);
    router.pop(); await tester.pumpAndSettle(); expect(find.text('أكد توفر إعلاناتك'), findsNothing);
    expect(notificationDestination(AppNotificationItem.fromJson({'id': 1, 'title': 'توفر', 'type': 'broker_availability_due'})), '/broker/availability?due=1');
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.4]) {
    testWidgets('notifications and final editor stay readable with Arabic scale $scale', (tester) async {
      final key = GlobalKey();
      await _pump(tester, const NotificationsScreen(), scale: scale, boundary: key);
      await _capture(tester, key, 'notifications-$scale'); expect(tester.takeException(), isNull);
      await _pump(tester, const ListingEditorScreen(), snapshot: _snapshot(step: 3), scale: scale);
      expect(find.text('إرسال للمراجعة').hitTestable(), findsOneWidget); expect(tester.takeException(), isNull);
    });
  }
}

import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_repository.dart';
import 'package:real_estate_mobile/features/discovery/presentation/marketplace_categories_screen.dart';
import 'support/wave3_fakes.dart';
import 'package:real_estate_mobile/core/widgets/app_components.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/account/presentation/account_screen.dart';
import 'package:real_estate_mobile/features/app_shell/presentation/app_shell_screen.dart';
import 'package:real_estate_mobile/features/broker/data/broker_repository.dart';
import 'package:real_estate_mobile/features/broker/domain/broker_models.dart';
import 'package:real_estate_mobile/features/broker/presentation/broker_workspaces.dart';
import 'package:real_estate_mobile/features/broker/presentation/broker_activity.dart';
import 'package:real_estate_mobile/features/broker/presentation/broker_directory.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/account/data/private_collection.dart';

// Synthetic fixtures are confined to tests; production reads authorized backend data.
final exampleBroker = BrokerProfile.fromJson({'id': 1, 'name': 'دلال عرض تجريبي', 'account_type': 'broker', 'verified': true,
  'governorate': 'أمانة العاصمة', 'bio': 'وساطة عقارية في حدة والسنينة، بيانات تجريبية لاختبار الواجهة.',
  'rating_average': 4.6, 'rating_count': 7, 'completed_deals': 12, 'active_listings': 8,
  'work_areas': ['حدة', 'السنينة'], 'specializations': ['بيع', 'إيجار'], 'joined_at': '2026-07-01'});

AuthUser brokerTestUser([int id = 1]) => AuthUser.fromJson({'id': id, 'name': 'حساب عرض تجريبي', 'email': 'preview@example.test',
  'phone': '+967700000000', 'account_status': 'active', 'phone_verified_at': '2026-10-12T00:00:00Z', 'profile_completed_at': '2026-10-12T00:00:00Z',
  if (id == 1) 'verification_profile': {'type': 'broker', 'status': 'approved', 'reviewed_at': '2026-10-12T00:00:00Z'}});
class BrokerTestAuth extends AuthController {
  BrokerTestAuth([this.id = 1]);
  final int id;
  @override
  Future<AuthUser?> build() async => brokerTestUser(id);
}

Map<String, dynamic> brokerTestWorkspace() => {
  'broker_profile': {'id': 1, 'name': exampleBroker.name, 'account_type': 'broker', 'verified': true, 'rating_average': 4.6, 'rating_count': 7,
    'completed_deals': 12, 'active_listings': 8, 'governorate': 'أمانة العاصمة'},
  'listings': {'published': 8, 'draft': 1}, 'customer_activity': {'unread_conversations': 3, 'new_customers_this_week': 4, 'active_viewings': 2, 'completed_deals': 12},
  'needs_attention': {'availability_count': 2, 'correction_listings': [{'id': 3}], 'pending_deal_count': 1},
  'financial_summary': {'listing_creation_blocked': false},
};

class BrokerTestRepository implements BrokerRepository {
  BrokerTestRepository({this.viewerId = 1, this.rentDue = false});
  final int viewerId;
  final bool rentDue;
  final availabilityChanges = <(List<int>, String)>[];
  final reportedDeals = <(int, double?)>[];
  final decisions = <(int, bool)>[];
  final seenDeals = <(int, int)>[];
  int? dealViewRevision;
  String dealStatus = 'pending_customer';
  bool priceConfirmationRequired = false;
  String transactionType = 'sale';
  @override
  Future<Map<String, dynamic>> workspace() async => brokerTestWorkspace();
  @override
  Future<BrokerProfile> profile(int id) async => exampleBroker;
  @override
  Future<BrokerPage<BrokerProfile>> directory({String? governorate, int page = 1, int perPage = 15, bool regionOnly = false, String? search, String? specialty, String? accountType, double? minRating}) async => BrokerPage(items: [exampleBroker], page: 1, lastPage: 1);
  @override
  Future<List<BrokerAvailability>> availability() async => [
    BrokerAvailability(id: 11, title: 'شقة حدة', purpose: 'sale', status: 'available', needsConfirmation: true),
    BrokerAvailability(id: 12, title: 'منزل السنينة', purpose: 'rent', status: 'available', needsConfirmation: rentDue),
  ];
  @override
  Future<PrivateCollectionPage<BrokerAvailability>> availabilityPage({int page = 1, bool onlyDue = false}) async {
    final updated = availabilityChanges.expand((change) => change.$1).toSet();
    final items = (await availability()).where((item) =>
        !updated.contains(item.id) &&
        (!onlyDue || item.needsConfirmation || item.status == 'confirmation_paused')).toList();
    return PrivateCollectionPage(items: items, currentPage: 1, lastPage: 1, total: items.length);
  }
  @override
  Future<void> updateAvailability(List<int> ids, String state) async { availabilityChanges.add((List.of(ids), state)); }
  @override
  Future<BrokerPage<BrokerCustomer>> customers({String? stage, int? propertyId, int page = 1, String? filter, bool includeOtherThreads = false}) async => const BrokerPage(items: [
    BrokerCustomer(threadId: 19, customerName: 'عميل تجريبي', propertyId: 11, propertyTitle: 'شقة حدة', stage: 'new'),
  ], page: 1, lastPage: 1);
  @override
  Future<BrokerDeal> reportDeal(int threadId, {double? amount}) async {
    reportedDeals.add((threadId, amount));
    return deal(4);
  }
  @override
  Future<BrokerDeal> deal(int id) async => BrokerDeal(id: id, threadId: 19, propertyId: 11, advertiserId: 1, propertyTitle: 'شقة حدة',
    customerName: 'عميل تجريبي', advertiserName: exampleBroker.name, status: dealStatus, amount: 100000000, currency: 'YER',
    canConfirm: viewerId == 2 && dealStatus == 'pending_customer', canRate: viewerId == 2 && dealStatus == 'confirmed',
    advertiserViewRevision: viewerId == 1 ? dealViewRevision : null,
    priceConfirmationRequired: priceConfirmationRequired, transactionType: transactionType);
  @override
  Future<void> markDealSeen(int id, int revision) async {
    seenDeals.add((id, revision));
  }
  @override
  Future<BrokerDeal> decide(int id, bool confirmed) async { decisions.add((id, confirmed)); dealStatus = confirmed ? 'confirmed' : 'disputed'; return deal(id); }
  @override
  Future<BrokerPage<BrokerDeal>> activity({int? threadId, int page = 1}) async => BrokerPage(items: [await deal(4)], page: 1, lastPage: 1);
  @override
  Future<Map<String, dynamic>> finance() async => {'balances': [{'currency': 'YER', 'open': 50000, 'paid': 10000}], 'receivables': [
    {'id': 8, 'reference': 'DUE-PREVIEW', 'property_title': 'شقة حدة', 'basis_amount': 100000000, 'sai_amount': 2000000,
      'amount_total': 50000, 'amount_paid': 0, 'remaining_amount': 50000, 'currency': 'YER', 'status': 'open', 'due_at': '2026-10-13T10:00:00Z'},
  ]};
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}
class BrokerTestProperties implements PropertyRepository {
  @override
  Future<PropertyDetails> details(int propertyId) async => PropertyDetails.fromJson({
    'id': propertyId,
    'title': 'شقة حدة',
    'purpose': 'sale',
    'type': 'apartment',
    'price': 100000000,
    'currency': 'YER',
    'latitude': 15.37,
    'longitude': 44.19,
    'status': 'published',
    'is_owner': true,
  });
  @override
  Future<(List<PropertySummary>, bool)> advertiserListings(int id, {int page = 1, String? purpose}) async => ([PropertySummary.fromJson({
    'id': 11, 'title': 'شقة حدة', 'purpose': 'sale', 'type': 'apartment', 'price': 100000000, 'currency': 'YER', 'latitude': 15.37, 'longitude': 44.19,
  })], false);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<void> _pump(WidgetTester tester, Widget screen, BrokerTestRepository repo, {int userId = 1, double scale = 1, Size size = const Size(412, 915), GlobalKey? boundary}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(overrides: [authControllerProvider.overrideWith(() => BrokerTestAuth(userId)), brokerRepositoryProvider.overrideWithValue(repo),
    propertyRepositoryProvider.overrideWithValue(BrokerTestProperties()),
    marketplaceRepositoryProvider.overrideWithValue(Wave3MarketplaceFake()), homeLocationAttemptedProvider.overrideWith((_) => true)], child: MaterialApp(theme: AppTheme.light, builder: (context, child) =>
      MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: RepaintBoundary(key: boundary, child: child!)), home: screen)));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final arabic = FontLoader('NotoSansArabic')..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'))..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf'));
    await arabic.load();
    final manrope = FontLoader('PrimaryFont');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) { manrope.addFont(rootBundle.load('assets/ebroker/fonts/Manrope-$weight.ttf')); }
    await manrope.load();
    final root = Platform.environment['FLUTTER_ROOT']!;
    final directory = '$root/bin/cache/artifacts/material_fonts';
    final icons = await File('$directory/MaterialIcons-Regular.otf').readAsBytes();
    await (FontLoader('MaterialIcons')..addFont(Future.value(icons.buffer.asByteData()))).load();
    final latin = await File('$directory/Roboto-Regular.ttf').readAsBytes();
    for (final name in ['Arial', 'sans-serif']) {
      final font = FontLoader(name)..addFont(Future.value(latin.buffer.asByteData()));
      if (name == 'sans-serif') font.addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
      await font.load();
    }
  });
  testWidgets('verified broker opens work and the unified message list from the marketplace', (tester) async {
    await _pump(tester, const AppShellScreen(), BrokerTestRepository());
    final nav = tester.widget<AppNavigationBar>(find.byType(AppNavigationBar));
    expect(nav.destinations.map((d) => d.label), ['الرئيسية', 'إعلاناتي', 'الرسائل', 'حسابي']);
    expect(nav.onCreate, isNotNull);
    expect(find.text('مهام تحتاج إجراء'), findsNothing);
    expect(find.byKey(const ValueKey('home-search')), findsOneWidget);
    nav.onSelected(1);
    await tester.pumpAndSettle();
    expect(find.byType(BrokerDashboardScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('broker-achievement-carousel')), findsOneWidget);
    expect(find.text('أدوات عملك'), findsOneWidget);
    expect(find.text('أكمل مسودة'), findsNothing);
    expect(find.text('مشاركة إعلان منشور'), findsNothing);
    expect(find.byKey(const ValueKey('broker-tool-badge-الصفقات')), findsNothing);
    expect(find.byKey(const ValueKey('broker-tool-badge-المستحقات')), findsNothing);
    nav.onSelected(2);
    await tester.pumpAndSettle();
    expect(find.byType(TabBar), findsNothing);
    expect(find.text('كل الحالات'), findsOneWidget);
    expect(find.text('عميل تجريبي'), findsOneWidget);
    expect(find.text('إدارة العملاء'), findsNothing);
    nav.onSelected(3); await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('لوحة العمل'), 300,
      scrollable: find.descendant(of: find.byType(AccountScreen), matching: find.byType(Scrollable)).first);
    await tester.pumpAndSettle();
    expect(find.text('لوحة العمل'), findsOneWidget);
    expect(find.text('إدارة العملاء'), findsOneWidget);
  });
  testWidgets('regular account opens categories from the old messages slot', (tester) async {
    await _pump(tester, const AppShellScreen(), BrokerTestRepository(viewerId: 2), userId: 2);
    final nav = tester.widget<AppNavigationBar>(find.byType(AppNavigationBar));
    expect(nav.destinations.map((destination) => destination.label), ['العقارات', 'الأقسام', 'الرسائل', 'حسابي']);
    nav.onSelected(1);
    await tester.pumpAndSettle();
    expect(find.byType(MarketplaceCategoriesScreen), findsOneWidget);
    expect(find.text('الإيجارات'), findsOneWidget);
    expect(find.text('البيع'), findsOneWidget);
  });
  testWidgets('availability starts empty and confirms only chosen listing IDs', (tester) async {
    final repo = BrokerTestRepository();
    await _pump(tester, const BrokerAvailabilityScreen(initiallyDue: true), repo);
    expect(find.text('التحديثات'), findsOneWidget);
    expect(find.textContaining('أكد إعلانات البيع'), findsNothing);
    expect(find.text('منزل السنينة'), findsNothing);
    final confirm = find.byKey(const ValueKey('broker-availability-confirm'));
    final row = find.byKey(const ValueKey('broker-availability-available-11'));
    expect(tester.widget<AppButton>(confirm).onPressed, isNull);
    expect(tester.widget<AppButton>(row).style, AppButtonStyle.outlined);
    expect(repo.availabilityChanges, isEmpty);

    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.text('تحديث (1)'), findsOneWidget);
    expect(find.text('هل ما زال العقار متوفرًا؟'), findsOneWidget);
    expect(find.text('كل إعلاناتي'), findsNothing);
    expect(tester.widget<AppButton>(row).style, AppButtonStyle.tonal);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(repo.availabilityChanges, hasLength(1));
    expect(repo.availabilityChanges.single.$1, [11]);
    expect(repo.availabilityChanges.single.$2, 'available');
    expect(row, findsNothing);
  });

  testWidgets('updates close only the chosen sale or rental outside the platform', (tester) async {
    final repo = BrokerTestRepository(rentDue: true);
    await _pump(tester, const BrokerAvailabilityScreen(), repo);
    for (final (id, expected) in [(11, 'sold'), (12, 'rented')]) {
      final action = find.byKey(ValueKey('broker-availability-close-$id'));
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('كيف تمت الصفقة؟'), findsOneWidget);
      expect(find.text('مع عميل من التطبيق'), findsOneWidget);
      final before = repo.availabilityChanges.length;
      await tester.tap(find.text('خارج التطبيق'));
      await tester.pumpAndSettle();
      expect(repo.availabilityChanges.length, before + 1);
      expect(repo.availabilityChanges.last.$1, [id]);
      expect(repo.availabilityChanges.last.$2, expected);
      expect(find.text('التحديثات'), findsOneWidget);
    }
    expect(repo.reportedDeals, isEmpty);
  });

  testWidgets('updates can record the advertised price for an app customer', (tester) async {
    final repo = BrokerTestRepository()..dealStatus = 'confirmed';
    await _pump(tester, const BrokerAvailabilityScreen(), repo);
    await tester.tap(find.byKey(const ValueKey('broker-availability-close-11')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مع عميل من التطبيق'));
    await tester.pumpAndSettle();
    expect(find.text('اختر عميل الصفقة'), findsOneWidget);
    await tester.tap(find.text('الصفقة مع هذا العميل'));
    await tester.pumpAndSettle();
    expect(find.text('مبلغ الصفقة'), findsOneWidget);
    expect(repo.reportedDeals, isEmpty);
    expect(tester.widget<AppButton>(find.widgetWithText(AppButton, 'تسجيل الصفقة')).onPressed, isNull);
    await tester.tap(find.text('بنفس السعر المعروض'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تسجيل الصفقة'));
    await tester.pumpAndSettle();
    expect(repo.reportedDeals, [(19, null)]);
    expect(repo.availabilityChanges, isEmpty);
    expect(find.text('التحديثات'), findsOneWidget);
  });

  for (final (amount, action, status) in [
    (90000000.0, 'طلب تأكيد المبلغ', 'pending_customer'),
    (110000000.0, 'تسجيل الصفقة', 'confirmed'),
  ]) {
    testWidgets('updates send manual amount with action $action', (tester) async {
      final repo = BrokerTestRepository()..dealStatus = status;
      await _pump(tester, const BrokerAvailabilityScreen(), repo);
      await tester.tap(find.byKey(const ValueKey('broker-availability-close-11')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('مع عميل من التطبيق'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('الصفقة مع هذا العميل'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إدخال المبلغ'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), amount.toStringAsFixed(0));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppButton, action));
      await tester.pumpAndSettle();
      expect(repo.reportedDeals, [(19, amount)]);
      expect(find.text('التحديثات'), findsOneWidget);
    });
  }

  testWidgets('a customer approves the lower monthly amount explicitly', (tester) async {
    final repo = BrokerTestRepository(viewerId: 2)
      ..priceConfirmationRequired = true
      ..transactionType = 'rent';
    await _pump(tester, const BrokerDealScreen(id: 4), repo, userId: 2);

    expect(find.textContaining('هل توافق على الإيجار الشهري'), findsOneWidget);
    expect(find.text('نعم، تمت الصفقة'), findsNothing);
    await tester.tap(find.text('أوافق على المبلغ'));
    await tester.pumpAndSettle();
    expect(find.text('تأكيد المبلغ'), findsOneWidget);
    expect(repo.decisions, isEmpty);
    await tester.tap(find.text('أؤكد المبلغ'));
    await tester.pumpAndSettle();
    expect(repo.decisions, [(4, true)]);
  });

  testWidgets('customer affirmation is explicit and rating stays locked until confirmed', (tester) async {
    final repo = BrokerTestRepository(viewerId: 2);
    await _pump(tester, const BrokerDealScreen(id: 4), repo, userId: 2);
    expect(find.text('تقييم المعلن'), findsNothing);
    await tester.tap(find.text('نعم، تمت الصفقة')); await tester.pumpAndSettle();
    expect(repo.decisions, isEmpty);
    await tester.tap(find.text('نعم، تمت')); await tester.pumpAndSettle();
    expect(repo.decisions, [(4, true)]);
    expect(repo.seenDeals, isEmpty);
    expect(find.text('تقييم المعلن'), findsOneWidget);
  });
  testWidgets('opening a deal records the displayed advertiser revision once', (tester) async {
    final repo = BrokerTestRepository()..dealViewRevision = 7;
    await _pump(tester, const BrokerDealScreen(id: 4), repo);
    expect(find.text('شقة حدة'), findsOneWidget);
    expect(repo.seenDeals, [(4, 7)]);
    await tester.pump(const Duration(milliseconds: 250));
    expect(repo.seenDeals, [(4, 7)]);
  });
  testWidgets('achievement cards advance after four seconds and support pause', (tester) async {
    await _pump(tester, const BrokerDashboardScreen(), BrokerTestRepository());
    final pages = tester.widget<PageView>(find.descendant(
      of: find.byKey(const ValueKey('broker-achievement-carousel')),
      matching: find.byType(PageView),
    ));
    expect(pages.controller!.page, 0);
    await tester.pump(const Duration(seconds: 3));
    expect(pages.controller!.page, 0);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(pages.controller!.page, 1);
    await tester.tap(find.byKey(const ValueKey('broker-achievement-autoplay')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    expect(pages.controller!.page, 1);
  });
  final screens = <String, Widget>{'dashboard': const BrokerDashboardScreen(), 'customers': const BrokerCustomersScreen(),
    'availability': const BrokerAvailabilityScreen(), 'deals': const BrokerScaffold(appBar: AppAppBar(title: 'نشاطي'), body: BrokerDealsList()), 'finance': const BrokerFinanceScreen(),
    'public-profile': const BrokerPublicProfileScreen(id: 1), 'directory': const BrokerDirectoryScreen(), 'account': const AccountScreen()};
  for (final entry in screens.entries) {
    testWidgets('${entry.key} remains usable at 320 width with large Arabic', (tester) async {
      await _pump(tester, entry.value, BrokerTestRepository(), scale: 2.4, size: const Size(320, 640));
      expect(tester.takeException(), isNull);
      final scrollables = find.byType(Scrollable);
      if (scrollables.evaluate().isNotEmpty) { await tester.drag(scrollables.first, const Offset(0, -380)); await tester.pumpAndSettle(); expect(tester.takeException(), isNull); }
    });
  }
  testWidgets('exports rendered broker screens with synthetic fixtures', (tester) async {
    final old = debugDisableShadows; debugDisableShadows = false;
    try {
      for (final entry in screens.entries) {
        final key = GlobalKey();
        await _pump(tester, entry.value, BrokerTestRepository(), boundary: key);
        await tester.runAsync(() async {
          final render = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final picture = await render.toImage(pixelRatio: 2);
          final data = await picture.toByteData(format: ui.ImageByteFormat.png);
          final file = File('build/broker-preview/${entry.key}.png'); await file.parent.create(recursive: true); await file.writeAsBytes(data!.buffer.asUint8List()); picture.dispose();
        });
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    } finally { debugDisableShadows = old; }
  });
}

import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_repository.dart';
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
  'listings': {'published': 8}, 'customer_activity': {'unread_conversations': 3, 'new_customers_this_week': 4, 'active_viewings': 2, 'completed_deals': 12},
  'needs_attention': {'availability_count': 2, 'correction_listings': [{'id': 3}], 'pending_deal_count': 1},
  'financial_summary': {'listing_creation_blocked': false},
};

class BrokerTestRepository implements BrokerRepository {
  BrokerTestRepository({this.viewerId = 1});
  final int viewerId;
  final availabilityChanges = <(List<int>, String)>[];
  final decisions = <(int, bool)>[];
  String dealStatus = 'pending_customer';
  @override
  Future<Map<String, dynamic>> workspace() async => brokerTestWorkspace();
  @override
  Future<BrokerProfile> profile(int id) async => exampleBroker;
  @override
  Future<BrokerPage<BrokerProfile>> directory({String? governorate, int page = 1, int perPage = 15, bool regionOnly = false, String? search, String? specialty, String? accountType, double? minRating}) async => BrokerPage(items: [exampleBroker], page: 1, lastPage: 1);
  @override
  Future<List<BrokerAvailability>> availability() async => [
    BrokerAvailability(id: 11, title: 'شقة حدة', purpose: 'sale', status: 'available', needsConfirmation: true),
    BrokerAvailability(id: 12, title: 'منزل السنينة', purpose: 'rent', status: 'available', needsConfirmation: false),
  ];
  @override
  Future<void> updateAvailability(List<int> ids, String state) async { availabilityChanges.add((List.of(ids), state)); }
  @override
  Future<BrokerPage<BrokerCustomer>> customers({String? stage, int? propertyId, int page = 1, String? filter}) async => const BrokerPage(items: [
    BrokerCustomer(threadId: 19, customerName: 'عميل تجريبي', propertyId: 11, propertyTitle: 'شقة حدة', stage: 'new'),
  ], page: 1, lastPage: 1);
  @override
  Future<BrokerDeal> deal(int id) async => BrokerDeal(id: id, threadId: 19, propertyId: 11, advertiserId: 1, propertyTitle: 'شقة حدة',
    customerName: 'عميل تجريبي', advertiserName: exampleBroker.name, status: dealStatus, amount: 100000000, currency: 'YER', canConfirm: viewerId == 2 && dealStatus == 'pending_customer', canRate: viewerId == 2 && dealStatus == 'confirmed');
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
class _Properties implements PropertyRepository {
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
    propertyRepositoryProvider.overrideWithValue(_Properties()),
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
  testWidgets('verified broker lands in the marketplace and opens a separate work dashboard', (tester) async {
    await _pump(tester, const AppShellScreen(), BrokerTestRepository());
    final nav = tester.widget<AppNavigationBar>(find.byType(AppNavigationBar));
    expect(nav.destinations.map((d) => d.label), ['الرئيسية', 'عملي', 'العملاء', 'نشاطي', 'حسابي']);
    expect(nav.onCreate, isNull);
    expect(find.text('يحتاج إجراء منك'), findsNothing);
    expect(find.byKey(const ValueKey('home-search')), findsOneWidget);
    nav.onSelected(1); await tester.pumpAndSettle();
    expect(find.text('يحتاج إجراء منك'), findsOneWidget);
  });
  testWidgets('availability update submits selected real listing IDs', (tester) async {
    final repo = BrokerTestRepository();
    await _pump(tester, const BrokerAvailabilityScreen(), repo);
    final button = find.textContaining('ما زالت متوفرة');
    await tester.ensureVisible(button.last); await tester.tap(button.last); await tester.pumpAndSettle();
    expect(repo.availabilityChanges, hasLength(1));
    expect(repo.availabilityChanges.single.$1, [11]);
    expect(repo.availabilityChanges.single.$2, 'available');
  });
  testWidgets('customer affirmation is explicit and rating stays locked until confirmed', (tester) async {
    final repo = BrokerTestRepository(viewerId: 2);
    await _pump(tester, const BrokerDealScreen(id: 4), repo, userId: 2);
    expect(find.text('تقييم المعلن'), findsNothing);
    await tester.tap(find.text('نعم، تمت الصفقة')); await tester.pumpAndSettle();
    expect(repo.decisions, isEmpty);
    await tester.tap(find.text('نعم، تمت')); await tester.pumpAndSettle();
    expect(repo.decisions, [(4, true)]);
    expect(find.text('تقييم المعلن'), findsOneWidget);
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

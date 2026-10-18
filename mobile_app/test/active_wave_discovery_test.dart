import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:real_estate_mobile/core/local/listing_viewer_key_store.dart';
import 'package:real_estate_mobile/core/platform/contact_actions.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/broker/data/broker_repository.dart';
import 'package:real_estate_mobile/features/broker/domain/broker_models.dart';
import 'package:real_estate_mobile/features/broker/presentation/broker_directory.dart';
import 'package:real_estate_mobile/features/discovery/domain/smart_search_filters.dart';
import 'package:real_estate_mobile/features/discovery/presentation/smart_search_assistant.dart';
import 'package:real_estate_mobile/features/map/domain/map_area_geometry.dart';
import 'package:real_estate_mobile/features/properties/data/favorites_repository.dart';
import 'package:real_estate_mobile/features/properties/data/property_market_repository.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/data/saved_search_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/properties/domain/property_sai.dart';
import 'package:real_estate_mobile/features/properties/domain/saved_property_search.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_compare_actions.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_compare_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_details_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_location_preview.dart';
import 'package:real_estate_mobile/features/properties/presentation/saved_search_builder_screen.dart';
import 'broker_experience_ui_test.dart' show BrokerTestAuth, BrokerTestRepository, exampleBroker;
import 'support/wave3_fakes.dart';

// Public synthetic fixtures; none of the rendered previews contain user data.
PropertyDetails _property(int id) => PropertyDetails.fromJson({
  'id': id, 'title': 'شقة في حدة $id', 'type': 'apartment', 'purpose': 'rent',
  'description': 'شقة للإيجار في حدة. تضم ثلاث غرف نوم وحمامين، وتقع في الدور الثاني.',
  'price': 300000, 'monthly_rent': 100000, 'currency': 'YER', 'status': 'published',
  'address': 'صنعاء، حدة', 'latitude': 15.3694, 'longitude': 44.191,
  if (id == 11) ...{'bedrooms': 3, 'bathrooms': 2, 'floor_number': '2', 'has_parking': false},
  'advertiser': {'id': 1, 'name': exampleBroker.name, 'verification_status': 'approved',
    'verification_type': 'broker', 'rating_average': 4.6, 'rating_count': 7},
});

class _Properties extends Wave3PropertiesFake {
  int contacts = 0;
  @override
  Future<PropertyDetails> details(int id) async {
    if (id == 13) throw StateError('Unavailable');
    return _property(id);
  }
  @override
  Future<PropertySaiEnvelope> sai(int id) async => const PropertySaiEnvelope(sai: PropertySai(
    ratePercent: 0, payer: 'customer', payerLabel: 'العميل', calculationBasis: 'fixed',
    displayText: 'السعي 5,000 ريال على المستأجر', amountType: 'fixed', fixedAmount: 5000, currency: 'YER'));
  @override
  Future<void> recordView(int propertyId, String viewerKey) async {}
  @override
  Future<String> contactPhone(int propertyId) async { contacts++; return '+967700000001'; }
}
class _Market implements PropertyMarketRepository {
  @override
  Future<PropertyMarketContext> context(int propertyId) async => const PropertyMarketContext(sufficientData: false, sampleCount: 0);
}
class _Hint extends AssistantHintStore {
  bool seen = false;
  @override
  Future<bool> take() async { if (seen) return false; seen = true; return true; }
}
class _Dialer extends ContactActions {
  final calls = <String>[];
  @override
  Future<bool> openDialer(String phone) async { calls.add(phone); return true; }
}
class _Saved implements SavedSearchRepository {
  Map<String, dynamic>? saved;
  @override
  Future<SavedPropertySearch> create({required String name, required Map<String, dynamic> filters, String alertFrequency = 'instant'}) async {
    saved = Map.of(filters);
    return SavedPropertySearch(id: 7, name: name, filters: filters, alertFrequency: alertFrequency, isActive: true, matchingCount: 0);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
class _Directory extends BrokerTestRepository {
  String? search, specialty, kind;
  double? rating;
  bool strictRegion = false;
  @override
  Future<BrokerPage<BrokerProfile>> directory({String? governorate, int page = 1, int perPage = 15,
    bool regionOnly = false, String? search, String? specialty, String? accountType, double? minRating}) async {
    this.search = search; this.specialty = specialty; kind = accountType; rating = minRating; strictRegion = regionOnly;
    return BrokerPage(items: [exampleBroker], page: 1, lastPage: 1);
  }
}

Future<void> _pump(WidgetTester tester, Widget screen, {double scale = 1, GlobalKey? boundary,
  _Properties? properties, _Saved? saved, _Dialer? dialer, _Directory? directory}) async {
  tester.view.physicalSize = const Size(412, 915); tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(overrides: [
    authControllerProvider.overrideWith(() => BrokerTestAuth(2)),
    propertyRepositoryProvider.overrideWithValue(properties ?? _Properties()),
    propertyMarketRepositoryProvider.overrideWithValue(_Market()),
    brokerRepositoryProvider.overrideWithValue(directory ?? _Directory()),
    assistantHintStoreProvider.overrideWithValue(_Hint()),
    favoritePropertyIdsProvider.overrideWith((ref) async => <int>{}),
    listingViewerKeyProvider.overrideWith((ref) async => 'synthetic-viewer-key-for-active-wave'),
    propertyMapPreviewBuilderProvider.overrideWithValue((context, lat, lon) => ColoredBox(color: Colors.teal.shade50,
      child: Center(child: Text('موقع الإعلان $lat, $lon')))),
    if (saved != null) savedSearchRepositoryProvider.overrideWithValue(saved),
    if (dialer != null) contactActionsProvider.overrideWithValue(dialer),
  ], child: MaterialApp(theme: AppTheme.light,
    builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true),
      child: RepaintBoundary(key: boundary, child: child!)), home: screen)));
  await tester.pumpAndSettle();
}
Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/broker-preview/active-wave-$name.png');
    await file.parent.create(recursive: true); await file.writeAsBytes(bytes!.buffer.asUint8List()); image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('NotoSansArabic')..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'))).load();
    await (FontLoader('sans-serif')..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'))).load();
    final primary = FontLoader('PrimaryFont');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) { primary.addFont(rootBundle.load('assets/ebroker/fonts/Manrope-$weight.ttf')); }
    await primary.load();
    final icons = await File('${Platform.environment['FLUTTER_ROOT']!}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytes();
    await (FontLoader('MaterialIcons')..addFont(Future.value(icons.buffer.asByteData()))).load();
  });
  test('map polygon survives saving with exact monthly currency and false filters', () {
    final area = MapAreaGeometry.fromPoints(const [LatLng(15,44), LatLng(15,45), LatLng(16,44)]);
    final filters = {'type':'apartment', 'purpose':'rent', 'currency':'USD', 'min_monthly_rent':100, 'max_monthly_rent':400,
      'has_parking':0, 'floor_number':'2', 'area_polygon':area.encodedRing, 'latitude':15.3, 'longitude':44.3, 'radius_km':30,
      'south':15, 'west':44, 'north':16, 'east':45, 'advertiser_id':25};
    final smart = SmartSearchFilters.fromApiFilters(filters);
    expect(smart.apiFilters, filters);
    final restored = MapAreaGeometry.fromEncodedRing(smart.values['area_polygon'] as String);
    expect(restored.contains(15.2,44.2), isTrue);
    expect(restored.contains(15.8,44.8), isFalse); // In the bounds, outside the selected triangle.
    expect(restored.contains(15.5,44.5), isTrue); // Boundary agrees with ST_Covers.
    expect(smart.without('map_area').hasMapArea, isFalse);
    expect(smart.without('map_area').apiFilters['has_parking'], 0);
  });
  test('comparison selection caps at four unique public IDs', () {
    final selection = PropertyCompareSelection(); addTearDown(selection.dispose);
    for (final id in [11,12,13,14]) { expect(selection.toggle(id), isTrue); }
    expect(selection.toggle(15), isFalse); expect(selection.state.length,4);
    expect(selection.toggle(12), isTrue); expect(selection.toggle(15), isTrue);
    expect(selection.state, {11,13,14,15}); expect(selection.toggle(0), isFalse);
  });
  testWidgets('assistant stays on physical left and dismisses its hint', (tester) async {
    int taps = 0;
    await _pump(tester, Directionality(textDirection: TextDirection.rtl, child: Scaffold(body:
      SmartSearchAssistantLayer(onPressed: () => taps++, child: const Center(child: Text('تصفح العقارات'))))));
    expect(tester.getTopLeft(find.byKey(const ValueKey('floating-smart-search'))).dx,16);
    expect(find.text('جرّب البحث الذكي'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('assistant-hint-close'))); await tester.pump();
    expect(find.text('جرّب البحث الذكي'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('floating-smart-search'))); expect(taps,1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final scale in [1.0,2.4]) {
    testWidgets('comparison keeps missing facts and unavailable columns honest at scale $scale', (tester) async {
      final key = GlobalKey();
      await _pump(tester, const PropertyCompareScreen(propertyIds: [11,12,13]), scale: scale, boundary:key);
      expect(find.text('العقار غير متاح حاليًا'), findsOneWidget);
      await _capture(tester,key,'compare-$scale');
      await tester.scrollUntilVisible(find.byKey(const ValueKey('compare-all')),300,scrollable:find.byType(Scrollable).first);
      await tester.pumpAndSettle();await tester.tap(find.byKey(const ValueKey('compare-all')));await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('compare-all'))).selected,isTrue);
      await tester.scrollUntilVisible(find.text('غرف النوم'),300,scrollable:find.byType(Scrollable).first);await tester.pumpAndSettle();
      expect(find.text('غير مذكور'), findsWidgets);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('0 غرف'), findsNothing);
      expect(tester.takeException(),isNull);
    });
    testWidgets('details shows ordered facts, compact advertiser and explicit contact at scale $scale', (tester) async {
      final key = GlobalKey(), properties = _Properties(), dialer = _Dialer();
      await _pump(tester,const PropertyDetailsScreen(propertyId:11),scale:scale,boundary:key,properties:properties,dialer:dialer);
      expect(properties.contacts,0); expect(dialer.calls,isEmpty);
      expect(find.byKey(const ValueKey('floating-smart-search')),findsNothing);
      await _capture(tester,key,'details-$scale');
      await tester.tap(find.byKey(const ValueKey('property-call'))); await tester.pumpAndSettle();
      expect(properties.contacts,1); expect(dialer.calls,['+967700000001']);
      await tester.scrollUntilVisible(find.text('المعلن'),350,scrollable:find.byType(Scrollable).first); await tester.pumpAndSettle();
      await _capture(tester,key,'advertiser-$scale');
      expect(find.text(exampleBroker.name),findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('property-open-map')),350,scrollable:find.byType(Scrollable).first);
      expect(find.textContaining('موقع الإعلان'),findsOneWidget);
      expect(tester.takeException(),isNull);
    });
    testWidgets('saved AI and map filters are visible and sent unchanged at scale $scale', (tester) async {
      final saved = _Saved(), key=GlobalKey();
      const filters = {'purpose':'rent','type':'apartment','currency':'USD','max_monthly_rent':400,'has_parking':0,
        'floor_number':'2','south':15,'west':44,'north':16,'east':45};
      await _pump(tester,const SavedSearchBuilderScreen(initialFilters:filters,fixedFilters:true),scale:scale,boundary:key,saved:saved);
      expect(find.text('بدون موقف'),findsOneWidget); expect(find.text('نطاق محدد على الخريطة'),findsOneWidget);
      await _capture(tester,key,'save-$scale');
      await tester.scrollUntilVisible(find.text('حفظ البحث'),300,scrollable:find.byType(Scrollable).first);
      await tester.tap(find.text('حفظ البحث')); await tester.pumpAndSettle();
      expect(saved.saved,filters); expect(tester.takeException(),isNull);
    });
    testWidgets('directory sends selected public filters at scale $scale', (tester) async {
      final directory=_Directory(), key=GlobalKey();
      await _pump(tester,const BrokerDirectoryScreen(),scale:scale,boundary:key,directory:directory);
      await tester.enterText(find.byKey(const ValueKey('broker-directory-search')),'مكتب حدة');
      await tester.tap(find.text('مكاتب')); await tester.pumpAndSettle();
      expect(directory.kind,'office'); expect(directory.search,'مكتب حدة'); expect(directory.strictRegion,isTrue);
      await _capture(tester,key,'directory-$scale');
      expect(tester.takeException(),isNull);
    });
  }
}

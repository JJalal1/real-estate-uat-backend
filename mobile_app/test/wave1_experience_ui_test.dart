import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:real_estate_mobile/core/local/listing_recovery_store.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/discovery/data/discovery_location.dart';
import 'package:real_estate_mobile/features/discovery/data/discovery_suggestions.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_repository.dart';
import 'package:real_estate_mobile/features/discovery/domain/smart_search_filters.dart';
import 'package:real_estate_mobile/features/map/presentation/map_screen.dart';
import 'package:real_estate_mobile/features/map/presentation/property_map_results_sheet.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_details_screen.dart';
import 'package:real_estate_mobile/features/properties/data/listing_account_draft_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/listing_account_draft.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/properties/domain/property_marker.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_details_sheet.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_draft_entry_screen.dart';
import 'package:real_estate_mobile/router/app_router.dart';
import 'support/owner_ux_fixtures.dart';
import 'support/wave6_fakes.dart';
import 'wave6_product_ui_test.dart' show editorSnapshot;

class _LocationStore extends DiscoveryLocationStore {
  DiscoveryLocationPreferences saved = const DiscoveryLocationPreferences();
  @override
  Future<DiscoveryLocationPreferences> load() async => saved;
  @override
  Future<void> save(DiscoveryLocationPreferences preferences) async { saved = preferences; }
}
class _LocationAccess extends DiscoveryLocationAccess {
  int checks = 0, requests = 0;
  final fix = Completer<HomeLocation>();
  @override
  Future<LocationPermission> permission() async { checks++; return LocationPermission.whileInUse; }
  @override
  Future<LocationPermission> requestPermission() async { requests++; return LocationPermission.whileInUse; }
  @override
  Future<HomeLocation> locate() => fix.future;
}
class _DelayedDrafts extends Wave6Drafts {
  int gets = 0;
  final pending = Completer<ListingAccountDraft>();
  @override
  Future<ListingAccountDraft> get(String key) { gets++; return pending.future; }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() { WidgetController.hitTestWarningShouldBeFatal = true; });
  tearDownAll(() { WidgetController.hitTestWarningShouldBeFatal = false; });
  setUpAll(loadUxFixtures);

  test('location introduction is passive, manual wins a late fix, and restart restores only a public city center', () async {
    final store = _LocationStore(), access = _LocationAccess();
    var state = const HomeLocation();
    DiscoveryLocationCoordinator coordinator() => DiscoveryLocationCoordinator(store, access, () => state, (next) => state = next);
    final first = coordinator(); await first.initialize();
    expect(access.checks, 0); expect(access.requests, 0); expect(first.shouldOfferChoice, isTrue);
    await first.markIntroductionShown();
    final pending = first.useDevice();
    await Future<void>.delayed(Duration.zero);
    const manual = HomeLocation(latitude: 14, longitude: 44, governorate: 'إب', label: 'إب', manual: true);
    await first.selectManual(manual);
    access.fix.complete(const HomeLocation(latitude: 13.123456, longitude: 44.654321, device: true));
    await pending; expect(state, same(manual)); expect(store.saved.manual, same(manual));
    state = const HomeLocation(); await coordinator().initialize();
    expect(state.governorate, 'إب'); expect(state.manual, isTrue); expect(access.requests, 0);

    final secondStore = _LocationStore(), secondAccess = _LocationAccess();
    var secondState = const HomeLocation();
    final second = DiscoveryLocationCoordinator(secondStore, secondAccess, () => secondState, (next) => secondState = next);
    await second.initialize();
    final device = second.useDevice();
    secondAccess.fix.complete(const HomeLocation(latitude: 13.123456, longitude: 44.654321, device: true));
    await device;
    await second.rememberPublicRegion('إب', const [manual]);
    expect(secondStore.saved.manual, isNull);
    expect(secondStore.saved.lastPublicRegion!.latitude, 14);
    expect(secondStore.saved.lastPublicRegion!.longitude, 44);
    expect(secondStore.saved.lastPublicRegion!.device, isFalse);
    secondState = const HomeLocation();
    final restarted = DiscoveryLocationCoordinator(secondStore, secondAccess, () => secondState, (next) => secondState = next);
    await restarted.initialize();
    expect(secondState.governorate, 'إب'); expect(secondState.latitude, 14);
    expect(restarted.shouldOfferChoice, isFalse); expect(secondAccess.checks, 1);
  });

  for (final keyboard in [true, false]) {
    testWidgets('typed suggestions submit exactly once by ${keyboard ? 'IME' : 'icon'} without clearing literal text', (tester) async {
      DiscoverySearchChoice? result;
      var submissions = 0;
      final scope = uxContainer(extra: [discoverySuggestionsProvider.overrideWith((ref, text) async => [
        if (text.contains('حدة')) const DiscoverySuggestion(label: 'حدة', kind: 'حي / منطقة'),
      ])]);
      await pumpUx(tester, scope, Builder(builder: (context) => Scaffold(body: TextButton(onPressed: () async {
        final choice = await showModalBottomSheet<DiscoverySearchChoice>(context: context, isScrollControlled: true,
          builder: (_) => const DiscoverySearchSheet(initialValue: 'صنعاء'));
        if (choice != null) { result = choice; submissions++; }
      }, child: const Text('افتح البحث')))));
      await tester.tap(find.text('افتح البحث')); await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('discovery-search-input'));
      expect(tester.widget<TextField>(field).controller!.text, 'صنعاء');
      await tester.enterText(field, 'منزل في حدة'); await uxFrames(tester);
      expect(find.text('حدة'), findsOneWidget);
      expect(find.text('حي / منطقة'), findsOneWidget);
      expect(tester.widget<TextField>(field).controller!.text, 'منزل في حدة');
      if (keyboard) { await tester.testTextInput.receiveAction(TextInputAction.search); }
      else { await tester.tap(find.byKey(const ValueKey('discovery-search-submit'))); }
      await tester.pumpAndSettle();
      expect(submissions, 1); expect(result!.text, 'منزل في حدة'); expect(result!.suggestion, isNull);
      expect(find.byKey(const ValueKey('discovery-search-input')), findsNothing);
      expect(tester.takeException(), isNull); await closeUx(tester);
    });
  }

  testWidgets('details expands, collapses and system back returns the original list offset', (tester) async {
    final homeScroll = ScrollController(); addTearDown(homeScroll.dispose);
    final details = PropertyDetails.fromJson({'id': 11, 'title': 'منزل اختبار حركة الإعلان', 'type': 'house',
      'purpose': 'sale', 'price': 10000000, 'currency': 'YER', 'status': 'published', 'availability_status': 'available',
      'description': List.filled(20, 'وصف العقار للاختبار.').join(' '),
      'images': [for (var image = 1; image <= 2; image++) {'id': image,
        'url': 'https://real-estate-uat-api-frankfurt.onrender.com/api/property-media/$image?v=synthetic-wave1',
        'is_primary': image == 1, 'sort_order': image - 1}],
      'advertiser': {'id': 2, 'name': 'معلن اختبار', 'account_type': 'broker', 'verification_status': 'approved'}});
    final scope = uxContainer(extra: [propertyDetailsProvider.overrideWith((ref, id) async => details)]);
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, _) => Scaffold(appBar: AppBar(actions: [TextButton(
        key: const ValueKey('open-details'), onPressed: () => context.push('/properties/11'), child: const Text('افتح الإعلان'))]),
        body: ListView.builder(controller: homeScroll, itemCount: 100, itemBuilder: (_, index) => ListTile(title: Text('عقار $index'))))),
      GoRoute(path: '/properties/:id', pageBuilder: (_, state) => PropertyDetailsSheetPage(propertyId: 11, key: state.pageKey)),
    ]); addTearDown(router.dispose);
    final boundary = GlobalKey();
    await pumpUx(tester, scope, const SizedBox.shrink(), router: router, boundary: boundary);
    homeScroll.jumpTo(400); await tester.pump(); final before = homeScroll.offset;
    await tester.tap(find.byKey(const ValueKey('open-details'))); await tester.pumpAndSettle();
    final draggable = tester.widget<DraggableScrollableSheet>(find.byKey(const ValueKey('property-details-sheet')));
    expect(draggable.controller!.size, closeTo(.72, .02));
    expect(find.text('منزل اختبار حركة الإعلان'), findsOneWidget);
    await uxPreview(tester, boundary, 'wave1-details-partial');
    final gallery = find.byType(PageView).first;
    await tester.drag(gallery, const Offset(300, 0)); await uxFrames(tester);
    final galleryPosition = tester.state<ScrollableState>(find.descendant(of: gallery, matching: find.byType(Scrollable)).first).position;
    expect(galleryPosition.pixels, greaterThan(galleryPosition.viewportDimension * .8));
    expect(draggable.controller!.size, closeTo(.72, .02));
    await uxPreview(tester, boundary, 'wave1-details-gallery-swipe');
    await tester.drag(find.byKey(const ValueKey('property-details-handle')), const Offset(0, -650));
    await tester.pumpAndSettle(); expect(draggable.controller!.size, greaterThan(.95));
    final verification = find.text('التوثيق والتقييم');
    await tester.scrollUntilVisible(verification, 300, scrollable: find.descendant(
      of: find.byKey(const ValueKey('property-details-11')), matching: find.byType(Scrollable)).first);
    await tester.ensureVisible(verification); await tester.pumpAndSettle();
    await tester.tap(verification); await tester.pumpAndSettle();
    expect(tester.takeException(), isNull); // ExpansionTile state must not read a numeric scroll offset.
    final list = tester.widget<ListView>(find.byKey(const ValueKey('property-details-11')));
    list.controller!.jumpTo(0); await tester.pumpAndSettle();
    await tester.drag(find.byKey(const ValueKey('property-details-handle')), const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(draggable.controller!.size, lessThan(.95)); expect(draggable.controller!.size, greaterThan(.38));
    await tester.binding.handlePopRoute(); await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('property-details-sheet')), findsNothing); expect(homeScroll.offset, before);
    expect(tester.takeException(), isNull); await closeUx(tester);
  });

  testWidgets('A05 A07 explicit My Drafts preserves its source, all saved work, deduplicated resume and actor fence', (tester) async {
    final old = _DelayedDrafts(), next = Wave6Drafts(), auth = UxAuth(uxUser(type: 'broker'));
    final firstKey = newListingDraftKey(), secondKey = newListingDraftKey();
    old.drafts[firstKey] = ListingAccountDraft(key: firstKey, revision: 2, payload: editorSnapshot(), title: 'مسودة سابقة', progress: 40);
    old.drafts[secondKey] = ListingAccountDraft(key: secondKey, revision: 3, payload: editorSnapshot(), title: 'المسودة الأخيرة', progress: 60);
    final scope = uxContainer(auth: auth, extra: [
      listingAccountDraftRepositoryProvider.overrideWith((ref) => ref.watch(authControllerProvider).asData?.value?.id == 1 ? old : next),
      listingRecoveryStoreProvider.overrideWithValue(Wave6Recovery()),
    ]);
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, _) => Scaffold(body: Center(child: TextButton(
        onPressed: () => context.push('/add-property'), child: const Text('سياق البحث الأصلي'))))),
      GoRoute(path: '/add-property', pageBuilder: (_, state) => CustomTransitionPage<void>(key: state.pageKey,
        opaque: false, barrierColor: Colors.black38,
        transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
        child: const ListingDraftEntryScreen(showSavedDrafts: true))),
    ]); addTearDown(router.dispose);
    final boundary = GlobalKey();
    await pumpUx(tester, scope, const SizedBox.shrink(), router: router, boundary: boundary);
    await tester.tap(find.text('سياق البحث الأصلي')); await tester.pumpAndSettle();
    expect(find.text('المسودة الأخيرة'), findsOneWidget); expect(find.text('مسودة سابقة'), findsOneWidget);
    expect(find.byKey(const ValueKey('listing-recovery-choice')), findsNothing);
    expect(find.text('سياق البحث الأصلي'), findsOneWidget);
    await uxPreview(tester, boundary, 'wave1-draft-choice');
    await tester.tap(find.byType(BackButton)); await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('listing-draft-choice')), findsNothing); expect(old.drafts, hasLength(2));
    await tester.tap(find.text('سياق البحث الأصلي')); await tester.pumpAndSettle();
    final resume = find.text('المسودة الأخيرة');
    await tester.tap(resume); await tester.tap(resume); await tester.pump(); expect(old.gets, 1);
    auth.change(uxUser(id: 2, type: 'broker')); await uxFrames(tester);
    old.pending.complete(old.drafts[secondKey]!); await uxFrames(tester);
    expect(find.text('المسودة الأخيرة'), findsNothing); expect(find.text('مسودة سابقة'), findsNothing);
    expect(old.drafts, hasLength(2)); expect(old.saves, isEmpty);
    expect(tester.takeException(), isNull); await closeUx(tester);
  });

  testWidgets('a directly opened property link can drag closed to Home with the actual router', (tester) async {
    final scope = uxContainer(extra: [propertyDetailsProvider.overrideWith((ref, id) async => PropertyDetails.fromJson({
      'id': id, 'title': 'عقار اختبار الرابط', 'type': 'house', 'purpose': 'sale', 'price': 10000000,
      'currency': 'YER', 'status': 'published', 'availability_status': 'available'}))]);
    await scope.read(authControllerProvider.future);
    final router = scope.read(appRouterProvider); addTearDown(router.dispose);
    router.go('/properties/11');
    await pumpUx(tester, scope, const SizedBox.shrink(), router: router);
    await tester.pumpAndSettle(); expect(router.canPop(), isTrue);
    await tester.drag(find.byKey(const ValueKey('property-details-handle')), const Offset(0, 600));
    await uxFrames(tester); await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.byKey(const ValueKey('property-details-sheet')), findsNothing);
    expect(tester.takeException(), isNull); await closeUx(tester);
  });

  testWidgets('ordinary map and full list roundtrip keeps the same canvas, typed query and result request', (tester) async {
    var requests = 0;
    const row = PropertyMarker(id: 11, title: 'شقة اختبار حدة', price: 10000000, currency: 'YER',
      latitude: 15.36, longitude: 44.19, distanceKm: 0, type: 'apartment', purpose: 'sale');
    const floor = PropertyMarker(id: 12, title: 'دور كامل حدة', price: 20000000, currency: 'YER',
      latitude: 15.36, longitude: 44.19, distanceKm: 0, type: 'floor', purpose: 'sale');
    var shown = <int>[];
    final scope = uxContainer(extra: [
      nearbyPropertiesProvider.overrideWith((ref, query) async { requests++; return const [row, floor]; }),
      sharedSearchMapBuilderProvider.overrideWithValue((context, rows, select, viewport) {
        shown = rows.map((row) => row.id).toList();
        return const ColoredBox(key: ValueKey('ordinary-native-canvas'), color: Colors.teal);
      }),
    ]);
    await pumpUx(tester, scope, MapScreen(initialFilters: SmartSearchFilters.fromMap({'search': 'حدة', 'type': 'apartment'})));
    await tester.pumpAndSettle();
    expect(shown, [11, 12]);
    final element = tester.element(find.byKey(const ValueKey('ordinary-native-canvas')));
    final query = tester.widget<TextField>(find.byType(TextField).first).controller!.text;
    await tester.tap(find.byTooltip('عرض القائمة')); await tester.pumpAndSettle();
    expect(find.text('قائمة العقارات'), findsOneWidget);
    expect(find.byKey(const ValueKey('ordinary-native-canvas')), findsNothing);
    expect(find.byKey(const ValueKey('ordinary-native-canvas'), skipOffstage: false), findsOneWidget);
    await tester.tap(find.text('خريطة')); await tester.pumpAndSettle();
    expect(tester.element(find.byKey(const ValueKey('ordinary-native-canvas'))), same(element));
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, query);
    expect(query, 'حدة'); expect(requests, 1);
    expect(tester.takeException(), isNull); await closeUx(tester);
  });

  for (final dark in [false, true]) {
    testWidgets('map sheet drag and selection preserve the canvas at small RTL scale 2.4 theme $dark', (tester) async {
      final rows = List.generate(5, (index) => PropertyMarker(id: index + 1, title: 'عقار اختبار ${index + 1}',
        price: 999999999999, currency: 'YER', latitude: 15.36, longitude: 44.19, distanceKm: 0,
        purpose: index.isEven ? 'sale' : 'rent', type: 'house', address: 'إب، منطقة الاختبار'));
      int? selected; var canvasBuilds = 0;
      final boundary = GlobalKey(), scope = uxContainer();
      await pumpUx(tester, scope, StatefulBuilder(builder: (context, update) => Scaffold(body: Stack(children: [
        Positioned.fill(child: Builder(builder: (_) { canvasBuilds++; return ColoredBox(key: const ValueKey('persistent-map'),
          color: Colors.teal.shade50, child: Align(alignment: Alignment.topCenter, child: TextButton(
            key: const ValueKey('select-marker'), onPressed: () => update(() => selected = 5), child: const Text('علامة الاختبار')))); })),
        PropertyMapResultsSheet(items: rows, selectedId: selected, itemBuilder: (row) => PropertyMapResultCard(
          property: row, favorite: false, onFavorite: () {}, onMap: () => update(() => selected = row.id), onDetails: () {})),
      ]))), size: const Size(320, 568), scale: 2.4, dark: dark, boundary: boundary);
      final canvasElement = tester.element(find.byKey(const ValueKey('persistent-map')));
      await tester.tap(find.byKey(const ValueKey('select-marker'))); await tester.pumpAndSettle();
      final sheet = tester.widget<DraggableScrollableSheet>(find.byKey(const ValueKey('map-results-sheet')));
      expect(sheet.controller!.size, closeTo(.5, .02));
      await tester.drag(find.byKey(const ValueKey('map-results-handle')), const Offset(0, -300));
      await tester.pumpAndSettle(); expect(sheet.controller!.size, greaterThan(.75));
      expect(tester.element(find.byKey(const ValueKey('persistent-map'))), same(canvasElement)); expect(canvasBuilds, 2);
      final list = tester.widget<ListView>(find.byKey(const ValueKey('map-results-list')));
      expect(list.controller!.hasClients, isTrue);
      expect(find.byKey(const ValueKey('map-result-5')), findsOneWidget);
      await uxPreview(tester, boundary, 'wave1-map-sheet-${dark ? 'dark' : 'light'}-2.4');
      expect(tester.takeException(), isNull); await closeUx(tester);
    });
  }
}

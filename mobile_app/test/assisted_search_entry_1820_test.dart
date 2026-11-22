import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:real_estate_mobile/core/platform/voice_input.dart';
import 'package:real_estate_mobile/features/discovery/data/ai_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_search_session.dart';
import 'package:real_estate_mobile/features/discovery/data/smart_search_session.dart';
import 'package:real_estate_mobile/features/discovery/domain/smart_search_filters.dart';
import 'package:real_estate_mobile/features/discovery/presentation/home_ai_search_entry.dart';
import 'package:real_estate_mobile/features/discovery/presentation/marketplace_search_panel.dart';
import 'package:real_estate_mobile/features/map/presentation/map_screen.dart';
import 'package:real_estate_mobile/features/map/presentation/property_map_results_sheet.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/saved_property_search.dart';
import 'package:real_estate_mobile/features/properties/presentation/saved_searches_screen.dart';
import 'package:real_estate_mobile/router/app_router.dart';

import 'support/owner_ux_fixtures.dart';
import 'support/wave3_fakes.dart';

const _dhamar = HomeLocation(latitude: 14.55, longitude: 44.4, governorate: 'ذمار', governorateCode: 'YE-DH', label: 'ذمار', manual: true);
const _taiz = HomeLocation(latitude: 13.58, longitude: 44.02, governorate: 'تعز', governorateCode: 'YE-TA', label: 'تعز', manual: true);
const _description = ValueKey('smart-search-description');

void main() {
  setUpAll(loadUxFixtures);

  testWidgets('verified broker opens the saved polygon through the assistant menu', (tester) async {
    const filters = {'purpose': 'rent', 'governorate_code': 'DHAMAR',
      'area_polygon': '[[44.399,14.551],[44.4,14.551],[44.4,14.553],[44.399,14.553],[44.399,14.551]]'};
    const saved = SavedPropertySearch(id: 1822, name: 'UAT1822 11-on', filters: filters,
      alertFrequency: 'off', isActive: true, matchingCount: 1);
    final properties = Wave3PropertiesFake();
    final scope = uxContainer(user: uxUser(id: 28, type: 'broker'), extra: [
      propertyRepositoryProvider.overrideWithValue(properties),
      sharedSearchMapBuilderProvider.overrideWithValue((context, rows, select, viewport) => const ColoredBox(color: Colors.teal)),
    ]);
    final production = scope.read(appRouterProvider);
    addTearDown(production.dispose);
    final aiRoute = production.configuration.routes.whereType<GoRoute>().firstWhere((route) => route.path == '/smart-search');
    final navigation = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const SavedSearchResultsScreen(search: saved)),
      GoRoute(path: '/smart-search', builder: aiRoute.builder),
    ]);
    addTearDown(navigation.dispose);
    await pumpUx(tester, scope, const SizedBox(), router: navigation);
    await tester.tap(find.byKey(const ValueKey('floating-smart-search')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('بحث عن عقار بالذكاء'));
    await tester.pumpAndSettle();
    expect(scope.read(smartSearchSessionProvider).filters.values, filters);
    expect(properties.queries.single.filters, filters);
    await tester.ensureVisible(find.byKey(const ValueKey('smart-search-map')));
    await tester.tap(find.byKey(const ValueKey('smart-search-map')));
    await tester.pumpAndSettle();
    expect(find.byType(MapScreen), findsOneWidget);
    expect(scope.read(smartSearchSessionProvider).filters.values, filters);
    expect(properties.queries, hasLength(1));
    expect(tester.takeException(), isNull);
    await closeUx(tester);
  });

  testWidgets('wide Home AI entry uses the production route without old Home or AI criteria and preserves typed city', (tester) async {
    final properties = Wave3PropertiesFake(), ai = Wave3AiFake(), voice = Wave3VoiceFake();
    addTearDown(voice.dispose);
    final scope = uxContainer(extra: [
      propertyRepositoryProvider.overrideWithValue(properties), aiRepositoryProvider.overrideWithValue(ai),
      voiceInputProvider.overrideWithValue(voice),
      homeLocationProvider.overrideWith((ref) => _dhamar),
      homeLocationsProvider.overrideWith((ref) async => const [_dhamar, _taiz]),
    ]);
    final home = scope.read(marketplaceSearchControllerProvider.notifier);
    home.edit('بحث Home القديم');
    home.applyFilters(SmartSearchFilters.fromMap({'type': 'villa', 'purpose': 'sale', 'max_price': 90000000}));
    await tester.pump();
    final parent = scope.read(homeSearchResultsProvider);
    await scope.read(smartSearchSessionProvider.notifier).replaceManually(
      SmartSearchFilters.fromMap({'search': 'بحث AI القديم', 'purpose': 'rent', 'min_bedrooms': 9}));

    // Reuse the production route builder, while keeping unrelated shell pages
    // outside this focused owner-boundary fixture.
    final production = scope.read(appRouterProvider);
    addTearDown(production.dispose);
    final aiRoute = production.configuration.routes.whereType<GoRoute>().firstWhere((route) => route.path == '/smart-search');
    final navigation = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Center(
        child: HomeAiSearchEntry(wide: true, location: 'صنعاء', purpose: 'sale', type: 'villa')))),
      GoRoute(path: '/smart-search', builder: aiRoute.builder),
    ]);
    addTearDown(navigation.dispose);
    await pumpUx(tester, scope, const SizedBox(), router: navigation);
    await tester.tap(find.byKey(const ValueKey('home-smart-search')));
    await tester.pumpAndSettle();
    final field = find.byKey(_description);
    expect(scope.read(smartSearchSessionProvider).filters.values, {'governorate': 'ذمار', 'governorate_code': 'YE-DH'});
    expect(scope.read(smartSearchSessionProvider).started, isFalse);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(tester.widget<TextField>(field).decoration!.hintText, contains('ذمار'));
    expect(find.text('أرض في ذمار'), findsOneWidget);
    expect(identical(scope.read(homeSearchResultsProvider), parent), isTrue);
    await tester.enterText(field, 'أريد شقة في عدن');
    scope.read(homeLocationProvider.notifier).state = _taiz;
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, 'أريد شقة في عدن');
    expect(tester.widget<TextField>(field).decoration!.hintText, contains('تعز'));
    expect(ai.requests, isEmpty);
    navigation.pop();
    await tester.pumpAndSettle();
    expect(scope.read(marketplaceSearchControllerProvider).draftQuery, 'بحث Home القديم');
    expect(scope.read(marketplaceSearchControllerProvider).criteria.values['type'], 'villa');
    expect(identical(scope.read(homeSearchResultsProvider), parent), isTrue);
    await tester.tap(find.byKey(const ValueKey('home-smart-search')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(scope.read(smartSearchSessionProvider).filters.values, {'governorate': 'تعز', 'governorate_code': 'YE-TA'});
    expect(tester.takeException(), isNull);
    await closeUx(tester);
  });

  testWidgets('explicit map AI copy survives its own map and details then discards changes on parent return', (tester) async {
    final properties = Wave3PropertiesFake(), ai = Wave3AiFake(), voice = Wave3VoiceFake();
    ai.onRefine = (_, filters, revision) async => {'revision': revision, 'filters': {
      ...filters, 'search': 'تعز', 'governorate': 'تعز', 'governorate_code': 'YE-TA', 'max_price': 100000,
    }};
    addTearDown(voice.dispose);
    final scope = uxContainer(extra: [
      propertyRepositoryProvider.overrideWithValue(properties), aiRepositoryProvider.overrideWithValue(ai),
      voiceInputProvider.overrideWithValue(voice), homeLocationProvider.overrideWith((ref) => _dhamar),
      homeLocationsProvider.overrideWith((ref) async => const [_dhamar, _taiz]),
      sharedSearchMapBuilderProvider.overrideWithValue((context, rows, select, viewport) => const ColoredBox(color: Colors.teal)),
    ]);
    final parent = scope.read(marketplaceSearchControllerProvider.notifier);
    parent.edit('ذمار'); await parent.submit();
    final mapToken = parent.enterMap();
    parent.setChoice('purpose', 'rent', onMap: true);
    await tester.pump();
    final homeBefore = scope.read(homeSearchResultsProvider), mapBefore = scope.read(marketplaceMapResultsProvider);
    final production = scope.read(appRouterProvider);
    addTearDown(production.dispose);
    final aiRoute = production.configuration.routes.whereType<GoRoute>().firstWhere((route) => route.path == '/smart-search');
    final navigation = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, __) => Scaffold(body: TextButton(key: const ValueKey('open-map-ai'),
        onPressed: () => context.push('/smart-search', extra: SmartSearchFilters.fromMap(Map<String, dynamic>.from(mapBefore.filters.values))),
        child: const Text('بحث ذكي')))),
      GoRoute(path: '/smart-search', builder: aiRoute.builder),
      GoRoute(path: '/properties/:id', builder: (_, __) => const Scaffold(body: Text('تفاصيل الاختبار'))),
    ]);
    addTearDown(navigation.dispose);
    await pumpUx(tester, scope, const SizedBox(), router: navigation);
    await tester.tap(find.byKey(const ValueKey('open-map-ai'))); await tester.pumpAndSettle();
    expect(scope.read(smartSearchSessionProvider).filters.sameAs(mapBefore.filters), isTrue);
    final field = find.byKey(_description);
    await tester.enterText(field, 'ابحث في تعز وخفض السعر');
    await tester.ensureVisible(find.byKey(const ValueKey('smart-search-send')));
    await tester.tap(find.byKey(const ValueKey('smart-search-send'))); await tester.pumpAndSettle();
    final accepted = scope.read(smartSearchSessionProvider);
    expect(accepted.filters.values['max_price'], 100000);
    await tester.ensureVisible(find.byKey(const ValueKey('smart-search-map')));
    await tester.tap(find.byKey(const ValueKey('smart-search-map'))); await tester.pumpAndSettle();
    expect(tester.widget<MapScreen>(find.byType(MapScreen)).cameraCenterHint!.latitude, closeTo(13.58, 1e-9));
    expect(tester.widget<MapScreen>(find.byType(MapScreen)).cameraCenterHint!.longitude, closeTo(44.02, 1e-9));
    await tester.tap(find.byKey(const ValueKey('map-open-search'))); await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('smart-search-list')), findsOneWidget);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    await tester.tap(find.byKey(const ValueKey('smart-search-list'))); await tester.pumpAndSettle();
    final withinJourney = scope.read(smartSearchSessionProvider);
    expect(withinJourney.filters.sameAs(accepted.filters), isTrue);
    expect(withinJourney.rows.map((row) => row.id), accepted.rows.map((row) => row.id));
    expect(withinJourney.revision, accepted.revision);
    await tester.ensureVisible(find.byKey(const ValueKey('smart-search-result-11')));
    await tester.tap(find.byKey(const ValueKey('smart-search-result-11'))); await tester.pumpAndSettle();
    expect(find.text('تفاصيل الاختبار'), findsOneWidget);
    navigation.pop(); await tester.pumpAndSettle();
    expect(identical(scope.read(smartSearchSessionProvider), withinJourney), isTrue);
    navigation.pop(); await tester.pumpAndSettle();
    expect(parent.isMapJourneyCurrent(mapToken), isTrue);
    expect(identical(scope.read(marketplaceMapResultsProvider), mapBefore), isTrue);
    expect(identical(scope.read(homeSearchResultsProvider), homeBefore), isTrue);
    expect(parent.uiFor(onMap: true).criteria.values.containsKey('max_price'), isFalse);
    expect(scope.read(smartSearchSessionProvider).started, isFalse);
    parent.leaveMap(mapToken);
    expect(tester.takeException(), isNull);
    await closeUx(tester);
  });

  testWidgets('map-origin typing and final dictation keep matching bounds and use the map drawer', (tester) async {
    const bounds = {'south': 15.35, 'west': 44.17, 'north': 15.39, 'east': 44.21};
    final voice = Wave3VoiceFake(autoComplete: false);
    final ai = Wave3AiFake()..onRefine = (message, filters, revision) async => {
      'revision': revision,
      'filters': {...filters, 'purpose': 'rent', 'min_bedrooms': 3,
        if (message.contains('السعر')) 'max_price': 100000},
    };
    final properties = Wave3PropertiesFake()..onSearch = (filters, _) async =>
      ([wave3Property(filters.containsKey('max_monthly_rent') ? 12 : 11)], false);
    addTearDown(voice.dispose);
    final scope = uxContainer(extra: [
      aiRepositoryProvider.overrideWithValue(ai),
      voiceInputProvider.overrideWithValue(voice),
      propertyRepositoryProvider.overrideWithValue(properties),
      sharedSearchMapBuilderProvider.overrideWithValue((_, __, ___, ____) => const ColoredBox(color: Colors.teal)),
    ]);
    await pumpUx(tester, scope, const MarketplaceSearchMapScreen(), size: const Size(412, 820));
    final map = scope.read(marketplaceMapResultsProvider.notifier);
    map.updateViewport(south: bounds['south']!, west: bounds['west']!, north: bounds['north']!, east: bounds['east']!);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('map-open-search')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('map-smart-search')));
    await tester.pumpAndSettle();
    final listMode = find.byKey(const ValueKey('smart-search-list'));
    expect(listMode, findsOneWidget);
    final field = find.byKey(_description);
    const typed = 'أبحث عن شقة للإيجار بثلاث غرف';
    await tester.tap(find.byKey(const ValueKey('map-open-search')));
    await tester.pumpAndSettle();
    await tester.enterText(field, typed);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(ai.requests.single.message, typed);
    expect(ai.requests.single.filters, bounds);
    expect(properties.queries.last.filters, {...bounds, 'purpose': 'rent', 'min_bedrooms': 3});
    expect(listMode, findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('smart-search-voice')));
    await tester.pump();
    voice.latest.emit(const VoiceEvent('ready'));
    voice.latest.emit(const VoiceEvent('partial', text: 'خفّض السعر'));
    await tester.pump();
    expect(ai.requests, hasLength(1));
    final finish = find.byKey(const ValueKey('voice-finish'));
    await tester.ensureVisible(finish);
    await tester.tap(finish);
    await tester.pump();
    const dictated = 'خفّض السعر إلى مئة ألف';
    voice.latest.emit(const VoiceEvent('final', text: dictated));
    await tester.pumpAndSettle();
    expect(ai.requests.map((request) => request.message), [typed, dictated]);
    final filters = {...bounds, 'purpose': 'rent', 'min_bedrooms': 3, 'max_monthly_rent': 100000, 'currency': 'YER'};
    expect(properties.queries.last.filters, filters);
    final drawer = tester.widget<PropertyMapResultsSheet>(find.byType(PropertyMapResultsSheet));
    expect(drawer.items.map((row) => row.id), [12]);
    expect(listMode, findsOneWidget);
    final queryCount = properties.queries.length;
    await tester.tap(listMode);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('smart-search-result-12')), findsOneWidget);
    expect(properties.queries, hasLength(queryCount));
    expect(tester.takeException(), isNull);
    await closeUx(tester);
  });

  testWidgets('route replacement cancels active voice without publishing after disposal', (tester) async {
    final voice = Wave3VoiceFake(autoComplete: false), ai = Wave3AiFake();
    addTearDown(voice.dispose);
    final scope = uxContainer(extra: [voiceInputProvider.overrideWithValue(voice), aiRepositoryProvider.overrideWithValue(ai)]);
    final production = scope.read(appRouterProvider);
    addTearDown(production.dispose);
    final aiRoute = production.configuration.routes.whereType<GoRoute>().firstWhere((route) => route.path == '/smart-search');
    final navigation = GoRouter(initialLocation: '/smart-search', routes: [
      GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('الصفحة الرئيسية'))),
      GoRoute(path: '/smart-search', builder: aiRoute.builder),
    ]);
    addTearDown(navigation.dispose);
    await pumpUx(tester, scope, const SizedBox(), router: navigation);
    await tester.tap(find.byKey(const ValueKey('smart-search-voice'))); await tester.pump();
    voice.latest.emit(const VoiceEvent('ready')); await tester.pump();
    navigation.go('/'); await tester.pumpAndSettle();
    voice.latest.emit(const VoiceEvent('final', text: 'رد صوتي متأخر')); await tester.pump();
    expect(voice.latest.cancellations, greaterThanOrEqualTo(1));
    expect(ai.requests, isEmpty);
    expect(scope.read(smartSearchSessionProvider).started, isFalse);
    expect(tester.takeException(), isNull);
    await closeUx(tester);
  });

  for (final androidBack in [true, false]) {
    testWidgets('Dhamar search 20 returns from 147 and the child map by ${androidBack ? 'Android Back' : 'the app arrow'}', (tester) async {
      final properties = Wave3PropertiesFake()..onSearch = (filters, _) async =>
        ([
          wave3Property(147),
          if (filters['purpose'] != 'rent') wave3Property(146),
        ], false);
      final scope = uxContainer(extra: [
        propertyRepositoryProvider.overrideWithValue(properties),
        homeLocationProvider.overrideWith((ref) => _dhamar),
        homeLocationsProvider.overrideWith((ref) async => const [_dhamar]),
        sharedSearchMapBuilderProvider.overrideWithValue((_, __, ___, ____) => const ColoredBox(color: Colors.teal)),
      ]);
      final owner = scope.read(marketplaceSearchControllerProvider.notifier);
      owner.edit('20');
      owner.applyFilters(SmartSearchFilters.fromMap({'purpose': 'rent'}));
      final navigation = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => const MarketplaceSearchMapScreen()),
        GoRoute(path: '/properties/:id', builder: (_, state) => Scaffold(
          appBar: AppBar(title: Text('عقار ${state.pathParameters['id']}')))),
      ]);
      addTearDown(navigation.dispose);
      await pumpUx(tester, scope, const SizedBox(), router: navigation);
      await tester.pumpAndSettle();
      final parent = scope.read(marketplaceMapResultsProvider);
      expect(parent.filters.values, containsPair('search', '20'));
      expect(parent.filters.values, containsPair('purpose', 'rent'));

      Future<void> back() async {
        if (androidBack) {
          await tester.binding.handlePopRoute();
        } else {
          await tester.tap(find.byType(BackButton));
        }
        await tester.pumpAndSettle();
      }

      await tester.tap(find.byKey(const ValueKey('map-open-search')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('map-smart-search')));
      await tester.pumpAndSettle();
      expect(scope.read(smartSearchSessionProvider).filters.sameAs(parent.filters), isTrue);
      final listMode = find.byKey(const ValueKey('smart-search-list'));
      expect(listMode, findsOneWidget);
      await tester.tap(listMode);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('smart-chip-remove-purpose')));
      await tester.pumpAndSettle();
      final edited = scope.read(smartSearchSessionProvider);
      expect(edited.filters.values.containsKey('purpose'), isFalse);
      expect(edited.rows.map((row) => row.id), [147, 146]);

      final mapButton = find.byKey(const ValueKey('smart-search-map'));
      await tester.ensureVisible(mapButton);
      await tester.tap(mapButton);
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(const ValueKey('map-results-handle')), const Offset(0, -260));
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('map-result-147'));
      await tester.ensureVisible(card);
      await tester.tap(find.descendant(of: card, matching: find.text('عقار تجريبي 147')));
      await tester.pumpAndSettle();
      expect(find.text('عقار 147'), findsOneWidget);
      await back();
      expect(find.byKey(const ValueKey('smart-search-list')), findsOneWidget);
      expect(scope.read(smartSearchSessionProvider), same(edited));
      await back();
      expect(find.text('البحث الذكي'), findsOneWidget);
      expect(find.byKey(const ValueKey('smart-chip-remove-purpose')), findsNothing);
      expect(scope.read(smartSearchSessionProvider), same(edited));
      expect(scope.read(marketplaceMapResultsProvider), same(parent));

      await back();
      expect(find.byType(MarketplaceSearchMapScreen), findsOneWidget);
      expect(find.text('البحث على الخريطة'), findsNothing);
      expect(scope.read(marketplaceMapResultsProvider), same(parent));
      expect(scope.read(smartSearchSessionProvider).started, isFalse);
      expect(tester.takeException(), isNull);
      await closeUx(tester);
    });
  }
}

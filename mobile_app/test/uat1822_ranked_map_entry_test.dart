import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/discovery_suggestions.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_search_session.dart';
import 'package:real_estate_mobile/features/discovery/data/smart_search_session.dart';
import 'package:real_estate_mobile/features/discovery/domain/smart_search_filters.dart';
import 'package:real_estate_mobile/features/discovery/presentation/assisted_search_screen.dart';
import 'package:real_estate_mobile/features/discovery/presentation/marketplace_search_panel.dart';
import 'package:real_estate_mobile/features/map/presentation/property_map_results_sheet.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/properties/domain/saved_property_search.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_location_picker_screen.dart';

import 'support/owner_ux_fixtures.dart';
import 'wave2_home_search_test.dart' show Listings;

const _widePolygon =
    '[[44.1,14.4],[44.4075,14.4],[44.4075,15.55],[44.1,15.55],[44.1,14.4]]';
const _initialBounds = {
  'south': 14.95,
  'west': 44.24,
  'north': 15.0,
  'east': 44.27
};
const _fitBounds = {
  'south': 14.51,
  'west': 44.12,
  'north': 15.46,
  'east': 44.45
};

typedef _Rank = (int id, bool nearby);

List<_Rank> _rank(List<int> exact, List<int> nearby) => [
      for (final id in exact) (id, false),
      for (final id in nearby) (id, true),
    ];

class _NativeCamera {
  _NativeCamera(WidgetTester tester)
      : messenger = tester.binding.defaultBinaryMessenger {
    messenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final args = call.arguments as Map;
        channel = MethodChannel('plugins.flutter.io/maplibre_gl_${args['id']}');
        messenger.setMockMethodCallHandler(channel!, _onCall);
        return 0;
      }
      if (call.method == 'resize') {
        final args = call.arguments as Map;
        return {'width': args['width'], 'height': args['height']};
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
      if (channel != null) messenger.setMockMethodCallHandler(channel!, null);
    });
  }

  final TestDefaultBinaryMessenger messenger;
  MethodChannel? channel;
  Map<String, double> bounds = _initialBounds;
  int fits = 0;
  final animations = <Object?>[];

  Future<Object?> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'camera#animate':
        animations.add((call.arguments as Map)['cameraUpdate']);
        return true;
      case 'camera#move':
        fits++;
        bounds = _fitBounds;
      case 'map#getVisibleRegion':
        return {
          'sw': [bounds['south'], bounds['west']],
          'ne': [bounds['north'], bounds['east']],
        };
    }
    return null;
  }

  Future<void> emit(String method) => messenger.handlePlatformMessage(
        channel!.name,
        const StandardMethodCodec()
            .encodeMethodCall(MethodCall(method, <String, Object>{})),
        (_) {},
      );
}

void main() {
  setUpAll(loadUxFixtures);

  testWidgets(
      'a registered neighborhood locates the picker and requires a separate pin choice',
      (tester) async {
    final native = _NativeCamera(tester);
    final dio = Dio(BaseOptions(baseUrl: 'https://synthetic.example'));
    addTearDown(() => dio.close(force: true));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      expect(request.path, '/regions/cells');
      expect(request.queryParameters['search'], 'حدة');
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'data': [
          {
            'name_ar': 'حدة',
            'is_active': true,
            'governorate': {'name_ar': 'أمانة العاصمة'},
            'boundary': {
              'type': 'Polygon',
              'coordinates': [
                [
                  [44.20, 15.30],
                  [44.22, 15.30],
                  [44.22, 15.32],
                  [44.20, 15.32],
                  [44.20, 15.30],
                ]
              ],
            },
          }
        ],
      }));
    }));
    final scope = uxContainer(extra: [
      homeLocationsProvider.overrideWith((_) async => const <HomeLocation>[]),
      discoverySuggestionsRepositoryProvider
          .overrideWithValue(DiscoverySuggestionsRepository(dio)),
    ]);
    await pumpUx(tester, scope, const PropertyLocationPickerScreen());
    await native.emit('map#onStyleLoaded');
    await tester.pumpAndSettle();
    final controls = find.byType(PropertyLocationPickerControls);
    expect(tester.widget<PropertyLocationPickerControls>(controls).onConfirm,
        isNotNull);

    await tester.tap(find.byKey(const ValueKey('listing-map-find-address')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('map-address-input')), 'حدة');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('map-address-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حدة، أمانة العاصمة'));
    await tester.pumpAndSettle();
    final animation = native.animations.single as List;
    final point = animation[1] as List;
    expect(point[0], closeTo(15.31, 1e-9));
    expect(point[1], closeTo(44.21, 1e-9));
    expect(tester.widget<PropertyLocationPickerControls>(controls).onConfirm,
        isNull);
    expect(find.text('حرّك الدبوس على موقع العقار لتأكيده.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await closeUx(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
      'opening the marketplace map keeps the settled 21 listings in Sana’a',
      (tester) async {
    final native = _NativeCamera(tester);
    final listings = List.generate(
        21,
        (index) => PropertySummary(
              id: 200 + index,
              title: 'عقار ${index + 1}',
              type: 'house',
              purpose: 'sale',
              price: 100000,
              currency: 'YER',
              latitude: 15.1 + index * .02,
              longitude: 44.25,
            ));
    final repository = Listings()
      ..respond = (filters, page) async {
        if (filters.containsKey('south')) {
          return (listings.take(19).toList(), false);
        }
        return page == 1
            ? (listings.take(20).toList(), true)
            : (listings.skip(20).toList(), false);
      };
    final scope = uxContainer(
        extra: [propertyRepositoryProvider.overrideWithValue(repository)]);
    scope.read(homeLocationProvider.notifier).state = const HomeLocation(
      latitude: 15.3694,
      longitude: 44.1910,
      governorate: 'صنعاء',
      label: 'محافظة صنعاء',
      manual: true,
    );
    final journey = scope.read(marketplaceSearchControllerProvider.notifier);
    journey.applyFilters(SmartSearchFilters.fromMap({'purpose': 'sale'}));
    await tester.pump();
    final home = scope.read(homeSearchResultsProvider.notifier);
    await home.loadNextPage(home.snapshot);
    expect(home.snapshot.rows, hasLength(21));

    journey.enterMap();
    await pumpUx(tester, scope, const MarketplaceSearchMapScreen());
    await native.emit('map#onStyleLoaded');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('marketplace-map-find-address')), findsOneWidget);
    expect(native.fits, 1);
    await native.emit('camera#onIdle');
    await uxFrames(tester);
    final drawer = tester
        .widget<PropertyMapResultsSheet>(find.byType(PropertyMapResultsSheet));
    expect(drawer.items.map((row) => row.id), listings.map((row) => row.id));
    expect(
        scope.read(marketplaceMapResultsProvider).filters.values['governorate'],
        'صنعاء');
    expect(repository.calls, hasLength(2));

    native.bounds = _initialBounds;
    await tester.dragFrom(
        tester.getTopLeft(find.byType(MapLibreMap)) + const Offset(200, 25),
        const Offset(65, 0));
    await native.emit('camera#onIdle');
    await uxFrames(tester);
    expect(
        repository.calls.last, containsPair('south', _initialBounds['south']));
    expect(scope.read(marketplaceMapResultsProvider).rows, hasLength(19));
    expect(home.snapshot.rows, hasLength(21));
    expect(tester.takeException(), isNull);
    await closeUx(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  final pages10 = [
    _rank([
      145,
      144,
      143,
      140,
      139,
      138,
      136,
      135,
      134,
      133,
      131,
      130,
      129,
      128,
      127,
      126,
      125,
      124,
      123,
      122
    ], []),
    _rank(List.generate(16, (i) => 121 - i), [142, 147, 141, 146]),
    _rank([], [132, 137]),
  ];
  const nearby11 = [140, 133, 138, 135, 147, 131, 142, 136, 129];
  for (final (id, name, filters, pages) in [
    (6, '10', {'area_polygon': _widePolygon}, pages10),
    for (final (id, label, east, onBoundary) in [
      (7, 'on', 44.4, true),
      (8, 'out', 44.3999, false)
    ])
      (
        id,
        '11-$label',
        {
          'area_polygon': jsonEncode([
            [44.399, 14.551],
            [east, 14.551],
            [east, 14.553],
            [44.399, 14.553],
            [44.399, 14.551]
          ]),
          'purpose': 'rent',
          'governorate_code': 'DHAMAR',
        },
        [
          _rank(onBoundary ? [145] : [], [if (!onBoundary) 145, ...nearby11])
        ]
      ),
  ]) {
    testWidgets(
        'saved case $name keeps ranked pages through native map startup and drawer scrolling',
        (tester) async {
      final native = _NativeCamera(tester);
      final requests = <Map<String, dynamic>>[];
      final all = pages.expand((page) => page).toList();
      final dio = Dio();
      addTearDown(() => dio.close(force: true));
      dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
        expectSync(request.path, '/properties');
        final query = Map<String, dynamic>.of(request.queryParameters);
        requests.add(query);
        final hasCamera = query.containsKey('south');
        final candidates =
            hasCamera ? [_rank([], List.generate(12, (i) => 106 + i))] : pages;
        final currentPage = query['page'] as int;
        final combined = candidates.expand((page) => page).toList();
        final exactCount = combined.where((rank) => !rank.$2).length;
        handler.resolve(Response(
            requestOptions: request,
            statusCode: 200,
            headers: Headers.fromMap({
              'x-aqer-ranked-contract': ['1']
            }),
            data: {
              'data': [
                for (final (id, nearby) in candidates[currentPage - 1])
                  {
                    'id': id,
                    'title': 'عقار $id',
                    'purpose': 'rent',
                    'type': 'house',
                    'price': 100000,
                    'currency': 'YER',
                    'latitude': id == 145 ? 14.552 : 15.18 + id / 1000,
                    'longitude': id == 145 ? 44.4 : 44.2,
                    'discovery_match': {
                      'kind': nearby ? 'nearby' : 'exact',
                      'reasons': [
                        if (nearby)
                          {
                            'field': 'location',
                            'message': 'خارج المنطقة المرسومة'
                          }
                      ]
                    },
                  }
              ],
              'meta': {
                'current_page': currentPage,
                'last_page': candidates.length,
                'total': combined.length,
                'exact_total': exactCount,
                'alternative_total': combined.length - exactCount
              },
            }));
      }));
      final scope = uxContainer(user: uxUser(id: 28, type: 'broker'), extra: [
        propertyRepositoryProvider.overrideWith((ref) => PropertyRepository(
            dio, ref.watch(authRepositoryProvider),
            rankedDiscovery: true)),
      ]);
      final search = SavedPropertySearch(
          id: id,
          name: 'UAT1822 $name',
          filters: filters,
          alertFrequency: 'off',
          isActive: true,
          matchingCount: all.where((rank) => !rank.$2).length);
      await pumpUx(tester, scope, AssistedSearchScreen(savedSearch: search));
      await tester.pumpAndSettle();
      final list = find.byType(Scrollable).first;
      final more = find.text('المزيد من العقارات');
      for (var page = 1; page < pages.length; page++) {
        await tester.scrollUntilVisible(more, 500, scrollable: list);
        await tester.tap(more);
        await tester.pumpAndSettle();
      }
      final stateBeforeMap = scope.read(smartSearchSessionProvider);
      expect(
          stateBeforeMap.rows
              .map((row) => (row.id, row.discoveryMatch!.nearby)),
          all);
      Map<String, dynamic> query(int page) => {
            ...filters,
            'page': page,
            'per_page': 20,
            'sort': 'latest',
            'ranked_search': 1,
            'ranking_version': 2,
          };
      final listRequests = [
        for (var page = 1; page <= pages.length; page++) query(page)
      ];
      expect(requests, listRequests);

      final mapButton = find.byKey(const ValueKey('smart-search-map'));
      tester.state<ScrollableState>(list).position.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(mapButton);
      await tester.pumpAndSettle();
      // Exercise the actual MapLibre method channel callbacks. The native view
      // can report idle with its initial region before the style finishes, then
      // report another region after the programmatic fit or a layout change.
      await native.emit('camera#onIdle');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await native.emit('map#onStyleLoaded');
      await tester.pumpAndSettle();
      expect(native.fits, 1);
      native.bounds = {..._fitBounds, 'north': 15.50};
      await native.emit('camera#onIdle');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      final handle = find.byKey(const ValueKey('map-results-handle'));
      await tester.drag(handle, const Offset(0, -310));
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(const ValueKey('map-results-list')),
          const Offset(0, -180));
      await tester.pumpAndSettle();

      expect(requests, listRequests,
          reason: 'Camera initialization must not issue a new page 1 request.');
      final stateOnMap = scope.read(smartSearchSessionProvider);
      expect(stateOnMap.filters.values, filters);
      expect(stateOnMap.page, stateBeforeMap.page);
      expect(stateOnMap.revision, stateBeforeMap.revision);
      final drawer = tester.widget<PropertyMapResultsSheet>(
          find.byType(PropertyMapResultsSheet));
      expect(
          drawer.items.map((row) => (row.id, row.discoveryMatch!.nearby)), all);
      expect(drawer.more, isFalse);
      expect(find.text('${all.length} نتيجة'), findsOneWidget);

      if (id == 6) {
        // Moving the map itself still commits a viewport for the current search.
        native.bounds = _initialBounds;
        await tester.dragFrom(
            tester.getTopLeft(find.byType(MapLibreMap)) + const Offset(230, 20),
            const Offset(65, 0));
        await native.emit('camera#onIdle');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(requests, [
          ...listRequests,
          {
            ...query(1),
            ..._initialBounds,
            'west': const LatLng(0, 44.24).longitude,
            'east': const LatLng(0, 44.27).longitude,
          }
        ]);
        expect(scope.read(smartSearchSessionProvider).page, 1);
        expect(scope.read(smartSearchSessionProvider).rows.map((row) => row.id),
            List.generate(12, (i) => 106 + i));
        native.bounds = _fitBounds;
        await native.emit('camera#onIdle');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(requests, hasLength(4),
            reason:
                'A settled gesture must not authorize a later layout idle.');
      }
      expect(tester.takeException(), isNull);
      await closeUx(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }
}

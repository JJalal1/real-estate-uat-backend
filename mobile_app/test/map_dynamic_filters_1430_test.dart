import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:real_estate_mobile/features/discovery/data/ai_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_search_session.dart';
import 'package:real_estate_mobile/features/discovery/data/smart_search_session.dart';
import 'package:real_estate_mobile/features/discovery/domain/smart_search_filters.dart';
import 'package:real_estate_mobile/features/discovery/presentation/assisted_search_screen.dart';
import 'package:real_estate_mobile/features/discovery/presentation/marketplace_search_panel.dart';
import 'package:real_estate_mobile/features/map/presentation/map_screen.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'support/owner_ux_fixtures.dart';
import 'support/wave3_fakes.dart';
import 'wave2_home_search_test.dart' show Listings;

const _map = ColoredBox(key: ValueKey('filters-map-canvas'), color: Color(0xffe3eee9),
  child: Center(child: Text('خريطة اختبار اصطناعية')));

Future<void> _tap(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _apply(WidgetTester tester) async {
  final apply = find.text('تطبيق الشروط');
  await tester.ensureVisible(apply);
  await tester.tap(apply);
  await tester.pumpAndSettle();
}

Future<void> _stroke(WidgetTester tester) async {
  final rect = tester.getRect(find.byKey(const ValueKey('map-area-drawing')));
  Offset point(double x, double y) => Offset(rect.left + rect.width * x, rect.top + rect.height * y);
  final gesture = await tester.startGesture(point(.20, .45));
  for (final p in [point(.32, .40), point(.55, .39), point(.75, .45), point(.76, .58),
    point(.58, .67), point(.34, .65), point(.20, .53), point(.20, .45)]) {
    await gesture.moveTo(p);
    await tester.pump(const Duration(milliseconds: 25));
  }
  await gesture.up();
  await tester.pump();
}

void main() {
  setUpAll(loadUxFixtures);

  test('map budget, rooms and bathroom criteria reach the API and type changes clear inapplicable fields', () async {
    final listings = Listings(), scope = uxContainer(extra: [propertyRepositoryProvider.overrideWithValue(listings)]);
    final controller = scope.read(marketplaceSearchControllerProvider.notifier);
    controller.enterMap();
    scope.read(marketplaceMapResultsProvider.notifier).updateViewport(south: 15, west: 44, north: 16, east: 45);
    controller.setChoice('type', 'apartment');
    controller.setChoice('purpose', 'rent');
    controller.setChoice('min_bedrooms', 3);
    controller.setChoice('min_bathrooms', 2);
    controller.setChoice('max_price', 250000);
    await Future<void>.delayed(Duration.zero);
    final query = scope.read(marketplaceMapResultsProvider).filters.apiFilters;
    expect(query, containsPair('min_bedrooms', 3));
    expect(query, containsPair('min_bathrooms', 2));
    expect(query, containsPair('max_monthly_rent', 250000));
    expect(query, containsPair('currency', 'YER'));
    expect(query, containsPair('south', 15));
    expect(listings.calls.any((call) => call['min_bathrooms'] == 2 && call['max_monthly_rent'] == 250000), isTrue);
    controller.setChoice('type', 'land');
    await Future<void>.delayed(Duration.zero);
    expect(scope.read(marketplaceMapResultsProvider).filters.values.containsKey('min_bedrooms'), isFalse);
    expect(scope.read(marketplaceMapResultsProvider).filters.values.containsKey('min_bathrooms'), isFalse);
    expect(scope.read(marketplaceMapResultsProvider).filters.values['max_price'], 250000);
    controller.setChoice('purpose', 'rent');
    await Future<void>.delayed(Duration.zero);
    expect(scope.read(marketplaceSearchControllerProvider).criteria.values.containsKey('purpose'), isFalse);
    expect(scope.read(marketplaceMapResultsProvider).filters.apiFilters.containsKey('purpose'), isFalse);
  });

  testWidgets('selected filters remain visible after apply and submit, without a purpose-all chip', (tester) async {
    final listings = Listings(), scope = uxContainer(extra: [propertyRepositoryProvider.overrideWithValue(listings)]);
    await pumpUx(tester, scope, const Scaffold(body: SingleChildScrollView(child: MarketplaceSearchPanel(onMap: true))));
    expect(find.byKey(const ValueKey('published-purpose-all')), findsNothing);
    await _tap(tester, 'published-type-apartment');
    await _tap(tester, 'published-filter-rooms');
    await _tap(tester, 'filter-min_bedrooms-3');
    await _apply(tester);
    expect(find.byTooltip('3 غرف فأكثر'), findsOneWidget);
    await _tap(tester, 'published-filter-bathrooms');
    await _tap(tester, 'filter-min_bathrooms-2');
    await _apply(tester);
    expect(find.byTooltip('2 دورات مياه فأكثر'), findsOneWidget);
    await _tap(tester, 'published-filter-max-price');
    await tester.enterText(find.byKey(const ValueKey('filter-max_price')), '٢٥٠٬٠٠٠');
    await _apply(tester);
    await _tap(tester, 'published-search-submit');
    expect(find.byTooltip('3 غرف فأكثر'), findsOneWidget);
    expect(find.byTooltip('2 دورات مياه فأكثر'), findsOneWidget);
    expect(scope.read(marketplaceSearchControllerProvider).criteria.values['max_price'], 250000);
    expect(find.byKey(const ValueKey('published-map-filters')), findsOneWidget);
    await _tap(tester, 'published-type-land');
    expect(find.byKey(const ValueKey('published-filter-rooms')), findsNothing);
    expect(find.byKey(const ValueKey('published-filter-bathrooms')), findsNothing);
    expect(find.byKey(const ValueKey('published-filter-land-use')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await closeUx(tester);
  });

  testWidgets('price range validation retains the current filters until valid Arabic input is applied', (tester) async {
    final scope = uxContainer(extra: [propertyRepositoryProvider.overrideWithValue(Listings())]);
    final controller = scope.read(marketplaceSearchControllerProvider.notifier);
    controller.applyFilters(SmartSearchFilters.fromMap({'min_price': 200000, 'type': 'house'}));
    await pumpUx(tester, scope, const Scaffold(body: SingleChildScrollView(child: MarketplaceSearchPanel(onMap: true))));
    await _tap(tester, 'published-filter-max-price');
    await tester.enterText(find.byKey(const ValueKey('filter-max_price')), '١٠٠٠٠٠');
    await _apply(tester);
    expect(find.text('الحد الأدنى يجب ألا يتجاوز الحد الأعلى.'), findsOneWidget);
    expect(scope.read(marketplaceSearchControllerProvider).criteria.values.containsKey('max_price'), isFalse);
    await tester.enterText(find.byKey(const ValueKey('filter-max_price')), '٣٠٠٠٠٠');
    await _apply(tester);
    expect(scope.read(marketplaceSearchControllerProvider).criteria.values['max_price'], 300000);
    expect(tester.takeException(), isNull);
    await closeUx(tester);
  });

  testWidgets('drawing sends a real polygon with existing filters and clearing it preserves the viewport', (tester) async {
    final listings = Listings();
    final scope = uxContainer(extra: [
      propertyRepositoryProvider.overrideWithValue(listings),
      sharedSearchMapBuilderProvider.overrideWithValue((context, rows, pick, viewport) => _map),
      sharedSearchMapProjectorProvider.overrideWithValue((pixels) async =>
        LatLng(15.0 + pixels.y / 10000, 44.0 + pixels.x / 10000)),
    ]);
    await pumpUx(tester, scope, const MarketplaceSearchMapScreen());
    await tester.pumpAndSettle();
    await _tap(tester, 'published-type-house');
    await _tap(tester, 'map-draw-area');
    expect(find.byKey(const ValueKey('map-results-sheet')), findsNothing);
    await _stroke(tester);
    await tester.pumpAndSettle();
    final filters = scope.read(marketplaceMapResultsProvider).filters.values;
    expect(filters['area_polygon'], isA<String>());
    expect(filters['type'], 'house');
    expect(filters['south'], isA<double>());
    expect(listings.calls.last['area_polygon'], filters['area_polygon']);
    expect(scope.read(homeSearchResultsProvider).filters.values.containsKey('area_polygon'), isFalse);
    expect(find.byKey(const ValueKey('map-drawn-area')), findsOneWidget);
    tester.widget<InputChip>(find.byKey(const ValueKey('map-drawn-area'))).onDeleted!();
    await tester.pumpAndSettle();
    expect(scope.read(marketplaceMapResultsProvider).filters.values.containsKey('area_polygon'), isFalse);
    expect(scope.read(marketplaceMapResultsProvider).filters.values['south'], filters['south']);
    expect(tester.takeException(), isNull);
    await closeUx(tester);
  });

  testWidgets('cancel invalidates an in-flight native projection and never applies its late polygon', (tester) async {
    final projection = Completer<LatLng>(), listings = Listings();
    final scope = uxContainer(extra: [
      propertyRepositoryProvider.overrideWithValue(listings),
      sharedSearchMapBuilderProvider.overrideWithValue((context, rows, pick, viewport) => _map),
      sharedSearchMapProjectorProvider.overrideWithValue((pixels) => projection.future),
    ]);
    await pumpUx(tester, scope, const MarketplaceSearchMapScreen());
    await tester.pumpAndSettle();
    final before = listings.calls.length;
    await _tap(tester, 'map-draw-area');
    await _stroke(tester);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    projection.complete(const LatLng(15.4, 44.2));
    await tester.pumpAndSettle();
    expect(listings.calls.length, before);
    expect(scope.read(marketplaceMapResultsProvider).filters.values.containsKey('area_polygon'), isFalse);
    expect(find.byKey(const ValueKey('map-area-drawing')), findsNothing);
    expect(tester.takeException(), isNull);
    await closeUx(tester);
  });

  testWidgets('smart search receives map context and returns accepted semantic filters to the map and list', (tester) async {
    final ai = Wave3AiFake(), listings = Listings();
    final scope = uxContainer(extra: [
      aiRepositoryProvider.overrideWithValue(ai), propertyRepositoryProvider.overrideWithValue(listings),
      sharedSearchMapBuilderProvider.overrideWithValue((context, rows, pick, viewport) => _map),
    ]);
    await pumpUx(tester, scope, const MarketplaceSearchMapScreen());
    await tester.pumpAndSettle();
    final controller = scope.read(marketplaceSearchControllerProvider.notifier);
    controller.applyFilters(SmartSearchFilters.fromMap({'type': 'apartment', 'purpose': 'rent', 'min_bedrooms': 3}));
    scope.read(marketplaceMapResultsProvider.notifier).updateViewport(south: 15, west: 44, north: 16, east: 45);
    await tester.pumpAndSettle();
    await _tap(tester, 'map-smart-search');
    expect(find.byType(AssistedSearchScreen), findsOneWidget);
    expect(scope.read(smartSearchSessionProvider).filters.values['south'], 15);
    await tester.enterText(find.byKey(const ValueKey('smart-search-description')), 'خفض السعر');
    await _tap(tester, 'smart-search-send');
    expect(ai.requests.single.filters['min_bedrooms'], 3);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(scope.read(marketplaceSearchControllerProvider).criteria.values['max_price'], 100000);
    expect(scope.read(marketplaceMapResultsProvider).filters.values['south'], 15);
    expect(scope.read(homeSearchResultsProvider).filters.values.containsKey('south'), isFalse);
    expect(scope.read(marketplaceMapResultsProvider).filters.apiFilters['max_monthly_rent'], 100000);
    expect(tester.takeException(), isNull);
    await closeUx(tester);
  });

  testWidgets('an assistant reply from the previous account cannot repopulate the new map session', (tester) async {
    final auth = UxAuth(uxUser(id: 1)), ai = Wave3AiFake();
    final reply = Completer<Map<String, dynamic>>();
    ai.onRefine = (_, __, ___) => reply.future;
    final scope = uxContainer(auth: auth, extra: [
      aiRepositoryProvider.overrideWithValue(ai), propertyRepositoryProvider.overrideWithValue(Listings()),
      sharedSearchMapBuilderProvider.overrideWithValue((context, rows, pick, viewport) => _map),
    ]);
    await pumpUx(tester, scope, const MarketplaceSearchMapScreen());
    await tester.pumpAndSettle();
    await _tap(tester, 'published-type-apartment');
    await _tap(tester, 'map-smart-search');
    await tester.enterText(find.byKey(const ValueKey('smart-search-description')), 'خفض السعر');
    await tester.ensureVisible(find.byKey(const ValueKey('smart-search-send')));
    await tester.tap(find.byKey(const ValueKey('smart-search-send')));
    await tester.pump();
    auth.change(uxUser(id: 2));
    await tester.pump();
    reply.complete({'revision': ai.requests.single.revision,
      'filters': {'type': 'house', 'max_price': 123456}, 'message': 'نتيجة الحساب السابق'});
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(scope.read(marketplaceSearchControllerProvider).criteria.values, isEmpty);
    expect(scope.read(marketplaceMapResultsProvider).filters.values.containsKey('max_price'), isFalse);
    expect(tester.takeException(), isNull);
    await closeUx(tester);
  });

  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.4]) {
      testWidgets('real filter toolbar retains map space and selected controls in RTL dark=$dark scale=$scale', (tester) async {
        final boundary = GlobalKey(), listings = Listings();
        final scope = uxContainer(extra: [
          propertyRepositoryProvider.overrideWithValue(listings),
          sharedSearchMapBuilderProvider.overrideWithValue((context, rows, pick, viewport) => _map),
        ]);
        final controller = scope.read(marketplaceSearchControllerProvider.notifier);
        controller.applyFilters(SmartSearchFilters.fromMap({'purpose': 'rent', 'type': 'apartment',
          'min_bedrooms': 3, 'min_bathrooms': 2, 'max_price': 250000, 'has_parking': true}));
        await pumpUx(tester, scope, const MarketplaceSearchMapScreen(), boundary: boundary,
          size: scale == 1 ? const Size(412,820) : const Size(320,568), dark: dark, scale: scale);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('published-purpose-all')), findsNothing);
        expect(find.byKey(const ValueKey('published-filter-rooms')), findsOneWidget);
        expect(find.byKey(const ValueKey('published-selected-has_parking')), findsOneWidget);
        expect(find.byKey(const ValueKey('map-draw-area')), findsOneWidget);
        expect(find.byKey(const ValueKey('map-smart-search')), findsOneWidget);
        final toolbar = tester.getRect(find.byKey(const ValueKey('marketplace-search-toolbar')));
        final list = tester.getRect(find.byKey(const ValueKey('map-results-list')));
        expect(list.top - toolbar.bottom, greaterThanOrEqualTo(70));
        for (final key in ['published-purpose-rent', 'published-map-filters', 'map-draw-area', 'map-smart-search']) {
          final rect = tester.getRect(find.byKey(ValueKey(key)));
          expect(rect.left, greaterThanOrEqualTo(toolbar.left - 1));
          expect(rect.right, lessThanOrEqualTo(toolbar.right + 1));
          expect(rect.bottom, lessThanOrEqualTo(toolbar.bottom + 1));
        }
        final maximum = find.byKey(const ValueKey('published-filter-max-price'));
        if (scale == 1) {
          final rect = tester.getRect(maximum);
          expect(rect.left, greaterThanOrEqualTo(toolbar.left));
          expect(rect.right, lessThanOrEqualTo(toolbar.right));
          expect(rect.bottom, lessThanOrEqualTo(toolbar.bottom));
        }
        await uxPreview(tester, boundary, 'map-filters-1430-$dark-$scale');
        await tester.ensureVisible(maximum);
        await tester.pumpAndSettle();
        expect(tester.getRect(maximum).bottom, lessThanOrEqualTo(toolbar.bottom + 1));
        await uxPreview(tester, boundary, 'map-filters-1430-$dark-$scale-controls');
        expect(tester.takeException(), isNull);
        await closeUx(tester);
      });
    }
  }
}

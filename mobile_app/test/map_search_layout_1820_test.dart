import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:real_estate_mobile/core/theme/ebroker_design.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_search_session.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_repository.dart';
import 'package:real_estate_mobile/features/discovery/domain/smart_search_filters.dart';
import 'package:real_estate_mobile/features/discovery/presentation/marketplace_search_panel.dart';
import 'package:real_estate_mobile/features/map/presentation/map_screen.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'support/owner_ux_fixtures.dart';
import 'wave2_home_search_test.dart' show Listings, PageResult;

Future<void> _tap(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

class _MapLifetimeCanvas extends StatefulWidget {
  const _MapLifetimeCanvas({required this.onMount, required this.onUnmount});
  final VoidCallback onMount, onUnmount;
  @override
  State<_MapLifetimeCanvas> createState() => _MapLifetimeCanvasState();
}

class _MapLifetimeCanvasState extends State<_MapLifetimeCanvas> {
  @override
  void initState() { super.initState(); widget.onMount(); }
  @override
  void dispose() { widget.onUnmount(); super.dispose(); }
  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.teal);
}

void main() {
  setUpAll(loadUxFixtures);

  testWidgets('fresh map shows both purposes without selecting either and keeps the property type', (tester) async {
    PropertySummary row(int id, String purpose, String type) => PropertySummary(
      id: id, title: 'إعلان $id', type: type, purpose: purpose, price: 190000,
      currency: 'YER', latitude: 15.36, longitude: 44.19,
    );
    final rows = [row(1, 'rent', 'apartment'), row(2, 'sale', 'apartment'), row(3, 'sale', 'house')];
    final listings = Listings()..respond = (filters, _) async => (
      rows.where((row) =>
        (filters['purpose'] == null || filters['purpose'] == row.purpose) &&
        (filters['type'] == null || filters['type'] == row.type)).toList(),
      false,
    );
    final scope = uxContainer(extra: [
      propertyRepositoryProvider.overrideWithValue(listings),
      sharedSearchMapBuilderProvider.overrideWithValue((_, __, ___, ____) => const SizedBox.expand()),
    ]);
    await pumpUx(tester, scope, const MarketplaceSearchMapScreen());
    await tester.pumpAndSettle();
    bool selected(String key) => tester.widget<Semantics>(find.ancestor(
      of: find.byKey(ValueKey(key)),
      matching: find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.selected != null),
    ).first).properties.selected!;
    List<int> ids() => scope.read(marketplaceMapResultsProvider).rows.map((row) => row.id).toList();
    expect(selected('published-purpose-sale'), isFalse);
    expect(selected('published-purpose-rent'), isFalse);
    expect(listings.calls.single.containsKey('purpose'), isFalse);
    expect(ids(), [1, 2, 3]);

    await _tap(tester, 'published-type-apartment');
    expect(ids(), [1, 2]);
    await _tap(tester, 'published-purpose-rent');
    expect(selected('published-purpose-rent'), isTrue);
    expect(selected('published-purpose-sale'), isFalse);
    expect(ids(), [1]);
    await _tap(tester, 'published-purpose-rent');
    expect(selected('published-purpose-rent'), isFalse);
    expect(listings.calls.last['type'], 'apartment');
    expect(listings.calls.last.containsKey('purpose'), isFalse);
    expect(ids(), [1, 2]);
    await _tap(tester, 'published-purpose-sale');
    expect(selected('published-purpose-sale'), isTrue);
    expect(ids(), [2]);
    expect(tester.takeException(), isNull);
    await closeUx(tester);
  });

  testWidgets('full map results keep the drawn-area filters, loaded pages and mounted map', (tester) async {
    const triangle = '[[44.35,14.5],[44.45,14.5],[44.35,14.6],[44.35,14.5]]';
    PropertySummary rental(int id, double latitude, double longitude) => PropertySummary(
      id: id, title: 'شقة للإيجار $id', type: 'apartment', purpose: 'rent', price: 220000,
      monthlyRent: 220000, currency: 'YER', latitude: latitude, longitude: longitude,
    );
    final first = rental(4, 14.52, 44.36), second = rental(19, 14.54, 44.38);
    final outside = rental(25, 14.59, 44.44);
    final listings = Listings()..respond = (filters, page) async {
      if (filters['area_polygon'] == null) return ([first, second, outside], false);
      return page == 1 ? ([first, outside], true) : ([second], false);
    };
    late void Function(double, double, double, double) viewport;
    List<int> pins = [];
    var mounts = 0, disposals = 0;
    final scope = uxContainer(extra: [
      propertyRepositoryProvider.overrideWithValue(listings),
      sharedSearchMapBuilderProvider.overrideWithValue((_, rows, __, update) {
        viewport = update;
        pins = rows.map((row) => row.id).toList();
        return _MapLifetimeCanvas(onMount: () => mounts++, onUnmount: () => disposals++);
      }),
    ]);
    await pumpUx(tester, scope, const MarketplaceSearchMapScreen());
    await tester.pumpAndSettle();
    await _tap(tester, 'published-type-apartment');
    await _tap(tester, 'published-purpose-rent');
    viewport(14.49, 44.31, 14.65, 44.48);
    await tester.pumpAndSettle();
    await scope.read(marketplaceMapResultsProvider.notifier).applyDrawnArea(triangle);
    await tester.pumpAndSettle();
    expect(pins, [4]);
    final map = scope.read(marketplaceSearchControllerProvider.notifier);
    final journey = map.mapJourneyToken;
    final filters = scope.read(marketplaceMapResultsProvider).filters;
    final previousQuery = listings.calls.last;
    expect(previousQuery['purpose'], 'rent');
    expect(previousQuery['type'], 'apartment');
    expect(previousQuery['area_polygon'], triangle);
    expect(previousQuery['south'], 14.49);
    final requests = listings.calls.length;

    await _tap(tester, 'map-show-list');
    expect(find.text('قائمة العقارات'), findsOneWidget);
    expect(find.byKey(const ValueKey('map-results-sheet')), findsNothing);
    expect(find.text('داخل المنطقة المرسومة'), findsOneWidget);
    expect(find.byKey(const ValueKey('map-full-result-4')), findsOneWidget);
    expect(find.byKey(const ValueKey('map-full-result-25')), findsNothing);
    expect(listings.calls, hasLength(requests));
    expect(mounts, 1);
    expect(disposals, 0);

    await tester.tap(find.text('المزيد من العقارات'));
    await tester.pumpAndSettle();
    expect(listings.calls.last, {...previousQuery, 'page': 2});
    expect(find.text('نتيجتان'), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const ValueKey('map-full-result-4'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey('map-full-result-19'))).dy));
    expect(find.byKey(const ValueKey('map-full-result-25')), findsNothing);

    await _tap(tester, 'map-full-list-return');
    expect(find.text('قائمة العقارات'), findsNothing);
    expect(map.isMapJourneyCurrent(journey), isTrue);
    expect(scope.read(marketplaceMapResultsProvider).filters.sameAs(filters), isTrue);
    expect(pins, [4, 19]);
    expect(mounts, 1);
    expect(disposals, 0);
    expect(listings.calls, hasLength(requests + 1));

    await _tap(tester, 'map-show-list');
    expect(find.text('نتيجتان'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('قائمة العقارات'), findsNothing);
    expect(map.isMapJourneyCurrent(journey), isTrue);
    expect(scope.read(marketplaceMapResultsProvider).filters.sameAs(filters), isTrue);
    expect(listings.calls, hasLength(requests + 1));
    expect(tester.takeException(), isNull);
    await closeUx(tester);
  });

  testWidgets('delayed Dhamar results keep the confirmed governorate camera and whole-province criteria', (tester) async {
    final reply = Completer<PageResult>();
    final properties = Listings()..respond = (_, __) => reply.future;
    final scope = uxContainer(extra: [propertyRepositoryProvider.overrideWithValue(properties),
      sharedSearchMapBuilderProvider.overrideWithValue((context, rows, pick, viewport) =>
        const ColoredBox(color: Colors.teal)),
    ]);
    scope.read(homeLocationProvider.notifier).state = const HomeLocation(
      latitude: 14.5428, longitude: 44.4051, governorate: 'ذمار', governorateCode: 'DH', label: 'ذمار', manual: true);
    await pumpUx(tester, scope, const MarketplaceSearchMapScreen());
    await tester.pump();
    final map = tester.widget<MapScreen>(find.byType(MapScreen));
    expect(map.cameraCenterHint!.latitude, closeTo(14.5428, 1e-9));
    expect(map.cameraCenterHint!.longitude, closeTo(44.4051, 1e-9));
    expect(scope.read(marketplaceMapResultsProvider).filters.values['governorate_code'], 'DH');
    expect(scope.read(marketplaceMapResultsProvider).filters.values.containsKey('south'), isFalse);
    expect(scope.read(marketplaceMapResultsProvider).filters.values.containsKey('radius_km'), isFalse);
    expect(properties.calls.single['governorate'], 'ذمار');
    expect(properties.calls.single.containsKey('latitude'), isFalse);
    reply.complete((<PropertySummary>[], false));
    await tester.pumpAndSettle();
    expect(properties.calls, hasLength(1));
    expect(tester.takeException(), isNull);
    await closeUx(tester);
  });

  testWidgets('a failed map viewport refresh keeps compatible cards and pins until a retry succeeds', (tester) async {
    PropertySummary listing(int id, double latitude) => PropertySummary(
      id: id, title: 'إيجار في ذمار $id', type: 'house', purpose: 'rent', price: 230000,
      currency: 'YER', latitude: latitude, longitude: 44.4);
    final request = RequestOptions(path: '/properties');
    final failedRefresh = Completer<PageResult>();
    final properties = Listings()..respond = (_, __) async => ([listing(145, 14.552), listing(147, 14.6)], false);
    late void Function(double, double, double, double) viewport;
    var pins = <int>[];
    final scope = uxContainer(extra: [
      propertyRepositoryProvider.overrideWithValue(properties),
      sharedSearchMapBuilderProvider.overrideWithValue((context, rows, pick, updateViewport) {
        viewport = updateViewport;
        pins = rows.map((row) => row.id).toList();
        return const ColoredBox(color: Colors.teal);
      }),
    ]);
    scope.read(marketplaceSearchControllerProvider.notifier).applyFilters(SmartSearchFilters.fromMap({'purpose': 'rent'}));
    await pumpUx(tester, scope, const MarketplaceSearchMapScreen());
    await tester.pumpAndSettle();
    expect(pins, [145, 147]);

    properties.respond = (_, __) => failedRefresh.future;
    viewport(14.5, 44.35, 14.57, 44.45);
    await tester.pump();
    expect(pins, [145]);
    failedRefresh.completeError(DioException(requestOptions: request, type: DioExceptionType.unknown));
    await tester.pumpAndSettle();
    expect(pins, [145]);
    const countKey = ValueKey('map-results-count');
    expect(tester.widget<Text>(find.byKey(countKey)).data, '١ نتيجة');
    final staleCount = find.byWidgetPredicate((widget) =>
      widget is Semantics && widget.properties.label == '١ نتيجة من آخر تحميل');
    expect(staleCount, findsOneWidget);

    await tester.drag(find.byKey(const ValueKey('map-results-handle')), const Offset(0, -230));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('map-result-145')), findsOneWidget);
    expect(find.byKey(const ValueKey('map-result-147')), findsNothing);
    properties.respond = (_, __) async => ([listing(146, 14.55)], false);
    final retry = find.text('إعادة المحاولة');
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(pins, [146]);
    expect(tester.widget<Text>(find.byKey(countKey)).data, '١ نتيجة');
    expect(staleCount, findsNothing);
    expect(properties.calls[properties.calls.length - 2], properties.calls.last);

    properties.respond = (_, __) async => throw DioException(
      requestOptions: request, type: DioExceptionType.badResponse,
      response: Response<void>(requestOptions: request, statusCode: 403));
    await scope.read(marketplaceMapResultsProvider.notifier).search();
    await tester.pumpAndSettle();
    expect(pins, isEmpty);
    expect(tester.widget<Text>(find.byKey(countKey)).data, '٠ نتيجة');
    expect(staleCount, findsNothing);
    await closeUx(tester);
  });

  test('governorate camera hint follows the requested registry entry without changing explicit user bounds', () {
    const home = HomeLocation(latitude: 15.3, longitude: 44.2, governorate: 'صنعاء', label: 'صنعاء');
    const dhamar = HomeLocation(latitude: 14.5428, longitude: 44.4051, governorate: 'ذمار', governorateCode: 'DH', label: 'ذمار');
    final requested = SmartSearchFilters.fromMap({'governorate': 'ذمار', 'governorate_code': 'DH'});
    expect(mapSearchInitialCamera(requested, home, [dhamar])!.latitude, 14.5428);
    expect(requested.values.containsKey('radius_km'), isFalse);
    expect(mapSearchInitialCamera(SmartSearchFilters.fromMap({
      ...requested.values, 'south': 14, 'west': 44, 'north': 15, 'east': 45,
    }), home, [dhamar]), isNull);
    expect(mapSearchInitialCamera(SmartSearchFilters.fromMap({'governorate_code': 'UNKNOWN'}), home, [dhamar]), isNull);
  });

  testWidgets('editable map price bounds retain pending Arabic input through currency selection and clear one bound atomically', (tester) async {
    final scope = uxContainer(extra: [propertyRepositoryProvider.overrideWithValue(Listings())]);
    final controller = scope.read(marketplaceSearchControllerProvider.notifier);
    controller.applyFilters(SmartSearchFilters.fromMap({
      'purpose': 'rent', 'type': 'apartment', 'currency': 'USD', 'max_price': 500000,
    }));
    controller.enterMap();
    final home = scope.read(marketplaceSearchControllerProvider).criteria;
    await pumpUx(tester, scope, const Scaffold(body: SingleChildScrollView(
      child: MarketplaceSearchPanel(onMap: true))));
    expect(find.byKey(const ValueKey('filter-min_price')), findsNothing);
    await _tap(tester, 'published-map-filters');
    final minimum = find.byKey(const ValueKey('filter-min_price'));
    final maximum = find.byKey(const ValueKey('filter-max_price'));
    await tester.enterText(minimum, '١٢٥٬٠٠٠٫٥');
    await tester.enterText(maximum, '٢٥٠٬٠٠٠');
    await _tap(tester, 'filter-min_bedrooms-3');
    expect(tester.widget<TextField>(minimum).controller!.text, '١٢٥٬٠٠٠٫٥');
    expect(tester.widget<TextField>(maximum).controller!.text, '٢٥٠٬٠٠٠');
    await _tap(tester, 'filter-currency');
    await tester.tap(find.text('ريال سعودي').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('تطبيق الشروط'));
    await tester.tap(find.text('تطبيق الشروط'));
    await tester.pumpAndSettle();
    expect(controller.uiFor(onMap: true).criteria.values, containsPair('min_price', 125000.5));
    expect(controller.uiFor(onMap: true).criteria.values, containsPair('max_price', 250000));
    expect(controller.uiFor(onMap: true).criteria.values, containsPair('currency', 'SAR'));
    expect(controller.uiFor(onMap: true).criteria.values, containsPair('min_bedrooms', 3));
    expect(scope.read(marketplaceSearchControllerProvider).criteria.sameAs(home), isTrue);
    await _tap(tester, 'published-map-filters');
    await tester.enterText(maximum, '');
    await _tap(tester, 'filter-apply');
    expect(controller.uiFor(onMap: true).criteria.values.containsKey('max_price'), isFalse);
    expect(controller.uiFor(onMap: true).criteria.values['min_price'], 125000.5);
    expect(tester.takeException(), isNull);
    await closeUx(tester);
  });

  testWidgets('invalid or reversed price bounds cannot replace the accepted map budget', (tester) async {
    final scope = uxContainer(extra: [propertyRepositoryProvider.overrideWithValue(Listings())]);
    final controller = scope.read(marketplaceSearchControllerProvider.notifier);
    controller.enterMap(filters: SmartSearchFilters.fromMap({'min_price': 100, 'max_price': 200}));
    await pumpUx(tester, scope, const Scaffold(body: SingleChildScrollView(
      child: MarketplaceSearchPanel(onMap: true))));
    await _tap(tester, 'published-map-filters');
    final original = controller.uiFor(onMap: true).criteria;
    final minimum = find.byKey(const ValueKey('filter-min_price'));
    for (final invalid in ['-1', 'Infinity', '١٠٠٠٠٠٠٠٠٠٠٠١']) {
      await tester.ensureVisible(minimum);
      await tester.enterText(minimum, invalid);
      await _tap(tester, 'filter-apply');
      expect(find.byKey(const ValueKey('filter-validation-error')), findsOneWidget);
      expect(controller.uiFor(onMap: true).criteria.sameAs(original), isTrue);
    }
    await tester.ensureVisible(minimum);
    await tester.enterText(minimum, '٣٠٠');
    await _tap(tester, 'filter-apply');
    expect(find.text('الحد الأدنى يجب ألا يتجاوز الحد الأعلى.'), findsOneWidget);
    expect(controller.uiFor(onMap: true).criteria.sameAs(original), isTrue);
    expect(tester.takeException(), isNull);
    await closeUx(tester);
  });

  for (final (resolution, density, scale, keyboard) in [
    (const Size(1080, 1920), 420, 1.0, 0.0),
    (const Size(720, 1280), 360, 1.8, 496.0),
  ]) {
    testWidgets('rejected price remains readable with both values at ${resolution.width.toInt()}px density $density', (tester) async {
      final properties = Listings();
      final scope = uxContainer(extra: [
        propertyRepositoryProvider.overrideWithValue(properties),
        sharedSearchMapBuilderProvider.overrideWithValue((_, __, ___, ____) => const ColoredBox(color: Colors.teal)),
      ]);
      final owner = scope.read(marketplaceSearchControllerProvider.notifier);
      owner.applyFilters(SmartSearchFilters.fromMap({'purpose': 'rent', 'min_price': keyboard > 0 ? 177000 : 1000000}));
      final pixelRatio = density / 160;
      tester.view.padding = FakeViewPadding(top: 24 * pixelRatio);
      addTearDown(tester.view.resetPadding);
      await pumpUx(tester, scope, const MarketplaceSearchMapScreen(),
        size: resolution / pixelRatio, devicePixelRatio: pixelRatio, scale: scale);
      await tester.pumpAndSettle();

      await _tap(tester, 'published-map-filters');
      final minimum = find.byKey(const ValueKey('filter-min_price'));
      final maximum = find.byKey(const ValueKey('filter-max_price'));
      await tester.ensureVisible(maximum);
      await tester.tap(maximum);
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.enterText(maximum, '100000');
      if (keyboard == 0) {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
      }
      final previous = scope.read(marketplaceMapResultsProvider);
      final requests = properties.calls.length;
      await _tap(tester, 'filter-apply');
      expect(scope.read(marketplaceMapResultsProvider), same(previous));
      expect(properties.calls.length, requests);

      final error = find.text('الحد الأدنى يجب ألا يتجاوز الحد الأعلى.');
      for (final widget in [minimum, maximum, error]) {
        await tester.ensureVisible(widget);
        await tester.pumpAndSettle();
        final rect = tester.getRect(widget);
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo((resolution.height - keyboard) / pixelRatio + 1));
      }
      for (final field in [minimum, maximum]) {
        final text = find.descendant(of: field, matching: find.byType(EditableText));
        final editor = tester.state<EditableTextState>(text);
        final painter = TextPainter(text: editor.renderEditable.text, textDirection: TextDirection.ltr,
          textScaler: editor.renderEditable.textScaler, maxLines: 1)..layout();
        expect(painter.width + 2, lessThanOrEqualTo(editor.renderEditable.size.width));
        painter.dispose();
      }
      await tester.ensureVisible(maximum);
      await tester.enterText(maximum, '١٠٠٠٠٠٠');
      await _tap(tester, 'filter-apply');
      expect(error, findsNothing);
      expect(owner.uiFor(onMap: true).criteria.values['max_price'], 1000000);
      expect(tester.takeException(), isNull);
      await closeUx(tester);
    });
  }

  for (final dark in [false, true]) {
    testWidgets('360px map keeps price filters usable with keyboard and preserves the dragged results extent dark=$dark', (tester) async {
      final properties = Listings();
      final scope = uxContainer(extra: [propertyRepositoryProvider.overrideWithValue(properties),
        sharedSearchMapBuilderProvider.overrideWithValue((context, rows, pick, viewport) =>
          const ColoredBox(key: ValueKey('map-1820-canvas'), color: Colors.teal)),
      ]);
      await pumpUx(tester, scope, const MarketplaceSearchMapScreen(),
        size: const Size(360, 640), scale: 2.0, dark: dark);
      await tester.pumpAndSettle();
      final canvas = tester.element(find.byKey(const ValueKey('map-1820-canvas')));
      await tester.drag(find.byKey(const ValueKey('map-results-handle')), const Offset(0, -250));
      await tester.pumpAndSettle();
      final sheetFinder = find.byKey(const ValueKey('map-results-sheet'), skipOffstage: false);
      final sheet = tester.element(sheetFinder);
      final extent = tester.widget<DraggableScrollableSheet>(sheetFinder).controller!.size;
      final requests = properties.calls.length;
      await _tap(tester, 'published-map-filters');
      final maximum = find.byKey(const ValueKey('filter-max_price'));
      await tester.ensureVisible(maximum);
      await tester.tap(maximum);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.ensureVisible(maximum);
      await tester.pumpAndSettle();
      final field = tester.getRect(maximum);
      expect(field.top, greaterThanOrEqualTo(0));
      expect(field.bottom, lessThanOrEqualTo(341));
      expect(find.byKey(const ValueKey('map-results-sheet')), findsNothing);
      expect(tester.element(sheetFinder), same(sheet));
      await tester.enterText(maximum, '١٥٠٠٠٠');
      FocusManager.instance.primaryFocus?.unfocus();
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(maximum).controller!.text, '١٥٠٠٠٠');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(maximum, findsNothing);
      expect(tester.element(find.byKey(const ValueKey('map-1820-canvas'))), same(canvas));
      expect(tester.widget<DraggableScrollableSheet>(sheetFinder).controller!.size, closeTo(extent, .001));
      expect(properties.calls.length, requests);
      expect(tester.takeException(), isNull);
      await closeUx(tester);
    });
  }

  testWidgets('compact map toolbar groups the filters and gives the map more room', (tester) async {
    final scope = uxContainer(extra: [propertyRepositoryProvider.overrideWithValue(Listings()),
      sharedSearchMapBuilderProvider.overrideWithValue((_, __, ___, ____) => const ColoredBox(color: Colors.teal)),
    ]);
    await pumpUx(tester, scope, const MarketplaceSearchMapScreen(), size: const Size(360, 640));
    await tester.pumpAndSettle();
    final toolbar = find.byKey(const ValueKey('map-top-search-region'));
    final purpose = find.byKey(const ValueKey('map-search-purpose'));
    final filters = find.byKey(const ValueKey('published-map-filters'));
    final apartment = find.byKey(const ValueKey('published-type-apartment'));
    final house = find.byKey(const ValueKey('published-type-house'));
    final search = find.byKey(const ValueKey('map-open-search'));
    final rentChoice = find.byKey(const ValueKey('published-purpose-rent'));
    final lastType = find.byKey(const ValueKey('published-type-farm'));
    expect(tester.getSize(toolbar).height, lessThan(125));
    expect(tester.getCenter(purpose).dy, closeTo(tester.getCenter(search).dy, 1));
    expect(tester.getCenter(rentChoice).dx, greaterThan(tester.getCenter(search).dx));
    expect(tester.getSize(rentChoice).height, tester.getSize(search).height);
    expect(tester.getCenter(apartment).dy, greaterThan(tester.getCenter(purpose).dy));
    expect(tester.getCenter(filters).dy, closeTo(tester.getCenter(apartment).dy, 1));
    expect(tester.getCenter(filters).dx, lessThan(tester.getCenter(lastType).dx));
    expect(filters.hitTestable(), findsNothing);
    expect(find.byKey(const ValueKey('published-type-all')), findsNothing);
    expect(find.byKey(const ValueKey('map-published-search-input')), findsNothing);
    expect(find.text('البحث على الخريطة'), findsNothing);
    expect(find.byKey(const ValueKey('map-draw-area')).hitTestable(), findsOneWidget);
    expect(find.byKey(const ValueKey('map-smart-search')).hitTestable(), findsOneWidget);
    expect(find.byKey(const ValueKey('map-my-location')).hitTestable(), findsOneWidget);
    expect(find.byKey(const ValueKey('published-filter-min-price')), findsNothing);
    expect(find.byKey(const ValueKey('filter-min_area_m2')), findsNothing);
    final rent = find.descendant(of: purpose, matching: find.widgetWithText(TextButton, 'إيجار'));
    await tester.tap(rent);
    await tester.pumpAndSettle();
    expect(scope.read(marketplaceMapResultsProvider).filters.values['purpose'], 'rent');
    await tester.tap(rent);
    await tester.pumpAndSettle();
    expect(scope.read(marketplaceMapResultsProvider).filters.values.containsKey('purpose'), isFalse);
    Finder selectedGradient(Finder chip) => find.descendant(of: chip, matching: find.byWidgetPredicate(
      (widget) => widget is Ink && widget.decoration is BoxDecoration &&
        (widget.decoration! as BoxDecoration).gradient == EbrokerDesign.propertyTypeSelectionGradient,
    ));
    await _tap(tester, 'published-type-apartment');
    expect(scope.read(marketplaceMapResultsProvider).filters.selectedTypes, ['apartment']);
    expect(selectedGradient(apartment), findsOneWidget);
    expect(selectedGradient(house), findsNothing);
    expect(tester.widget<TextButton>(apartment).style!.foregroundColor!.resolve({}), Colors.white);
    await _tap(tester, 'published-type-house');
    expect(scope.read(marketplaceMapResultsProvider).filters.selectedTypes, ['house']);
    expect(selectedGradient(apartment), findsNothing);
    expect(selectedGradient(house), findsOneWidget);
    await _tap(tester, 'published-type-house');
    expect(scope.read(marketplaceMapResultsProvider).filters.selectedTypes, isEmpty);
    expect(selectedGradient(house), findsNothing);
    await _tap(tester, 'published-map-filters');
    expect(find.byKey(const ValueKey('filter-min_price')), findsOneWidget);
    final area = find.byKey(const ValueKey('filter-min_area_m2'));
    expect(area, findsOneWidget);
    await tester.ensureVisible(area);
    await tester.enterText(area, '١٢٠');
    await _tap(tester, 'filter-apply');
    expect(scope.read(marketplaceMapResultsProvider).filters.apiFilters['min_area_m2'], 120);
    expect(tester.takeException(), isNull);
    await closeUx(tester);
  });

  testWidgets('a pin shows only its preview and a second tap opens that same listing', (tester) async {
    const listing = PropertySummary(id: 77, title: 'شقة للإيجار', type: 'apartment',
      purpose: 'rent', price: 120000, currency: 'YER', latitude: 15.4, longitude: 44.2);
    final properties = Listings()..respond = (_, __) async => ([listing], false);
    late void Function(int) select;
    final scope = uxContainer(extra: [
      propertyRepositoryProvider.overrideWithValue(properties),
      sharedSearchMapBuilderProvider.overrideWithValue((_, __, pick, ___) {
        select = pick;
        return const ColoredBox(color: Colors.teal);
      }),
    ]);
    final navigation = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const MarketplaceSearchMapScreen()),
      GoRoute(path: '/properties/:id', builder: (_, state) => Scaffold(appBar: AppBar(),
        body: Text('تفاصيل ${state.pathParameters['id']}'))),
    ]);
    addTearDown(navigation.dispose);
    await pumpUx(tester, scope, const SizedBox(), router: navigation, size: const Size(360, 640));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('map-broker-add')), findsNothing);
    select(listing.id);
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('map-marker-preview-77'));
    expect(card.hitTestable(), findsOneWidget);
    expect(find.byKey(const ValueKey('map-results-list')), findsNothing);
    expect(find.text('تفاصيل 77'), findsNothing);
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.text('تفاصيل 77'), findsOneWidget);
    navigation.pop();
    await tester.pumpAndSettle();
    expect(card.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await closeUx(tester);
  });

  testWidgets('the map add action follows publishing eligibility and respects RTL order', (tester) async {
    final auth = UxAuth(uxUser(type: 'broker'));
    final scope = uxContainer(auth: auth, extra: [
      propertyRepositoryProvider.overrideWithValue(Listings()),
      sharedSearchMapBuilderProvider.overrideWithValue((_, __, ___, ____) => const SizedBox.expand()),
    ]);
    await pumpUx(tester, scope, const MarketplaceSearchMapScreen());
    await tester.pumpAndSettle();
    final add = find.byKey(const ValueKey('map-broker-add'));
    final count = find.byKey(const ValueKey('map-results-count'));
    final list = find.byKey(const ValueKey('map-show-list'));
    expect(tester.getCenter(add).dx, lessThan(tester.getCenter(count).dx));
    expect(tester.getCenter(count).dx, lessThan(tester.getCenter(list).dx));
    auth.change(uxUser(type: 'owner'));
    await tester.pumpAndSettle();
    expect(add, findsOneWidget);
    auth.change(null);
    await tester.pumpAndSettle();
    expect(add, findsNothing);
    await closeUx(tester);
  });

  testWidgets('a viewport delivered during the map pop transition cannot revive the ended child journey', (tester) async {
    final properties = Listings();
    void Function(double, double, double, double)? viewport;
    final scope = uxContainer(extra: [propertyRepositoryProvider.overrideWithValue(properties),
      sharedSearchMapBuilderProvider.overrideWithValue((context, rows, pick, updateViewport) {
        viewport = updateViewport;
        return const ColoredBox(color: Colors.teal);
      }),
    ]);
    final navigation = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('الرئيسية'))),
      GoRoute(path: '/map', builder: (_, __) => const MarketplaceSearchMapScreen()),
    ]);
    addTearDown(navigation.dispose);
    await pumpUx(tester, scope, const SizedBox(), router: navigation);
    unawaited(navigation.push<void>('/map'));
    await tester.pumpAndSettle();
    final controller = scope.read(marketplaceSearchControllerProvider.notifier);
    final token = controller.mapJourneyToken;
    final lateViewport = viewport!;
    final requests = properties.calls.length;
    navigation.pop();
    expect(controller.isMapJourneyCurrent(token), isFalse);
    // Deliver before pumping/disposal: the old native child is still mounted.
    lateViewport(14, 43, 15, 44);
    expect(properties.calls.length, requests);
    await tester.pumpAndSettle();
    expect(scope.read(marketplaceMapResultsProvider).filters.values.containsKey('south'), isFalse);
    expect(scope.read(marketplaceSearchControllerProvider).criteria.values, isEmpty);
    expect(tester.takeException(), isNull);
    await closeUx(tester);
  });

  testWidgets('opening property details above an embedded map retains its child scope until the actual tab exit', (tester) async {
    final scope = uxContainer(extra: [propertyRepositoryProvider.overrideWithValue(Listings()),
      sharedSearchMapBuilderProvider.overrideWithValue((context, rows, pick, viewport) =>
        const ColoredBox(color: Colors.teal)),
    ]);
    final navigation = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const MarketplaceSearchMapScreen(embedded: true)),
      GoRoute(path: '/properties/:id', builder: (_, __) => Scaffold(
        appBar: AppBar(), body: const Text('تفاصيل فوق الخريطة'))),
    ]);
    addTearDown(navigation.dispose);
    await pumpUx(tester, scope, const SizedBox(), router: navigation);
    await tester.pumpAndSettle();
    final controller = scope.read(marketplaceSearchControllerProvider.notifier);
    controller.setChoice('type', 'house', onMap: true);
    scope.read(marketplaceMapResultsProvider.notifier).updateViewport(south: 15, west: 44, north: 16, east: 45);
    await tester.pumpAndSettle();
    final token = controller.mapJourneyToken;
    final filters = scope.read(marketplaceMapResultsProvider).filters;
    await tester.drag(find.byKey(const ValueKey('map-results-handle')), const Offset(0, -300));
    await tester.pumpAndSettle();
    final property = find.byKey(const ValueKey('map-result-1'));
    await tester.ensureVisible(property);
    await tester.tap(property);
    await tester.pumpAndSettle();
    expect(find.text('تفاصيل فوق الخريطة'), findsOneWidget);
    expect(controller.isMapJourneyCurrent(token), isTrue);
    navigation.pop();
    await tester.pumpAndSettle();
    expect(controller.isMapJourneyCurrent(token), isTrue);
    expect(scope.read(marketplaceMapResultsProvider).filters.sameAs(filters), isTrue);
    expect(scope.read(marketplaceSearchControllerProvider).criteria.values, isEmpty);
    expect(tester.takeException(), isNull);
    await closeUx(tester);
  });

  testWidgets('leaving a retained embedded map disposes its camera, rejects a late viewport and starts a fresh map from Home', (tester) async {
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    final properties = Listings();
    var instances = 0, disposed = 0;
    void Function(double, double, double, double)? viewport;
    final scope = uxContainer(extra: [propertyRepositoryProvider.overrideWithValue(properties),
      sharedSearchMapBuilderProvider.overrideWithValue((context, rows, pick, updateViewport) {
        viewport = updateViewport;
        return _MapLifetimeCanvas(onMount: () => instances++, onUnmount: () => disposed++);
      }),
    ]);
    final controller = scope.read(marketplaceSearchControllerProvider.notifier);
    controller.applyFilters(SmartSearchFilters.fromMap({'type': 'house'}));
    await pumpUx(tester, scope, ValueListenableBuilder<bool>(valueListenable: visible,
      builder: (context, enabled, child) => MarketplaceSearchMapScreen(embedded: true, active: enabled)));
    await tester.pumpAndSettle();
    expect(instances, 1);
    final firstToken = controller.mapJourneyToken;
    controller.setChoice('max_price', 100, onMap: true);
    await tester.pumpAndSettle();
    final lateViewport = viewport!;
    visible.value = false;
    await tester.pumpAndSettle();
    expect(controller.isMapJourneyCurrent(firstToken), isFalse);
    expect(disposed, 1);
    expect(find.byType(MapScreen), findsNothing);
    final requests = properties.calls.length;
    final revision = scope.read(marketplaceMapResultsProvider).revision;
    lateViewport(14, 43, 15, 44);
    await tester.pumpAndSettle();
    expect(properties.calls.length, requests);
    expect(scope.read(marketplaceMapResultsProvider).revision, revision);
    expect(scope.read(marketplaceMapResultsProvider).filters.values.containsKey('south'), isFalse);
    expect(scope.read(marketplaceSearchControllerProvider).criteria.values, {'type': 'house'});
    controller.applyFilters(SmartSearchFilters.fromMap({'type': 'land'}));
    visible.value = true;
    await tester.pumpAndSettle();
    expect(instances, 2);
    expect(controller.mapJourneyToken, greaterThan(firstToken));
    expect(controller.uiFor(onMap: true).criteria.values['type'], 'land');
    expect(controller.uiFor(onMap: true).criteria.values.containsKey('max_price'), isFalse);
    expect(scope.read(marketplaceMapResultsProvider).filters.values.containsKey('south'), isFalse);
    expect(tester.takeException(), isNull);
    await closeUx(tester);
  });

  testWidgets('very short keyboard viewport retains hidden results without a layout overflow', (tester) async {
    final scope = uxContainer(extra: [propertyRepositoryProvider.overrideWithValue(Listings()),
      sharedSearchMapBuilderProvider.overrideWithValue((context, rows, pick, viewport) =>
        const ColoredBox(key: ValueKey('map-1820-short-canvas'), color: Colors.teal)),
    ]);
    await pumpUx(tester, scope, const MarketplaceSearchMapScreen(), size: const Size(360, 360), scale: 2.4);
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 200);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('map-results-sheet')), findsNothing);
    expect(find.byKey(const ValueKey('map-results-sheet'), skipOffstage: false), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('map-1820-short-canvas'))).height, greaterThan(0));
    expect(tester.takeException(), isNull);
    await closeUx(tester);
  });
}

import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/widgets/app_components.dart';
import 'package:real_estate_mobile/core/widgets/ebroker_widgets.dart';
import 'package:real_estate_mobile/core/widgets/property_card_gallery.dart';
import 'package:real_estate_mobile/core/widgets/property_type_icon.dart';
import 'package:go_router/go_router.dart';
import 'package:real_estate_mobile/features/broker/domain/broker_models.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_search_session.dart';
import 'package:real_estate_mobile/features/discovery/presentation/marketplace_home_screen.dart';
import 'package:real_estate_mobile/features/discovery/presentation/marketplace_search_screen.dart';
import 'package:real_estate_mobile/features/discovery/presentation/marketplace_search_panel.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_summary_card.dart';
import 'support/owner_ux_fixtures.dart';
import 'support/wave3_fakes.dart';
import 'wave2_home_search_test.dart' show Listings, PageResult, row;

void main() {
  setUpAll(loadUxFixtures);

  test('A03 B06 a changed query or purpose clears old rows before an HTTP response', () async {
    final pending = Completer<PageResult>();
    final listings = Listings();
    final scope = uxContainer(extra: [propertyRepositoryProvider.overrideWithValue(listings)]);
    final controller = scope.read(marketplaceSearchControllerProvider.notifier);
    controller.edit('شقة'); await controller.submit();
    expect(scope.read(homeSearchResultsProvider).rows, isNotEmpty);
    listings.respond = (_, __) => pending.future;
    controller.edit('بيت'); final next = controller.submit();
    expect(scope.read(homeSearchResultsProvider).rows, isEmpty);
    expect(scope.read(homeSearchResultsProvider).filters.values['search'], 'بيت');
    pending.complete(([row(20, title: 'بيت')], false)); await next;
    final purposeReply = Completer<PageResult>();
    listings.respond = (_, __) => purposeReply.future;
    controller.choosePurpose('rent');
    expect(scope.read(homeSearchResultsProvider).rows, isEmpty);
    expect(listings.calls.last['purpose'], 'rent');
    expect(controller.suggestionFilters().values['purpose'], 'rent');
    purposeReply.complete(([row(21, purpose: 'rent')], false));
    await Future<void>.delayed(Duration.zero);
    expect(scope.read(homeSearchResultsProvider).rows.single.purpose, 'rent');
  });

  test('B03 B07 older-server compatibility uses real server-filtered public requests and scoped cache', () async {
    final calls = <RequestOptions>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://synthetic.example/api'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      calls.add(request);
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: request.path == '/marketplace'
        ? {'data': {'context': {'label': 'صنعاء', 'governorate': 'صنعاء'}, 'sections': {
          'latest': [{'id': 99, 'title': 'sale must never be displayed', 'purpose': 'sale'}]}, 'brokers': []}}
        : {'data': [{'id': request.queryParameters['spotlight'] == 1 ? 1 : 2,
          'title': 'عقار للإيجار', 'purpose': request.queryParameters['purpose'], 'price': 100000,
          'currency': 'YER', 'latitude': 15.36, 'longitude': 44.19}]}));
    }));
    addTearDown(() => dio.close(force: true));
    final repository = MarketplaceRepository(dio);
    const query = HomeFeedQuery(latitude: 15.36, longitude: 44.19, governorate: 'صنعاء', type: null, purpose: 'rent', device: false);
    final feed = await repository.feed(query);
    expect(calls, hasLength(3));
    expect(calls.skip(1).every((call) => call.path == '/properties' && call.queryParameters['purpose'] == 'rent'), isTrue);
    expect(feed.sections.values.expand((value) => value).every((row) => row.purpose == 'rent'), isTrue);
    expect(feed.sections.values.expand((value) => value).any((row) => row.id == 99), isFalse);
    await repository.feed(query); expect(calls, hasLength(3));
    final sale = HomeFeedQuery(latitude: query.latitude, longitude: query.longitude, governorate: query.governorate,
      type: query.type, purpose: 'sale', device: false);
    await repository.feed(sale); expect(calls, hasLength(6));
  });

  test('B06 a late rent reply cannot replace a faster explicit sale selection', () async {
    final rent = Completer<PageResult>(), sale = Completer<PageResult>();
    final listings = Listings();
    final scope = uxContainer(extra: [propertyRepositoryProvider.overrideWithValue(listings)]);
    final controller = scope.read(marketplaceSearchControllerProvider.notifier);
    controller.edit('عقار'); await controller.submit();
    listings.respond = (filters, _) => filters['purpose'] == 'rent' ? rent.future : sale.future;
    controller.choosePurpose('rent'); controller.choosePurpose('sale');
    expect(listings.transfers[listings.transfers.length - 2]!.isCancelled, isTrue);
    sale.complete(([row(42, purpose: 'sale')], false)); await Future<void>.delayed(Duration.zero);
    rent.complete(([row(41, purpose: 'rent')], false)); await Future<void>.delayed(Duration.zero);
    expect(scope.read(homeSearchResultsProvider).rows.single.id, 42);
    expect(scope.read(homeSearchResultsProvider).filters.values['purpose'], 'sale');
    expect(scope.read(marketplaceSearchControllerProvider).criteria.values['purpose'], 'sale');
  });

  for (final scale in [1.0, 2.4]) {
    testWidgets('A01 A02 A04 A03 one standalone route, back, IME and edited query at scale $scale', (tester) async {
      final listings = Listings(), boundary = GlobalKey();
      final scope = uxContainer(extra: [propertyRepositoryProvider.overrideWithValue(listings)]);
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => const MarketplaceHomeScreen()),
        GoRoute(path: '/marketplace-search', builder: (_, __) => const MarketplaceSearchScreen()),
        GoRoute(path: '/marketplace-search-map', builder: (_, __) => const MarketplaceSearchMapScreen()),
      ]);
      addTearDown(router.dispose);
      await pumpUx(tester, scope, const SizedBox(), router: router, scale: scale,
        size: scale == 1 ? const Size(412, 820) : const Size(320, 568), boundary: boundary);
      await uxPreview(tester, boundary, 'w3-two-home-$scale');
      await tester.tap(find.byKey(const ValueKey('home-search')));
      await tester.tap(find.byKey(const ValueKey('home-search')), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/marketplace-search');
      expect(find.byType(MarketplaceSearchScreen), findsOneWidget);
      final input = find.byKey(const ValueKey('home-search'));
      await tester.enterText(input, 'شقة');
      await tester.testTextInput.receiveAction(TextInputAction.search); await tester.pumpAndSettle();
      expect(listings.calls, hasLength(1));
      await tester.ensureVisible(input); await tester.enterText(input, 'بيت'); await tester.pump();
      expect(find.byKey(const ValueKey('home-result-1')), findsNothing);
      expect(find.text('نتائج «شقة»'), findsNothing);
      await uxPreview(tester, boundary, 'w3-two-search-edit-$scale');
      await tester.tap(find.byKey(const ValueKey('marketplace-search-back'))); await tester.pumpAndSettle();
      expect(router.state.uri.path, '/');
      expect(tester.takeException(), isNull); await closeUx(tester);
    });
  }

  for (final scale in [1.0, 2.4]) {
    testWidgets('Home keeps category choices, live broker details and the property feed at $scale', (tester) async {
      final boundary = GlobalKey();
      final fake = Wave3MarketplaceFake(onFeed: (query) async => MarketplaceFeed(label: 'صنعاء',
        brokers: const [BrokerProfile(id: 7, name: 'دلال اختبار 1393', type: 'broker', verified: true,
          rating: 4.8, ratingCount: 12, completedDeals: 3, activeListings: 7)],
        sections: {'latest': [row(11, purpose: query.purpose ?? 'rent'), row(12, purpose: query.purpose ?? 'rent')]},
        sectionOrder: const ['latest']));
      final scope = uxContainer(extra: [marketplaceRepositoryProvider.overrideWithValue(fake)]);
      await pumpUx(tester, scope, const MarketplaceHomeScreen(), scale: scale,
        size: scale == 1 ? const Size(412, 820) : const Size(320, 700), boundary: boundary);
      expect(find.byType(EbrokerCategoryCard), findsWidgets);
      expect(find.byWidgetPredicate((w) => w.runtimeType.toString().startsWith('EbrokerHome')), findsNothing);
      expect(find.byKey(const ValueKey('home-purpose-sale')), findsNothing);
      expect(find.byKey(const ValueKey('home-map')), findsNothing);
      expect(find.byKey(const ValueKey('home-filters')), findsNothing);
      expect(find.byKey(const ValueKey('home-smart-search')), findsNothing);
      expect(find.byKey(const ValueKey('floating-map-search')).hitTestable(), findsOneWidget);
      expect(find.byKey(const ValueKey('floating-smart-search')).hitTestable(), findsOneWidget);
      final apartments = find.byWidgetPredicate((widget) =>
        widget is EbrokerCategoryCard && widget.label == 'شقق');
      final apartmentFill = find.descendant(of: apartments, matching: find.byType(AnimatedContainer));
      final apartmentName = find.descendant(of: apartments, matching: find.byType(EbrokerText));
      final apartmentIcon = find.descendant(of: apartments, matching: find.byType(PropertyTypeIcon));
      final scheme = Theme.of(tester.element(apartments)).colorScheme;
      expect((tester.widget<AnimatedContainer>(apartmentFill).decoration! as BoxDecoration).color, scheme.surface);
      expect(tester.widget<EbrokerText>(apartmentName).color, scheme.onSurface);
      expect(tester.widget<PropertyTypeIcon>(apartmentIcon).color, scheme.primary);
      expect(tester.getSize(apartments).height, greaterThanOrEqualTo(48));
      expect(tester.widget<Text>(find.text('ماذا تبحث عنه؟')).style!.fontSize, 17);
      await tester.ensureVisible(apartments);
      await tester.tap(apartments);
      await tester.pumpAndSettle();
      expect(tester.widget<EbrokerCategoryCard>(apartments).selected, isTrue);
      expect((tester.widget<AnimatedContainer>(apartmentFill).decoration! as BoxDecoration).color, const Color(0xFF008052));
      expect(tester.widget<EbrokerText>(apartmentName).color, Colors.white);
      expect(tester.widget<PropertyTypeIcon>(apartmentIcon).color, Colors.white);
      scope.read(marketplaceSearchControllerProvider.notifier).choosePurpose('sale');
      await tester.pumpAndSettle();
      expect(fake.queries.last.purpose, 'sale');
      expect(scope.read(marketplaceSearchControllerProvider).criteria.values['purpose'], 'sale');
      final home = find.descendant(of: find.byKey(const PageStorageKey('marketplace-home')), matching: find.byType(Scrollable)).first;
      final broker = find.byKey(const ValueKey('home-broker-7'));
      await tester.scrollUntilVisible(broker, 200, scrollable: home);
      expect(find.descendant(of: broker, matching: find.text('دلال اختبار 1393')), findsOneWidget);
      expect(find.descendant(of: broker, matching: find.textContaining('3 صفقات مؤكدة')), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is Hero && w.tag == 'agent-hero-7'), findsNothing);
      await uxPreview(tester, boundary, 'w3-two-broker-$scale');
      final first = find.byKey(const ValueKey('home-property-11'));
      await tester.scrollUntilVisible(first, 250, scrollable: home);
      final card = tester.widget<PropertySummaryCard>(first);
      expect(card.property.purpose, 'sale');
      expect(card.imageFirst, isTrue);
      expect(card.preview, isTrue);
      final purpose = find.descendant(of: first, matching: find.byKey(const ValueKey('property-price-purpose')));
      final price = find.descendant(of: first, matching: find.byType(AppPropertyPrice));
      final gallery = find.descendant(of: first, matching: find.byType(PropertyCardGallery));
      expect(find.descendant(of: purpose, matching: find.text('بيع')), findsOneWidget);
      expect(tester.getRect(purpose).right, lessThan(tester.getRect(price).left));
      expect(tester.getRect(purpose).top, greaterThan(tester.getRect(gallery).bottom));
      expect(find.descendant(of: first, matching: find.byKey(const ValueKey('property-photo-price'))), findsNothing);
      expect(find.descendant(of: first, matching: find.byKey(const ValueKey('compare-property-11'))), findsNothing);
      await uxPreview(tester, boundary, 'w3-two-cards-$scale');
      expect(tester.takeException(), isNull); await closeUx(tester);
    });
  }

  testWidgets('weekly brokers follow the search row, advance and support an RTL swipe', (tester) async {
    final feed = Wave3MarketplaceFake(onFeed: (_) async => const MarketplaceFeed(
      label: 'ذمار',
      sectionOrder: [],
      brokers: [
        BrokerProfile(id: 7, name: 'دلال الاختبار الأول', type: 'broker', verified: true,
          rating: 4.8, ratingCount: 12, completedDeals: 3, activeListings: 7),
        BrokerProfile(id: 8, name: 'دلال الاختبار الثاني', type: 'broker', verified: true,
          rating: 4.8, ratingCount: 12, completedDeals: 3, activeListings: 7),
      ],
    ));
    final scope = uxContainer(extra: [marketplaceRepositoryProvider.overrideWithValue(feed)]);
    await pumpUx(tester, scope, const MarketplaceHomeScreen(), size: const Size(412, 820));
    await tester.pumpAndSettle();
    final rail = find.byKey(const ValueKey('home-weekly-brokers'));
    final controller = tester.widget<PageView>(rail).controller!;
    final search = find.byKey(const ValueKey('home-search'));
    expect(tester.getTopLeft(rail).dy, greaterThan(tester.getBottomLeft(search).dy));
    expect(tester.getSize(rail).height, 92);
    final brokerName = find.descendant(of: rail, matching: find.text('دلال الاختبار الأول'));
    expect(tester.widget<Text>(brokerName).style!.fontSize, 17);
    expect(controller.page, 1);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(controller.page, 2);
    await tester.drag(rail, const Offset(280, 0));
    await tester.pumpAndSettle();
    expect(controller.page, 1);
    expect(tester.takeException(), isNull);
    await closeUx(tester);
  });

  testWidgets('Home search, assistant and heading retain readable contrast on dark narrow screens', (tester) async {
    final scope = uxContainer(), boundary = GlobalKey();
    await pumpUx(tester, scope, const MarketplaceHomeScreen(), dark: true,
      size: const Size(320, 700), scale: 2.4, boundary: boundary);
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
    }
    final field = tester.widget<TextField>(find.byKey(const ValueKey('home-search')));
    expect(contrast(field.decoration!.hintStyle!.color!, field.decoration!.fillColor!), greaterThan(4.5));
    expect(find.byKey(const ValueKey('home-purpose-rent')), findsNothing);
    final assistant = find.byKey(const ValueKey('floating-smart-search'));
    final colors = Theme.of(tester.element(assistant)).colorScheme;
    expect(contrast(colors.primary, colors.surface), greaterThan(4.5));
    final heading = find.text('ماذا تبحث عنه؟');
    final headingColor = DefaultTextStyle.of(tester.element(heading)).style.color!;
    final canvas = tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor!;
    expect(contrast(headingColor, canvas), greaterThan(4.5));
    expect(canvas.computeLuminance(), lessThan(.1));
    await uxPreview(tester, boundary, 'w3-two-upper-dark-large');
    expect(tester.takeException(), isNull); await closeUx(tester);
  });
}

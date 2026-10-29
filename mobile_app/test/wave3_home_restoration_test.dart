import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:real_estate_mobile/core/widgets/ebroker_home/image_swiper.dart';
import 'package:real_estate_mobile/core/widgets/ebroker_home/property_card_big.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_search_session.dart';
import 'package:real_estate_mobile/features/discovery/presentation/marketplace_home_screen.dart';
import 'package:real_estate_mobile/features/discovery/presentation/marketplace_search_screen.dart';
import 'package:real_estate_mobile/features/discovery/presentation/marketplace_search_panel.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
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
    const query = (latitude: 15.36, longitude: 44.19, governorate: 'صنعاء', type: null, purpose: 'rent', device: false);
    final feed = await repository.feed(query);
    expect(calls, hasLength(3));
    expect(calls.skip(1).every((call) => call.path == '/properties' && call.queryParameters['purpose'] == 'rent'), isTrue);
    expect(feed.sections.values.expand((value) => value).every((row) => row.purpose == 'rent'), isTrue);
    expect(feed.sections.values.expand((value) => value).any((row) => row.id == 99), isFalse);
    await repository.feed(query); expect(calls, hasLength(3));
    final sale = (latitude: query.latitude, longitude: query.longitude, governorate: query.governorate,
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
      await uxPreview(tester, boundary, 'w3-home-$scale');
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
      await uxPreview(tester, boundary, 'w3-search-edit-$scale');
      await tester.tap(find.byKey(const ValueKey('marketplace-search-back'))); await tester.pumpAndSettle();
      expect(router.state.uri.path, '/');
      expect(tester.takeException(), isNull); await closeUx(tester);
    });
  }

  testWidgets('B05 source galleries, unique home cards and purpose survive navigation', (tester) async {
    final properties = [row(1), row(2)];
    final fake = Wave3MarketplaceFake(onFeed: (query) async => MarketplaceFeed(label: 'صنعاء',
      sections: {'spotlight': properties, 'latest': properties}, sectionOrder: const ['spotlight', 'latest']));
    final scope = uxContainer(extra: [marketplaceRepositoryProvider.overrideWithValue(fake)]);
    await pumpUx(tester, scope, const MarketplaceHomeScreen());
    await tester.tap(find.byKey(const ValueKey('home-purpose-rent'))); await tester.pumpAndSettle();
    expect(fake.queries.last.purpose, 'rent');
    expect(scope.read(marketplaceSearchControllerProvider).criteria.values['purpose'], 'rent');
    await tester.scrollUntilVisible(find.byType(EbrokerHomePropertyCard).first, 250,
      scrollable: find.descendant(of: find.byKey(const PageStorageKey('marketplace-home')), matching: find.byType(Scrollable)).first);
    expect(find.byKey(const ValueKey('home-property-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-property-2')), findsOneWidget);
    expect(tester.takeException(), isNull); await closeUx(tester);
  });

  testWidgets('C03 source loop and animated dots move through actual public image pages', (tester) async {
    final scope = uxContainer();
    await pumpUx(tester, scope, const Scaffold(body: SizedBox(width: 300, child: EbrokerHomeImageSwiper(
      images: ['https://synthetic.example/1.jpg', 'https://synthetic.example/2.jpg', 'https://synthetic.example/3.jpg'],
      heroTag: 'acceptance', width: 300, height: 150, borderRadius: BorderRadius.all(Radius.circular(4))))));
    expect(tester.widget<ScrollingDotsIndicator>(find.byType(ScrollingDotsIndicator)).currentIndex, 0);
    await tester.drag(find.byType(PageView), const Offset(240, 0)); await tester.pumpAndSettle();
    expect(tester.widget<ScrollingDotsIndicator>(find.byType(ScrollingDotsIndicator)).currentIndex, 1);
    expect(tester.takeException(), isNull); await closeUx(tester);
  });
}

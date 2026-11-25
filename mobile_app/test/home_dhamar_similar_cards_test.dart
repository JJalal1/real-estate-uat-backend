import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:real_estate_mobile/core/widgets/ebroker_widgets.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_search_session.dart';
import 'package:real_estate_mobile/features/discovery/domain/smart_search_filters.dart';
import 'package:real_estate_mobile/features/discovery/presentation/marketplace_home_screen.dart';
import 'package:real_estate_mobile/features/discovery/presentation/marketplace_section_screen.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_compare_actions.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_details_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_summary_card.dart';

import 'support/owner_ux_fixtures.dart';
import 'support/wave3_fakes.dart';

void main() {
  setUpAll(loadUxFixtures);

  test('Dhamar sample chooses from the full public inventory and keeps filters', () async {
    final calls = <RequestOptions>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://synthetic.example/api'));
    addTearDown(() => dio.close(force: true));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      calls.add(request);
      final page = request.queryParameters['page'];
      handler.resolve(Response(requestOptions: request, statusCode: 200,
        headers: Headers.fromMap({'X-Aqer-Filter-Contract': ['2']}), data: {
          'data': [
            for (final id in page == 1 ? [1, 2, 3, 4, 5, 6] : [13, 14])
              {'id': id, 'status': id == 14 ? 'draft' : 'published'},
          ],
          'meta': {'current_page': page, 'last_page': 3, 'total': 14},
        }));
    }));
    final repository = MarketplaceRepository(dio, random: _LastPageRandom());
    final sample = await repository.dhamarPreview(
      SmartSearchFilters.fromMap({'type': 'apartment', 'purpose': 'rent', 'max_price': 150000}),
      cancelToken: CancelToken(),
    );

    expect(calls.map((call) => call.queryParameters['page']), [1, 3]);
    for (final call in calls) {
      expect(call.path, '/properties');
      expect(call.queryParameters, containsPair('governorate', 'ذمار'));
      expect(call.queryParameters, containsPair('governorate_code', 'DHAMAR'));
      expect(call.queryParameters, containsPair('type', 'apartment'));
      expect(call.queryParameters, containsPair('purpose', 'rent'));
      expect(call.queryParameters, containsPair('max_monthly_rent', 150000));
      expect(call.queryParameters, isNot(contains('latitude')));
    }
    expect(sample.map((row) => row.id).toSet(), hasLength(6));
    expect(sample.first.id, 13);
    expect(sample.map((row) => row.id), isNot(contains(14)));
  });

  for (final scenario in [
    (label: 'unselected', location: const HomeLocation(), fallback: true),
    (label: 'unconfirmed GPS', location: const HomeLocation(device: true, governorate: 'إب', needsConfirmation: true), fallback: true),
    (label: 'manual governorate', location: const HomeLocation(governorate: 'إب', governorateCode: 'IBB', manual: true), fallback: false),
    (label: 'resolved GPS', location: const HomeLocation(governorate: 'إب', governorateCode: 'IBB', device: true), fallback: false),
  ]) {
    testWidgets('Home hides the GPS-only section for ${scenario.label} and scopes See all', (tester) async {
      final fallbackQueries = <HomeFeedQuery>[];
      final listings = Wave3PropertiesFake();
      final scope = uxContainer(extra: [
        homeLocationProvider.overrideWith((_) => scenario.location),
        marketplaceRepositoryProvider.overrideWithValue(Wave3MarketplaceFake(onFeed: (_) async => MarketplaceFeed(
          label: 'إب', governorate: 'إب', sections: {
            'latest': [wave3Property(10)],
            'nearby': [wave3Property(20)],
            'sale': [wave3Property(30), wave3Property(31)],
          }, sectionOrder: const ['nearby', 'latest', 'sale'],
        ))),
        marketplaceDhamarPreviewProvider.overrideWith((_, query) async {
          fallbackQueries.add(query);
          return [wave3Property(40), wave3Property(41)];
        }),
        propertyRepositoryProvider.overrideWithValue(listings),
      ]);
      scope.read(marketplaceSearchControllerProvider.notifier).chooseType('apartment');
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => const MarketplaceHomeScreen()),
        GoRoute(path: '/marketplace-section', builder: (_, state) => MarketplaceSectionScreen(
          section: state.uri.queryParameters['section']!,
          governorate: state.uri.queryParameters['governorate'],
          filters: state.extra! as SmartSearchFilters,
        )),
      ]);
      addTearDown(router.dispose);
      await pumpUx(tester, scope, const SizedBox(), router: router);

      final home = find.descendant(of: find.byKey(const PageStorageKey('marketplace-home')),
        matching: find.byType(Scrollable)).first;
      final heading = find.text('بالقرب منك');
      await tester.scrollUntilVisible(heading, 160, scrollable: home);
      expect(find.text('حول موقعك الحالي'), findsNothing);
      expect(find.byKey(const ValueKey('home-property-20')), findsNothing);
      expect(fallbackQueries, hasLength(scenario.fallback ? 1 : 0));
      final rail = find.byKey(PageStorageKey('home-properties-${scenario.fallback ? 'dhamar' : 'sale'}'));
      await Scrollable.ensureVisible(tester.element(rail), alignment: 0.5);
      await tester.pumpAndSettle();
      expect(tester.widget<SingleChildScrollView>(rail).scrollDirection, Axis.horizontal);
      final second = find.descendant(of: rail, matching: find.byKey(ValueKey('home-property-${scenario.fallback ? 41 : 31}')));
      final initialX = tester.getCenter(second).dx;
      await tester.drag(rail, const Offset(235, 0));
      await tester.pumpAndSettle();
      expect(tester.getCenter(second).dx, greaterThan(initialX));

      final title = find.ancestor(of: heading, matching: find.byType(EbrokerTitleHeader));
      final seeAll = find.descendant(of: title, matching: find.text('رؤية الكل'));
      await tester.ensureVisible(seeAll);
      await tester.pumpAndSettle();
      await tester.tap(seeAll);
      await tester.pumpAndSettle();
      expect(router.state.uri.queryParameters['governorate'], scenario.fallback ? 'ذمار' : 'إب');
      expect(router.state.uri.queryParameters['section'], scenario.fallback ? 'regional' : 'sale');
      if (scenario.fallback) expect(find.text('عقارات ذمار'), findsOneWidget);
      expect(listings.queries.last.filters, containsPair('governorate_code', scenario.fallback ? 'DHAMAR' : 'IBB'));
      expect(listings.queries.last.filters, containsPair('type', 'apartment'));
      expect(listings.queries.last.filters['purpose'], scenario.fallback ? isNull : 'sale');
      expect(tester.takeException(), isNull);
      await closeUx(tester);
    });
  }

  for (final scale in [1.0, 2.4]) {
    testWidgets('Similar cards fit their content and retain comparison at text scale $scale', (tester) async {
      final scope = uxContainer(extra: [
        propertyDetailsProvider(1).overrideWith((_) async => PropertyDetails.fromJson({
          'id': 1, 'title': 'عقار الاختبار', 'type': 'apartment', 'purpose': 'sale', 'status': 'published',
          'similar': [
            for (final id in [2, 3]) {
              'id': id, 'title': 'عقار مشابه $id', 'type': 'apartment', 'purpose': 'sale',
              'price': 9000000, 'area_m2': id == 2 ? null : 230, 'bedrooms': id == 2 ? null : 4,
            },
          ],
        })),
      ]);
      await pumpUx(tester, scope, const PropertyDetailsScreen(propertyId: 1),
        size: const Size(320, 660), scale: scale);
      final page = find.descendant(of: find.byKey(const ValueKey('property-details-1')),
        matching: find.byType(Scrollable)).first;
      final compare = find.byKey(const ValueKey('compare-property-2'));
      await tester.scrollUntilVisible(compare, 180, scrollable: page);
      await Scrollable.ensureVisible(tester.element(compare), alignment: 0.5);
      await tester.pumpAndSettle();
      final card = find.ancestor(of: compare, matching: find.byType(PropertySummaryCard));
      final rail = find.byKey(const PageStorageKey('similar-properties-1'));
      if (scale == 1.0) {
        expect(tester.widget<SingleChildScrollView>(rail).scrollDirection, Axis.horizontal);
        expect(tester.getSize(card).height, lessThan(442));
        final scrollable = find.descendant(of: rail, matching: find.byType(Scrollable));
        expect(tester.state<ScrollableState>(scrollable).position.maxScrollExtent, greaterThan(0));
      } else {
        expect(rail, findsNothing);
      }
      expect(tester.getRect(card).bottom - tester.getRect(compare).bottom, inInclusiveRange(0, 20));
      expect(find.byKey(const ValueKey('property-call')), findsOneWidget);
      expect(find.byKey(const ValueKey('property-message')), findsOneWidget);
      await tester.tap(compare);
      await tester.pump();
      expect(scope.read(propertyCompareSelectionProvider), contains(2));
      expect(tester.takeException(), isNull);
      await closeUx(tester);
    });
  }
}

class _LastPageRandom implements Random {
  @override
  int nextInt(int max) => max == 14 ? 13 : 0;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}

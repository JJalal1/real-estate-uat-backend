import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:real_estate_mobile/features/discovery/presentation/marketplace_categories_screen.dart';
import 'package:real_estate_mobile/features/discovery/presentation/marketplace_section_screen.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';

import 'support/owner_ux_fixtures.dart';
import 'wave2_home_search_test.dart' show Listings, row;

void main() {
  setUpAll(loadUxFixtures);

  testWidgets('categories scope requests by purpose and type across pages', (tester) async {
    final listings = Listings();
    listings.respond = (filters, page) async {
      final purpose = filters['purpose'] as String;
      final type = filters['type'] as String;
      return ([row(page, purpose: purpose, type: type)], page == 1);
    };
    final scope = uxContainer(
      extra: [propertyRepositoryProvider.overrideWithValue(listings)],
    );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const MarketplaceCategoriesScreen(),
        ),
        GoRoute(
          path: '/marketplace-categories/:purpose',
          builder: (_, state) => MarketplaceCategoryTypesScreen(
            purpose: state.pathParameters['purpose']!,
          ),
        ),
        GoRoute(
          path: '/marketplace-section',
          builder: (_, state) => MarketplaceSectionScreen(
            section: state.uri.queryParameters['section']!,
            purpose: state.uri.queryParameters['purpose'],
            type: state.uri.queryParameters['type'],
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await pumpUx(tester, scope, const SizedBox(), router: router);

    await tester.tap(find.text('الإيجارات'));
    await tester.pumpAndSettle();
    expect(find.text('مزارع'), findsOneWidget);
    await tester.tap(find.text('شقق'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('section-property-1')), findsOneWidget);
    expect(listings.calls.single, {'purpose': 'rent', 'type': 'apartment', 'page': 1});

    final loadMore = find.text('المزيد من العقارات');
    await tester.ensureVisible(loadMore);
    await tester.tap(loadMore);
    await tester.pumpAndSettle();
    expect(listings.calls.last, {'purpose': 'rent', 'type': 'apartment', 'page': 2});

    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('شقق'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('البيع'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('أراضٍ'));
    await tester.pumpAndSettle();
    expect(find.text('عقارات للبيع'), findsOneWidget);
    expect(listings.calls.last, {'purpose': 'sale', 'type': 'land', 'page': 1});
    expect(tester.takeException(), isNull);
    await closeUx(tester);
  });
}

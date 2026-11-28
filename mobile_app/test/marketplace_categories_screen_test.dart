import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:real_estate_mobile/core/theme/ebroker_design.dart';
import 'package:real_estate_mobile/features/discovery/presentation/marketplace_categories_screen.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_summary_card.dart';

import 'support/owner_ux_fixtures.dart';
import 'wave2_home_search_test.dart' show Listings, PageResult, row;

Finder _type(String type) =>
    find.byKey(ValueKey('marketplace-category-type-$type'));

Finder _purpose(String purpose) =>
    find.byKey(ValueKey('marketplace-category-purpose-$purpose'));

Finder _homeGradient(Finder receiver) => find.descendant(
      of: receiver,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).gradient ==
                EbrokerDesign.propertyTypeSelectionGradient,
      ),
    );

Finder _resultsScroll() => find.descendant(
      of: find.byKey(const ValueKey('marketplace-listing-results')),
      matching: find.byType(Scrollable),
    );

Finder get _filters =>
    find.byKey(const ValueKey('marketplace-category-filters'));
Finder get _rooms =>
    find.byKey(const ValueKey('section-filter-min_bedrooms-3'));
Finder get _parking => find.byKey(const ValueKey('section-filter-has_parking'));
Finder get _majlis =>
    find.byKey(const ValueKey('section-filter-has_separate_majlis'));
Finder get _apply => find.byKey(const ValueKey('section-filter-apply'));

void main() {
  setUpAll(loadUxFixtures);

  testWidgets(
      'all uses the Home selection gradient and a compact, fully tappable filter',
      (tester) async {
    final listings = Listings()
      ..respond = (_, __) async => ([row(10, purpose: 'rent')], false);
    final scope = uxContainer(
      extra: [propertyRepositoryProvider.overrideWithValue(listings)],
    );
    await pumpUx(tester, scope, const MarketplaceCategoriesScreen());

    expect(_homeGradient(_purpose('rent')), findsOneWidget);
    expect(_homeGradient(_purpose('sale')), findsNothing);
    expect(_homeGradient(_type('all')), findsOneWidget);
    expect(_homeGradient(_type('apartment')), findsNothing);
    expect(tester.widget<Icon>(find.byIcon(Icons.key_outlined)).color,
        Colors.white);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.grid_view_outlined)).color,
      Colors.white,
    );
    expect(
      DefaultTextStyle.of(tester.element(find.text('للإيجار'))).style.color,
      Colors.white,
    );

    final target = tester.getRect(_filters);
    final outline = tester.getRect(
      find.descendant(of: _filters, matching: find.byType(Material)),
    );
    expect(target.height, greaterThanOrEqualTo(48));
    expect(outline.height, lessThan(target.height));
    await tester.tapAt(Offset(target.center.dx, target.top + 2));
    await tester.pumpAndSettle();
    expect(find.text('تصفية العقارات'), findsOneWidget);
    expect(_rooms, findsNothing);
    final minimumArea =
        find.byKey(const ValueKey('section-filter-min_area_m2'));
    await tester.enterText(minimumArea, '١٢٠');
    await tester.tap(_apply);
    await tester.pumpAndSettle();
    expect(listings.calls.last, {
      'ranked_search': 0,
      'purpose': 'rent',
      'min_area_m2': 120,
      'page': 1,
    });

    await tester.tap(_purpose('sale'));
    await tester.pumpAndSettle();
    expect(_homeGradient(_purpose('sale')), findsOneWidget);
    expect(_homeGradient(_purpose('rent')), findsNothing);
    expect(_homeGradient(_type('all')), findsOneWidget);
    expect(_filters, findsOneWidget);
    expect(listings.calls.last,
        {'ranked_search': 0, 'purpose': 'sale', 'page': 1});
    await tester.tap(_type('apartment'));
    await tester.pumpAndSettle();
    expect(_homeGradient(_type('all')), findsNothing);
    expect(_homeGradient(_type('apartment')), findsOneWidget);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.apartment_rounded).first).color,
      Colors.white,
    );
    expect(tester.takeException(), isNull);
    await closeUx(tester);
  });

  testWidgets(
      'categories switch inline, preserve type and paginate compact listing cards',
      (tester) async {
    final listings = Listings();
    listings.respond = (filters, page) async {
      final purpose = filters['purpose'] as String;
      final type = filters['type'] as String? ?? 'apartment';
      return (
        [
          row(
            page,
            purpose: purpose,
            type: type,
            title: type == 'land' ? 'أرض في حدة' : 'شقة منشورة في حدة',
          ),
        ],
        page == 1
      );
    };
    final scope = uxContainer(
      extra: [propertyRepositoryProvider.overrideWithValue(listings)],
    );
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const MarketplaceCategoriesScreen(),
      ),
      GoRoute(
        path: '/properties/:id',
        builder: (_, state) => Scaffold(
          body: Text('تفاصيل العقار ${state.pathParameters['id']}'),
        ),
      ),
    ]);
    addTearDown(router.dispose);
    await pumpUx(tester, scope, const SizedBox(), router: router);

    expect(listings.calls.single,
        {'ranked_search': 0, 'purpose': 'rent', 'page': 1});
    expect(find.text('عقارات للإيجار'), findsOneWidget);
    expect(_filters, findsOneWidget);
    expect(tester.getCenter(_type('apartment')).dy,
        tester.getCenter(_type('house')).dy);
    expect(tester.getCenter(_type('apartment')).dx,
        greaterThan(tester.getCenter(_type('house')).dx));

    await tester.tap(_type('apartment'));
    await tester.pumpAndSettle();
    expect(router.canPop(), isFalse);
    expect(find.text('شقق للإيجار'), findsOneWidget);
    expect(_filters, findsOneWidget);
    expect(listings.calls.last, {
      'ranked_search': 0,
      'purpose': 'rent',
      'type': 'apartment',
      'page': 1
    });
    final firstListing = find.byKey(const ValueKey('section-property-1'));
    expect(firstListing, findsOneWidget);
    expect(
        find.descendant(
            of: firstListing, matching: find.byType(ListingPropertyCard)),
        findsOneWidget);
    final photo = find.descendant(
      of: firstListing,
      matching: find.byKey(const ValueKey('my-listing-photo')),
    );
    expect(tester.getSize(photo).height, 122);

    final loadMore = find.text('المزيد من العقارات');
    await tester.scrollUntilVisible(loadMore, 150,
        scrollable: _resultsScroll());
    await tester.tap(loadMore);
    await tester.pumpAndSettle();
    expect(listings.calls.last, {
      'ranked_search': 0,
      'purpose': 'rent',
      'type': 'apartment',
      'page': 2
    });
    expect(find.byKey(const ValueKey('section-property-2')), findsOneWidget);

    await tester.tap(find.text('للبيع'));
    await tester.pumpAndSettle();
    expect(router.canPop(), isFalse);
    expect(find.text('شقق للبيع'), findsOneWidget);
    expect(listings.calls.last, {
      'ranked_search': 0,
      'purpose': 'sale',
      'type': 'apartment',
      'page': 1
    });
    expect(find.byKey(const ValueKey('section-property-2')), findsNothing);

    final typeStrip =
        find.byKey(const PageStorageKey('marketplace-category-types'));
    final horizontal =
        find.descendant(of: typeStrip, matching: find.byType(Scrollable));
    await tester.scrollUntilVisible(_type('land').hitTestable(), 135,
        scrollable: horizontal);
    await tester.tap(_type('land').hitTestable());
    await tester.pumpAndSettle();
    expect(router.canPop(), isFalse);
    expect(find.text('أراضٍ للبيع'), findsOneWidget);
    expect(listings.calls.last,
        {'ranked_search': 0, 'purpose': 'sale', 'type': 'land', 'page': 1});

    await tester.tap(find.text('أرض في حدة 1'));
    await tester.pumpAndSettle();
    expect(find.text('تفاصيل العقار 1'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('أراضٍ للبيع'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await closeUx(tester);
  });

  testWidgets(
      'a delayed result from the previous category cannot replace the current list',
      (tester) async {
    final slowApartment = Completer<PageResult>();
    final listings = Listings()
      ..respond = (filters, _) async => switch (filters['type']) {
            'apartment' => slowApartment.future,
            'house' => (
                [
                  row(22, purpose: 'rent', type: 'house', title: 'منزل للإيجار')
                ],
                false
              ),
            _ => ([row(10, purpose: 'rent')], false),
          };
    final scope = uxContainer(
      extra: [propertyRepositoryProvider.overrideWithValue(listings)],
    );
    await pumpUx(tester, scope, const MarketplaceCategoriesScreen());

    await tester.tap(_type('apartment'));
    await tester.pump();
    expect(listings.calls.last['type'], 'apartment');
    final oldTransfer = listings.transfers.last;
    await tester.tap(_type('house'));
    await tester.pumpAndSettle();
    expect(listings.calls.last['type'], 'house');
    expect(oldTransfer?.isCancelled, isTrue);
    expect(find.byKey(const ValueKey('section-property-22')), findsOneWidget);

    slowApartment.complete(([row(11, purpose: 'rent')], false));
    await tester.pumpAndSettle();
    expect(find.text('منازل للإيجار'), findsOneWidget);
    expect(find.byKey(const ValueKey('section-property-22')), findsOneWidget);
    expect(find.byKey(const ValueKey('section-property-11')), findsNothing);
    expect(tester.takeException(), isNull);
    await closeUx(tester);
  });

  testWidgets(
      'house filters apply inline and are excluded from other property types',
      (tester) async {
    final listings = Listings()
      ..respond = (_, __) async => ([row(10, purpose: 'rent')], false);
    final scope = uxContainer(
      extra: [propertyRepositoryProvider.overrideWithValue(listings)],
    );
    await pumpUx(tester, scope, const MarketplaceCategoriesScreen());

    await tester.tap(_type('house'));
    await tester.pumpAndSettle();
    final requestsBeforeFilter = listings.calls.length;
    await tester.tap(_filters);
    await tester.pumpAndSettle();
    expect(find.text('تصفية المنازل'), findsOneWidget);
    await tester.ensureVisible(_rooms);
    await tester.pump();
    await tester.tap(_rooms);
    expect(_majlis, findsNothing);
    await tester.ensureVisible(_parking);
    await tester.pump();
    await tester.tap(_parking);
    expect(listings.calls, hasLength(requestsBeforeFilter));

    await tester.tap(_apply);
    await tester.pumpAndSettle();
    expect(find.text('تصفية المنازل'), findsNothing);
    expect(find.text('منازل للإيجار'), findsOneWidget);
    expect(listings.calls, hasLength(requestsBeforeFilter + 1));
    expect(listings.calls.last, {
      'ranked_search': 0,
      'purpose': 'rent',
      'type': 'house',
      'min_bedrooms': 3,
      'has_parking': 1,
      'page': 1,
    });

    await tester.tap(_type('apartment'));
    await tester.pumpAndSettle();
    expect(listings.calls.last, {
      'ranked_search': 0,
      'purpose': 'rent',
      'type': 'apartment',
      'page': 1
    });
    await tester.tap(_filters);
    await tester.pumpAndSettle();
    expect(find.text('تصفية الشقق'), findsOneWidget);
    expect(_majlis, findsNothing);
    await tester.tap(find.byTooltip('إغلاق التصفية'));
    await tester.pumpAndSettle();

    await tester.tap(_type('house'));
    await tester.pumpAndSettle();
    expect(listings.calls.last['min_bedrooms'], 3);
    expect(listings.calls.last['has_parking'], 1);
    await tester
        .tap(find.byKey(const ValueKey('marketplace-category-purpose-sale')));
    await tester.pumpAndSettle();
    expect(listings.calls.last,
        {'ranked_search': 0, 'purpose': 'sale', 'type': 'house', 'page': 1});
    await tester
        .tap(find.byKey(const ValueKey('marketplace-category-purpose-rent')));
    await tester.pumpAndSettle();
    expect(listings.calls.last['min_bedrooms'], 3);
    expect(listings.calls.last['has_parking'], 1);
    expect(tester.takeException(), isNull);
    await closeUx(tester);
  });
}

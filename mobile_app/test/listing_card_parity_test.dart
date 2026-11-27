import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/widgets/app_components.dart';
import 'package:real_estate_mobile/features/discovery/data/ai_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/smart_search_session.dart';
import 'package:real_estate_mobile/features/discovery/presentation/assisted_search_screen.dart';
import 'package:real_estate_mobile/features/properties/data/favorites_repository.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/data/recent_properties_store.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/properties/presentation/favorites_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/my_listings_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_compare_actions.dart';
import 'package:real_estate_mobile/features/properties/presentation/recent_properties_screen.dart';

import 'support/my_listings_fixtures.dart';
import 'support/owner_ux_fixtures.dart';
import 'support/private_collection_fixtures.dart';
import 'support/wave3_fakes.dart';

const _address = 'صنعاء، حدة، شارع بيروت';
const _examples = [
  (type: 'land', title: 'أرض على شارع فرعي', factCount: 2),
  (type: 'apartment', title: 'شقة عائلية واسعة بإطلالة مفتوحة على الجبال قريبة من المدارس والخدمات', factCount: 6),
];

Map<String, Rect> _measureCard(WidgetTester tester, String title, int factCount) {
  final facts = find.byKey(const ValueKey('my-listing-facts'));
  final card = find.ancestor(of: facts, matching: find.byType(AppSurface)).first;
  final bounds = tester.getRect(card);
  final factTips = find.descendant(of: facts, matching: find.byType(Tooltip));
  expect(factTips, findsNWidgets(factCount));
  final parts = {
    'photo': find.byKey(const ValueKey('my-listing-photo')),
    'title': find.text(title),
    'address': find.text(_address),
    'price': find.descendant(of: card, matching: find.byType(AppPropertyPrice)),
    'purpose': find.descendant(of: card, matching: find.text('بيع')),
    'status': find.descendant(of: card, matching: find.widgetWithText(AppStatusBadge, 'منشور')),
    'facts': facts,
    'actions': find.byTooltip('خيارات البطاقة'),
    for (final tip in tester.widgetList<Tooltip>(factTips))
      tip.message!: find.descendant(of: facts, matching: find.byTooltip(tip.message!)),
  };
  return {
    'card': Rect.fromLTWH(bounds.left, 0, bounds.width, bounds.height),
    for (final part in parts.entries)
      part.key: tester.getRect(part.value).shift(-bounds.topLeft),
  };
}

void main() {
  setUpAll(loadUxFixtures);
  for (final example in _examples) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('${example.type} in all consumer lists matches My Listings All at scale $scale', (tester) async {
        final json = <String, dynamic>{
          'id': 42, 'title': example.title, 'address': _address,
          'purpose': 'sale', 'type': example.type, 'status': 'published',
          'availability_status': 'available', 'currency': 'YER',
          'price': 12500000, 'area_m2': 140, 'latitude': 15.33, 'longitude': 44.21,
          if (example.type == 'apartment') ...{
            'bedrooms': 3, 'bathrooms': 2, 'floor_number': '3', 'has_parking': true,
          },
        };
        final listing = PropertyDetails.fromJson(json);
        final summary = PropertySummary.fromJson(json);
        final ai = Wave3AiFake()..onRefine = (_, __, revision) async => {
          'revision': revision,
          'filters': {'purpose': 'sale', 'type': example.type, 'governorate': 'صنعاء'},
        };
        final properties = Wave3PropertiesFake()..onSearch = (_, __) async => ([summary], false);
        final scope = uxContainer(user: uxUser(), extra: [
          aiRepositoryProvider.overrideWithValue(ai),
          propertyRepositoryProvider.overrideWithValue(properties),
          myListingsPagesProvider.overrideWith((_) => fixedMyListings([listing])),
          recentPropertiesProvider.overrideWith((_) async => [summary]),
          favoritePagesProvider.overrideWith((_) => fixedFavoritePages([summary])),
        ]);
        const size = Size(390, 1320);
        await pumpUx(tester, scope, const MyListingsScreen(), scale: scale, size: size);
        final expected = _measureCard(tester, example.title, example.factCount);
        expect(expected['card']!.left, 18);
        expect(expected['photo']!.height, 122);
        expect(expected['facts']!.right, lessThan(expected['photo']!.left));
        await closeUx(tester);

        for (final screen in const [
          AssistedSearchScreen(),
          FavoritesScreen(),
          RecentPropertiesScreen(),
        ]) {
          await pumpUx(tester, scope, screen, scale: scale, size: size);
          if (screen is AssistedSearchScreen) {
            final field = find.byKey(const ValueKey('smart-search-description'));
            await tester.enterText(field, 'عقار للبيع في صنعاء');
            await tester.testTextInput.receiveAction(TextInputAction.search);
            await tester.pumpAndSettle();
            expect(properties.queries, hasLength(1));
            expect(scope.read(smartSearchSessionProvider).rows.map((p) => p.id), [42]);
          }
          expect(find.text(example.title), findsOneWidget, reason: '${screen.runtimeType} loaded the sample');
          await tester.ensureVisible(find.text(example.title));
          final actual = _measureCard(tester, example.title, example.factCount);
          expect(actual.keys, unorderedEquals(expected.keys));
          for (final part in expected.keys) {
            final measured = actual[part]!, baseline = expected[part]!;
            final context = '${screen.runtimeType} $part at scale $scale';
            expect(measured.left, closeTo(baseline.left, .01), reason: context);
            expect(measured.top, closeTo(baseline.top, .01), reason: context);
            expect(measured.width, closeTo(baseline.width, .01), reason: context);
            expect(measured.height, closeTo(baseline.height, .01), reason: context);
          }

          await tester.tap(find.byTooltip('خيارات البطاقة'));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('favorite-property-42')).hitTestable(), findsOneWidget);
          final compare = find.byKey(const ValueKey('compare-property-42'));
          expect(compare.hitTestable(), findsOneWidget);
          expect(find.text('تعديل'), findsNothing);
          expect(find.text('حذف'), findsNothing);
          await tester.tap(compare);
          await tester.pumpAndSettle();
          expect(scope.read(propertyCompareSelectionProvider), {42});
          scope.read(propertyCompareSelectionProvider.notifier).clear();
          expect(tester.takeException(), isNull);
          await closeUx(tester);
        }
      });
    }
  }
}

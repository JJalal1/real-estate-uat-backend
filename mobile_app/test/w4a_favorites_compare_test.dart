import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/widgets/app_components.dart';
import 'package:real_estate_mobile/features/properties/data/favorites_repository.dart';
import 'package:real_estate_mobile/features/properties/data/property_market_repository.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/favorite_list_item.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/properties/domain/property_sai.dart';
import 'package:real_estate_mobile/features/properties/presentation/favorites_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_compare_screen.dart';

class _ComparisonProperties implements PropertyRepository {
  final unavailable = <int>{};
  final loaded = <int>[];
  final secondaryRequests = <int>[];

  @override
  Future<PropertyDetails> details(int propertyId) async {
    loaded.add(propertyId);
    return PropertyDetails.fromJson({
      'id': propertyId,
      'status': unavailable.contains(propertyId) ? 'draft' : 'published',
      'is_owner': unavailable.contains(propertyId),
      'title': unavailable.contains(propertyId)
          ? 'PRIVATE DRAFT TITLE' : 'Public comparison $propertyId',
      'price': unavailable.contains(propertyId) ? 987654321 : 15000000,
      'currency': 'YER',
      'purpose': 'sale',
      'type': 'house',
      'latitude': 15.3694,
      'longitude': 44.1910,
      'address': unavailable.contains(propertyId) ? 'PRIVATE ADDRESS' : 'صنعاء',
      'images': [],
    });
  }

  @override
  Future<PropertySaiEnvelope> sai(int propertyId) async {
    secondaryRequests.add(propertyId);
    return const PropertySaiEnvelope();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ComparisonMarket implements PropertyMarketRepository {
  final loaded = <int>[];

  @override
  Future<PropertyMarketContext> context(int propertyId) async {
    loaded.add(propertyId);
    return const PropertyMarketContext(sufficientData: false, sampleCount: 0);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ComparisonFavorites implements FavoritesRepository {
  @override
  Future<List<FavoriteListItem>> favorites() async => [
        for (final id in [42, 43, 99])
          FavoriteListItem.fromJson({
            'property_id': id,
            'availability': id == 99 ? 'unavailable' : 'available',
            if (id != 99)
              'property': {
                'id': id, 'status': 'published', 'title': 'Favorite $id',
                'price': 15000000, 'currency': 'YER',
                'latitude': 15.3694, 'longitude': 44.1910,
              },
          }),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(
  WidgetTester tester,
  Widget screen,
  _ComparisonProperties properties,
  _ComparisonMarket market,
) async {
  tester.view.physicalSize = const Size(400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      favoritesRepositoryProvider.overrideWithValue(_ComparisonFavorites()),
      propertyRepositoryProvider.overrideWithValue(properties),
      propertyMarketRepositoryProvider.overrideWithValue(market),
    ],
    child: MaterialApp(home: screen),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('real comparison navigation receives only available favorite IDs',
      (tester) async {
    final properties = _ComparisonProperties();
    final market = _ComparisonMarket();
    await _pump(
      tester, const FavoritesScreen(startInCompareMode: true), properties, market,
    );
    for (final id in [42, 43]) {
      await tester.tap(find.text('Favorite $id'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.widgetWithText(AppButton, 'مقارنة 2 عقارات'));
    await tester.pumpAndSettle();
    final compare = tester.widget<PropertyCompareScreen>(find.byType(PropertyCompareScreen));
    expect(compare.propertyIds, [42, 43]);
    expect(properties.loaded, [42, 43]);
    expect(market.loaded, [42, 43]);
    expect(find.text('Public comparison 42'), findsOneWidget);
    expect(find.text('Public comparison 43'), findsOneWidget);
  });

  testWidgets('comparison skips a property unpublished after selection',
      (tester) async {
    final properties = _ComparisonProperties()..unavailable.add(42);
    final market = _ComparisonMarket();
    await _pump(
      tester, const PropertyCompareScreen(propertyIds: [42, 43]), properties, market,
    );
    expect(properties.loaded, [42, 43]);
    expect(properties.secondaryRequests, [43]);
    expect(market.loaded, [43]);
    expect(find.text('اختر عقارين على الأقل'), findsOneWidget);
    expect(find.text('PRIVATE DRAFT TITLE'), findsNothing);
    expect(find.text('PRIVATE ADDRESS'), findsNothing);
    expect(find.byType(AppPropertyPrice), findsNothing);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/properties/data/favorites_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/property_marker.dart';
import 'package:real_estate_mobile/features/properties/presentation/favorites_screen.dart';

void main() {
  testWidgets('favorites screen has a real empty state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          favoritePropertiesProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: FavoritesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('المفضلة'), findsOneWidget);
    expect(find.text('لا توجد عقارات محفوظة'), findsOneWidget);
    expect(
      find.text('اضغط على رمز القلب في أي عقار ليظهر هنا ويظل محفوظاً في حسابك.'),
      findsOneWidget,
    );
  });

  testWidgets('favorites screen renders server-backed property cards',
      (tester) async {
    const property = PropertyMarker(
      id: 42,
      title: 'عقار محفوظ في Phase 3',
      price: 25000000,
      currency: 'YER',
      latitude: 15.3694,
      longitude: 44.1910,
      distanceKm: 0,
      purpose: 'sale',
      type: 'apartment',
      areaM2: 120,
      bedrooms: 3,
      bathrooms: 2,
      address: 'صنعاء',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          favoritePropertiesProvider.overrideWith((ref) async => const [property]),
        ],
        child: const MaterialApp(home: FavoritesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('عقار محفوظ في Phase 3'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Text &&
            widget.textSpan?.toPlainText().contains('25,000,000 YER') == true,
      ),
      findsOneWidget,
    );
    expect(find.text('للبيع'), findsOneWidget);
    expect(find.text('120 م²'), findsOneWidget);
    expect(find.byTooltip('إزالة من المفضلة'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/design/app_design.dart';
import 'package:real_estate_mobile/features/properties/data/favorites_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/property_marker.dart';
import 'package:real_estate_mobile/features/properties/presentation/favorites_screen.dart';

import 'support/design_test_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadDesignTestFonts);
  testWidgets('favorite comparison preserves selection order and four-property limit', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 915);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final items = List.generate(5, (index) => PropertyMarker(
      id: index + 1, title: 'عقار ${index + 1}', price: 100,
      currency: 'YER', latitude: 15.3694, longitude: 44.191,
      distanceKm: 0, purpose: 'sale',
    ));
    await tester.pumpWidget(ProviderScope(
      overrides: [favoritePropertiesProvider.overrideWith((ref) async => items)],
      child: MaterialApp(theme: AppTheme.light, home: const FavoritesScreen(startInCompareMode: true)),
    ));
    await tester.pumpAndSettle();
    for (var id = 1; id <= 5; id++) {
      final title = find.text('عقار $id');
      await tester.scrollUntilVisible(title, 350, scrollable: find.byType(Scrollable));
      await tester.pumpAndSettle();
      await tester.tap(title);
      await tester.pumpAndSettle();
      if (id <= 4) {
        final selected = find.text('اختيار $id');
        expect(selected, findsOneWidget);
        final card = find.widgetWithText(AppPropertyCard, 'عقار $id');
        final media = find.descendant(of: card, matching: find.byType(AppPropertyMedia));
        expect(tester.getTopLeft(selected).dy, greaterThan(tester.getBottomLeft(media).dy),
            reason: 'Comparison order must not cover the image/purpose badge.');
      }
    }
    expect(find.text('يمكن مقارنة أربعة عقارات كحد أقصى.'), findsOneWidget);
    final compare = tester.widget<AppButton>(find.widgetWithText(AppButton, 'مقارنة 4 عقارات'));
    expect(compare.onPressed, isNotNull);
    await tester.tap(find.byTooltip('إلغاء المقارنة'));
    await tester.pumpAndSettle();
    expect(find.text('المفضلة'), findsOneWidget);
    expect(find.text('مقارنة 4 عقارات'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

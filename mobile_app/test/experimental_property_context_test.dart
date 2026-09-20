import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/design/app_design.dart';
import 'package:real_estate_mobile/features/properties/data/property_market_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/property_sai.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_market_context_card.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_sai_public_line.dart';

import 'support/capture_design.dart';
import 'support/design_test_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadDesignTestFonts);
  for (final size in [const Size(320, 915), const Size(412, 915), const Size(600, 915), const Size(600, 280)]) {
    testWidgets('server market and Sai wording at $size / 2.4', (tester) async {
      final key = GlobalKey();
      await _open(tester, size: size, captureKey: key,
        market: () async => _market, sai: () async => _sai);
      await tester.pumpAndSettle();
      expect(find.text('8 مقارنة'), findsOneWidget);
      expect(find.text('95,000,000 YER'), findsOneWidget);
      expect(find.text('475,000 YER/م²'), findsOneWidget);
      expect(find.text('5.3% أقل من الوسيط'), findsOneWidget);
      expect(find.text(_disclaimer), findsOneWidget);
      expect(find.text(_publicSai), findsOneWidget);
      expect(find.textContaining('حصة المنصة'), findsNothing);
      await captureDesign(tester, key, 'property-context-${size.width.toInt()}-${size.height.toInt()}-2.4');
      await _reveal(tester, find.text(_publicSai));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('market and Sai errors retry independently at large Arabic scale', (tester) async {
    var marketCalls = 0;
    var saiCalls = 0;
    await _open(tester,
      market: () async {
        if (++marketCalls == 1) throw StateError('market unavailable');
        return _market;
      },
      sai: () async {
        if (++saiCalls == 1) throw StateError('sai unavailable');
        return _sai;
      },
    );
    await tester.pumpAndSettle();
    final marketRetry = find.descendant(of: find.byType(PropertyMarketContextCard), matching: find.text('إعادة المحاولة'));
    await _reveal(tester, marketRetry);
    await tester.tap(marketRetry);
    await tester.pumpAndSettle();
    expect(marketCalls, 2);
    expect(saiCalls, 1);
    expect(find.text('8 مقارنة'), findsOneWidget);
    final saiRetry = find.descendant(of: find.byType(PropertySaiPublicLine), matching: find.widgetWithText(AppButton, 'إعادة المحاولة'));
    await _reveal(tester, saiRetry);
    await tester.tap(saiRetry);
    await tester.pumpAndSettle();
    expect(saiCalls, 2);
    expect(marketCalls, 2);
    expect(find.text(_publicSai), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading resolves to original insufficient and unavailable states', (tester) async {
    final market = Completer<PropertyMarketContext>();
    final sai = Completer<PropertySaiEnvelope>();
    await _open(tester, market: () => market.future, sai: () => sai.future);
    expect(find.byType(AppSkeleton), findsNWidgets(2));
    market.complete(const PropertyMarketContext(sufficientData: false, sampleCount: 2, minimumSampleSize: 5));
    sai.complete(const PropertySaiEnvelope());
    await tester.pumpAndSettle();
    expect(find.text('2 من 5 عقارات مقارنة'), findsOneWidget);
    expect(find.text('وسيط السعر'), findsNothing);
    expect(find.text('بيانات السعي غير متاحة لهذا الإعلان.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const _disclaimer = 'مؤشر استرشادي وليس تقييماً رسمياً أو ضماناً لسعر الصفقة.';
const _publicSai = 'السعي 5% - يتحملها المشتري';
const _market = PropertyMarketContext(sufficientData: true, sampleCount: 8,
  medianPrice: 95000000, medianPricePerM2: 475000, deltaFromMedianPercent: -5.3,
  position: 'near_comparable_median', disclaimer: _disclaimer);
const _sai = PropertySaiEnvelope(sai: PropertySai(ratePercent: 5, payer: 'buyer',
  payerLabel: 'المشتري', calculationBasis: 'server', displayText: _publicSai));

Future<void> _open(WidgetTester tester, {
  Size size = const Size(320, 915), GlobalKey? captureKey,
  required Future<PropertyMarketContext> Function() market,
  required Future<PropertySaiEnvelope> Function() sai,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(overrides: [
    propertyMarketContextProvider(77).overrideWith((ref) => market()),
    propertySaiPublicProvider(77).overrideWith((ref) => sai()),
  ], child: RepaintBoundary(key: captureKey, child: MaterialApp(theme: AppTheme.light, debugShowCheckedModeBanner: false,
    home: MediaQuery(data: MediaQueryData(size: size, textScaler: const TextScaler.linear(2.4)),
      child: Directionality(textDirection: TextDirection.rtl, child: Scaffold(
        body: SingleChildScrollView(child: AppContentFrame(child: const Column(children: [
          PropertyMarketContextCard(propertyId: 77, currency: 'YER'),
          PropertySaiPublicLine(propertyId: 77),
        ]))),
      )),
    ),
  ))));
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  await Scrollable.ensureVisible(tester.element(target), alignment: .5);
  await tester.pumpAndSettle();
}

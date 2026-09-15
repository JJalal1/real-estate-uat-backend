import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/design/app_design.dart';

import 'support/capture_design.dart';
import 'support/design_test_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadDesignTestFonts);

  for (final width in [320.0, 412.0, 600.0]) {
    for (final scale in [1.0, 2.4]) {
      testWidgets('property card RTL $width / $scale keeps independent actions',
          (tester) async {
        _viewport(tester, Size(width, 915));
        final captureKey = GlobalKey();
        var details = 0;
        var favorites = 0;
        var maps = 0;
        const title = 'فيلا عائلية واسعة في منطقة حدة بالقرب من الخدمات';
        await tester.pumpWidget(_app(
          scale: scale,
          child: RepaintBoundary(
            key: captureKey,
            child: Scaffold(
              body: SingleChildScrollView(
                child: AppContentFrame(
                  child: AppPropertyCard(
                    title: title,
                    price: '12,500,000',
                    currency: 'YER',
                    purposeLabel: 'للبيع',
                    categoryLabel: 'فيلا',
                    location: 'صنعاء، حدة، بالقرب من جولة المصباحي — ABC-123',
                    selected: true,
                    facts: const [
                      AppPropertyFact(icon: Icons.square_foot, label: '420 م²'),
                      AppPropertyFact(icon: Icons.bed_outlined, label: '5 غرف'),
                      AppPropertyFact(icon: Icons.bathtub_outlined, label: '3 حمام'),
                    ],
                    trailing: IconButton.filledTonal(
                      tooltip: 'حفظ في المفضلة',
                      onPressed: () => favorites++,
                      icon: const Icon(Icons.favorite_border_rounded),
                    ),
                    footer: AppButton(
                      label: 'عرض على الخريطة',
                      icon: Icons.location_on_outlined,
                      onPressed: () => maps++,
                      style: AppButtonStyle.text,
                      expand: true,
                    ),
                    onTap: () => details++,
                  ),
                ),
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.widget<Text>(find.text(title)).maxLines, isNull);
        expect(Directionality.of(tester.element(find.text(title))), TextDirection.rtl);
        // Tooltip wraps the 40px painted icon surface inside Material's
        // 48px input padding. Measure and exercise the actual button target.
        final favorite = find.widgetWithIcon(IconButton, Icons.favorite_border_rounded);
        expect(tester.getSize(favorite).shortestSide, greaterThanOrEqualTo(48));
        await tester.tapAt(tester.getRect(favorite).centerLeft + const Offset(2, 0));
        expect(favorites, 1);
        expect(details, 0);
        await tester.ensureVisible(find.text(title));
        await tester.pumpAndSettle();
        await tester.tap(find.text(title));
        expect(details, 1);
        await tester.ensureVisible(find.text('عرض على الخريطة'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('عرض على الخريطة'));
        expect(maps, 1);
        expect(details, 1, reason: 'Map and favorite actions must not open details.');
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 4000));
        await tester.pumpAndSettle();
        await captureDesign(tester, captureKey, 'property-card-${width.toInt()}-$scale');
      });
    }
  }

  testWidgets('related rail grows for Arabic text and preserves last property action',
      (tester) async {
    _viewport(tester, const Size(320, 568));
    var opened = -1;
    await tester.pumpWidget(_app(
      scale: 2.4,
      child: Scaffold(
        body: SingleChildScrollView(
          child: AppContentFrame(
            child: AppPropertyRail(
              itemCount: 6,
              itemBuilder: (context, index) => AppPropertyCard(
                title: 'عقار مشابه رقم $index في منطقة حدة بصنعاء',
                price: '12,500,000',
                currency: 'YER',
                location: 'عنوان عربي طويل لاختبار تمدد البطاقة دون قص المعلومات',
                unavailable: index == 5,
                onTap: () => opened = index,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AppPropertyRail)).height, greaterThan(340));
    final last = find.text('عقار مشابه رقم 5 في منطقة حدة بصنعاء');
    await tester.ensureVisible(last);
    await tester.pumpAndSettle();
    await tester.tap(last);
    expect(opened, 5);
    expect(find.text('هذا الإعلان غير متاح حالياً.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled favorite remains disabled while details remain reachable',
      (tester) async {
    var opened = false;
    await tester.pumpWidget(_app(
      scale: 1,
      child: Scaffold(
        body: SingleChildScrollView(
          child: AppPropertyCard(
            title: 'عقار',
            price: '100',
            currency: 'YER',
            trailing: const IconButton.filledTonal(
              tooltip: 'حفظ في المفضلة',
              onPressed: null,
              icon: Icon(Icons.favorite_border_rounded),
            ),
            onTap: () => opened = true,
          ),
        ),
      ),
    ));
    expect(tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNull);
    await tester.tap(find.text('عقار'));
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
  });
}

void _viewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app({required double scale, required Widget child}) => MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: Directionality(textDirection: TextDirection.rtl, child: child!),
      ),
      home: child,
    );

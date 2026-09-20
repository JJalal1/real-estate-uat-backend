import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/design/app_design.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_map_dock.dart';

import 'support/capture_design.dart';
import 'support/design_test_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadDesignTestFonts);
  for (final viewport in [
    (const Size(320, 568), 1.0),
    (const Size(320, 568), 2.4),
    (const Size(412, 915), 2.4),
    (const Size(600, 280), 2.4),
  ]) {
    testWidgets('listing map actions preserve exposed map and reachability $viewport', (tester) async {
      final calls = <String>[];
      final key = GlobalKey();
      await _open(tester, viewport.$1, viewport.$2, key: key,
        mapTap: () => calls.add('map'), dock: ListingMapDock(
          instruction: 'اسحب الدبوس إلى العقار، أو حرّك الخريطة ليعود الدبوس إلى المنتصف.',
          message: 'لم يتم منح إذن الموقع. حرّك الدبوس يدوياً.',
          primaryLabel: 'تأكيد هذا الموقع', onPrimary: () => calls.add('confirm'),
          secondaryAction: AppButton(label: 'موقعي الحالي', onPressed: () => calls.add('location')),
        ),
      );
      await tester.tapAt(Offset(20, viewport.$1.height * .25));
      expect(calls, ['map']);
      expect(tester.getSize(find.byType(ListingMapDock)).height, lessThanOrEqualTo(viewport.$1.height * .4));
      for (final label in ['تأكيد هذا الموقع', 'موقعي الحالي']) {
        final target = find.widgetWithText(AppButton, label);
        await Scrollable.ensureVisible(tester.element(target), alignment: .5);
        await tester.pumpAndSettle();
        await tester.tap(target);
      }
      expect(calls, ['map', 'confirm', 'location']);
      expect(tester.takeException(), isNull);
      await captureDesign(tester, key, 'listing-map-dock-${viewport.$1.width.toInt()}-${viewport.$1.height.toInt()}-${viewport.$2}');
    });
  }

  testWidgets('loading and insufficient boundary keep confirmation disabled', (tester) async {
    await _open(tester, const Size(320, 568), 2.4,
      dock: const ListingMapDock(instruction: 'جارٍ تحميل الخريطة…',
        primaryLabel: 'جارٍ قراءة العنوان…', onPrimary: null, loading: true),
    );
    expect(tester.widget<AppButton>(find.widgetWithText(AppButton, 'جارٍ قراءة العنوان…')).onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _open(tester, const Size(320, 568), 2.4,
      dock: const ListingMapDock(instruction: 'تم تحديد 2 نقطة. أكمل محيط الأرض ثم أكد الحدود.',
        primaryLabel: 'اعتماد حدود الأرض', onPrimary: null),
    );
    expect(tester.widget<AppButton>(find.widgetWithText(AppButton, 'اعتماد حدود الأرض')).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _open(WidgetTester tester, Size size, double scale, {
  required Widget dock, GlobalKey? key, VoidCallback? mapTap,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(RepaintBoundary(key: key, child: MaterialApp(
    theme: AppTheme.light, debugShowCheckedModeBanner: false,
    builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: Directionality(textDirection: TextDirection.rtl, child: child!)),
    home: Scaffold(body: Stack(fit: StackFit.expand, children: [
      GestureDetector(behavior: HitTestBehavior.opaque, onTap: mapTap,
        child: const ColoredBox(color: Color(0xFFEFF4F0))),
      PositionedDirectional(start: 0, end: 0, bottom: 0, child: dock),
    ])),
  )));
  await tester.pump();
}

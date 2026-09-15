import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/design/app_design.dart';
import 'package:real_estate_mobile/features/map/presentation/discovery_filter_sheet.dart';

import 'support/capture_design.dart';
import 'support/design_test_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadDesignTestFonts);

  for (final viewport in [
    for (final width in [320.0, 412.0, 600.0])
      for (final scale in [1.0, 2.4]) (Size(width, 915), scale),
    (const Size(600, 280), 2.4),
  ]) {
    testWidgets('filter RTL ${viewport.$1} / ${viewport.$2} preserves existing criteria',
        (tester) async {
      DiscoveryFilterResult? result;
      final key = GlobalKey();
      await _open(tester,
        size: viewport.$1, scale: viewport.$2, captureKey: key,
        sheet: _initialSheet,
        onResult: (value) => result = value,
      );
      expect(tester.takeException(), isNull);
      await _reveal(tester, _field('أقل سعر'));
      await captureDesign(tester, key,
          'discovery-filter-${viewport.$1.width.toInt()}-${viewport.$1.height.toInt()}-${viewport.$2}');
      await _tap(tester, find.text('عرض العقارات'));
      expect(result, isNotNull);
      expect(result!.purpose, 'rent');
      expect(result!.type, 'apartment');
      expect(result!.minPrice, 100);
      expect(result!.maxPrice, 200);
      expect(result!.minArea, 50);
      expect(result!.maxArea, 80);
      expect(result!.minBedrooms, 2);
      expect(result!.minBathrooms, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('filter keeps malformed, negative, price and area validation order',
      (tester) async {
    DiscoveryFilterResult? result;
    await _open(tester, sheet: _initialSheet, onResult: (value) => result = value);
    await _enter(tester, 'أقل سعر', 'bad');
    await _enter(tester, 'أعلى سعر', '5');
    await _enter(tester, 'من', '100');
    await _enter(tester, 'إلى', '-1');
    for (final correction in [
      ('أقل سعر', '10', 'تأكد من كتابة الأرقام بشكل صحيح.'),
      ('إلى', '50', 'القيم لا يمكن أن تكون سالبة.'),
      ('أعلى سعر', '20', 'أعلى سعر يجب أن يكون أكبر من أقل سعر.'),
      ('إلى', '150', 'أكبر مساحة يجب أن تكون أكبر من أقل مساحة.'),
    ]) {
      await _tap(tester, find.text('عرض العقارات'));
      expect(result, isNull);
      expect(find.text(correction.$3), findsOneWidget);
      expect(find.byType(DiscoveryFilterSheet), findsOneWidget);
      await _enter(tester, correction.$1, correction.$2);
    }
    await _tap(tester, find.text('عرض العقارات'));
    expect(result!.minPrice, 10);
    expect(result!.maxPrice, 20);
    expect(result!.minArea, 100);
    expect(result!.maxArea, 150);
    expect(result!.minBedrooms, 2);
  });

  testWidgets('non-residential type clears room filters while retaining other criteria',
      (tester) async {
    DiscoveryFilterResult? result;
    await _open(tester, sheet: _initialSheet, onResult: (value) => result = value);
    await _tap(tester, find.widgetWithText(ChoiceChip, 'مزرعة'));
    expect(find.text('غرف النوم'), findsNothing);
    expect(find.text('الحمامات'), findsNothing);
    await _tap(tester, find.text('عرض العقارات'));
    expect(result!.type, 'farm');
    expect(result!.minBedrooms, isNull);
    expect(result!.minBathrooms, isNull);
    expect(result!.purpose, 'rent');
    expect(result!.minPrice, 100);
  });

  testWidgets('selected room minimum toggles off without affecting bathrooms',
      (tester) async {
    DiscoveryFilterResult? result;
    await _open(tester, sheet: _initialSheet, onResult: (value) => result = value);
    final section = find.ancestor(of: find.text('غرف النوم'), matching: find.byType(AppSectionCard));
    await _tap(tester, find.descendant(of: section, matching: find.widgetWithText(ChoiceChip, '2+')));
    await _tap(tester, find.text('عرض العقارات'));
    expect(result!.minBedrooms, isNull);
    expect(result!.minBathrooms, 1);
  });

  testWidgets('reset clears every filter and permits applying an empty result',
      (tester) async {
    DiscoveryFilterResult? result;
    await _open(tester, sheet: _initialSheet, onResult: (value) => result = value);
    await _tap(tester, find.text('مسح'));
    await _tap(tester, find.text('عرض العقارات'));
    expect(result, isNotNull);
    expect([
      result!.purpose, result!.type, result!.minPrice, result!.maxPrice,
      result!.minArea, result!.maxArea, result!.minBedrooms, result!.minBathrooms,
    ], everyElement(isNull));
  });
}

const _initialSheet = DiscoveryFilterSheet(
  initialPurpose: 'rent', initialType: 'apartment',
  initialMinPrice: 100, initialMaxPrice: 200,
  initialMinArea: 50, initialMaxArea: 80,
  initialMinBedrooms: 2, initialMinBathrooms: 1,
);

Finder _field(String label) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label);

Future<void> _reveal(WidgetTester tester, Finder target) async {
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await _reveal(tester, target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String label, String value) async {
  await _reveal(tester, _field(label));
  await tester.enterText(_field(label), value);
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester, {
  required DiscoveryFilterSheet sheet,
  required ValueChanged<DiscoveryFilterResult?> onResult,
  Size size = const Size(412, 915),
  double scale = 1,
  GlobalKey? captureKey,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    builder: (context, child) => RepaintBoundary(
      key: captureKey,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: Directionality(textDirection: TextDirection.rtl, child: child!),
      ),
    ),
    home: Builder(builder: (context) => Scaffold(
      body: Center(child: TextButton(
        onPressed: () async => onResult(await showModalBottomSheet<DiscoveryFilterResult>(
          context: context, isScrollControlled: true, useSafeArea: true,
          builder: (context) => sheet,
        )),
        child: const Text('فتح الفلاتر'),
      )),
    )),
  ));
  await tester.tap(find.text('فتح الفلاتر'));
  await tester.pumpAndSettle();
}

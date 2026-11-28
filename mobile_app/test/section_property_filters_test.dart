import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/features/discovery/presentation/marketplace_category_filter_sheet.dart';

Finder _filter(String key) => find.byKey(ValueKey('section-filter-$key'));

Future<void> _mount(
  WidgetTester tester, {
  required String type,
  required String typeLabel,
  required ValueChanged<Map<String, Object>?> onResult,
  String purpose = 'rent',
  Map<String, Object> initial = const {},
  double textScale = 1,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
        body: Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          onResult(await showMarketplaceCategoryFilters(
            context,
            purpose: purpose,
            type: type,
            typeLabel: typeLabel,
            initial: initial,
          ));
        },
        child: const Text('افتح التصفية'),
      ),
    )),
  ));
  await _open(tester);
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('افتح التصفية'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('house filter sends minimum counts and a private majlis bath',
      (tester) async {
    final results = <Map<String, Object>?>[];
    await _mount(tester,
        type: 'house', typeLabel: 'منازل', onResult: results.add);
    expect(find.text('تصفية المنازل'), findsOneWidget);
    expect(find.text('منازل للإيجار'), findsOneWidget);
    expect(find.text('نوع الأرض'), findsNothing);

    await _tap(tester, _filter('min_bedrooms-3'));
    await _tap(tester, _filter('min_parking_spaces-1'));
    await _tap(tester, _filter('has_majlis_bathroom'));
    expect(results, isEmpty);
    expect(tester.widget<SwitchListTile>(_filter('has_separate_majlis')).value,
        isTrue);
    await _tap(tester, _filter('apply'));
    expect(results, [
      {
        'min_bedrooms': 3,
        'min_parking_spaces': 1,
        'has_separate_majlis': 1,
        'has_majlis_bathroom': 1,
      }
    ]);
  });

  testWidgets(
      'land filter checks localized area bounds and sends land-specific fields',
      (tester) async {
    final results = <Map<String, Object>?>[];
    await _mount(tester,
        type: 'land',
        typeLabel: 'أراضٍ',
        purpose: 'sale',
        onResult: results.add);
    expect(find.text('تصفية الأراضي'), findsOneWidget);
    expect(find.text('أراضٍ للبيع'), findsOneWidget);
    expect(find.text('عدد الغرف'), findsNothing);

    await _tap(tester, _filter('land_use-residential'));
    await tester.enterText(_filter('min_area_m2'), '١٦٠٫٥');
    await tester.enterText(_filter('max_area_m2'), '۱۵۰');
    await _tap(tester, _filter('apply'));
    expect(results, isEmpty);
    expect(_filter('error'), findsOneWidget);

    await tester.enterText(_filter('max_area_m2'), '۳۴۵٫۵');
    await _tap(tester, _filter('min_street_width-16'));
    await _tap(tester, _filter('select-building_facade'));
    await _tap(tester, find.text('شمالية').last);
    await _tap(tester, _filter('apply'));
    expect(results, [
      {
        'land_use': 'residential',
        'min_area_m2': 160.5,
        'max_area_m2': 345.5,
        'min_street_width': 16,
        'building_facade': 'north',
      }
    ]);
  });

  testWidgets(
      'reset changes the draft, and dismissal keeps the applied filters',
      (tester) async {
    final initial = <String, Object>{
      'min_bedrooms': 3,
      'has_separate_majlis': 1,
      'has_majlis_bathroom': 1,
    };
    final results = <Map<String, Object>?>[];
    await _mount(tester,
        type: 'house',
        typeLabel: 'منازل',
        initial: initial,
        onResult: results.add);
    expect(
        tester.widget<ChoiceChip>(_filter('min_bedrooms-3')).selected, isTrue);
    await _tap(tester, _filter('has_separate_majlis'));
    expect(tester.widget<SwitchListTile>(_filter('has_majlis_bathroom')).value,
        isFalse);
    await _tap(tester, find.byTooltip('إغلاق التصفية'));
    expect(results, [null]);
    expect(initial.length, 3);

    await _open(tester);
    expect(
        tester.widget<ChoiceChip>(_filter('min_bedrooms-3')).selected, isTrue);
    await _tap(tester, _filter('reset'));
    expect(results, [null]);
    expect(tester.widget<ChoiceChip>(_filter('min_bedrooms-all')).selected,
        isTrue);
    await _tap(tester, _filter('apply'));
    expect(results, [null, <String, Object>{}]);
  });

  const types = {
    'apartment': (
      'شقق',
      ['floor_number', 'has_section_elevator', 'has_parking']
    ),
    'villa': ('فلل', ['has_yard', 'has_separate_majlis', 'min_parking_spaces']),
    'building': (
      'عمائر',
      ['min_floors', 'min_total_units', 'has_section_elevator']
    ),
    'farm': ('مزارع', ['farm_water_source', 'farm_crop_type', 'area']),
    'shop': ('محلات', ['min_shop_openings', 'min_street_width', 'area']),
    'office': (
      'مكاتب',
      ['min_office_rooms', 'floor_number', 'has_section_elevator']
    ),
  };
  for (final type in types.entries) {
    testWidgets('${type.key} filters stay usable at large Arabic text scale',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final results = <Map<String, Object>?>[];
      await _mount(tester,
          type: type.key,
          typeLabel: type.value.$1,
          textScale: 2.4,
          onResult: results.add);
      for (final key in type.value.$2) {
        expect(_filter(key), findsOneWidget);
      }
      expect(_filter('land_use'), findsNothing);
      await _tap(tester, _filter('reset'));
      await _tap(tester, _filter('apply'));
      expect(results, [<String, Object>{}]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('area stays focused when a keyboard reduces the sheet height',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    final results = <Map<String, Object>?>[];
    await _mount(tester,
        type: 'shop', typeLabel: 'محلات', onResult: results.add);
    final area = _filter('min_area_m2');
    await tester.enterText(area, '٩٠');
    tester.view.viewInsets = const FakeViewPadding(bottom: 330);
    await tester.pumpAndSettle();

    final editable = tester.widget<EditableText>(
        find.descendant(of: area, matching: find.byType(EditableText)));
    expect(editable.focusNode.hasFocus, isTrue);
    await _tap(tester, _filter('apply'));
    expect(results, [
      {'min_area_m2': 90}
    ]);
    expect(tester.takeException(), isNull);
  });
}

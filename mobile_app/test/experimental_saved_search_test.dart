import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/design/app_design.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/properties/data/saved_search_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/saved_property_search.dart';
import 'package:real_estate_mobile/features/properties/presentation/saved_search_builder_screen.dart';

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
    testWidgets('saved search RTL ${viewport.$1} / ${viewport.$2} preserves create payload', (tester) async {
      final repository = _Repository();
      final key = GlobalKey();
      await _open(tester, repository, size: viewport.$1, scale: viewport.$2, captureKey: key);
      await _reveal(tester, _field('أقل سعر'));
      await captureDesign(tester, key, 'saved-search-${viewport.$1.width.toInt()}-${viewport.$1.height.toInt()}-${viewport.$2}');
      await _tap(tester, find.widgetWithText(AppButton, 'حفظ البحث'));
      expect(repository.calls, 1);
      expect(repository.filters, _filters);
      expect(repository.name, 'إيجار • شقة • حدة ABC');
      expect(repository.frequency, 'instant');
      expect(find.text('SAVED'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('saved search edit preserves legacy daily selection and full criteria', (tester) async {
    final repository = _Repository();
    await _open(tester, repository, existing: _saved(frequency: 'daily'));
    await _reveal(tester, find.text('ملخص يومي محفوظ سابقًا'));
    final tile = tester.widget<RadioListTile<String>>(find.widgetWithText(RadioListTile<String>, 'ملخص يومي محفوظ سابقًا'));
    expect(tile.onChanged, isNull);
    await _tap(tester, find.widgetWithText(AppButton, 'حفظ التعديلات'));
    expect(repository.updatedId, 9);
    expect(repository.frequency, 'daily');
    expect(repository.filters, _filters);
    expect(find.text('SAVED'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('purpose deselection and location removal keep all other criteria', (tester) async {
    final repository = _Repository();
    await _open(tester, repository);
    await _tap(tester, find.widgetWithText(FilterChip, 'إيجار'));
    await _tap(tester, find.text('إزالة قيد الموقع'));
    await _tap(tester, find.text('حفظ بدون تنبيهات'));
    await _tap(tester, find.widgetWithText(AppButton, 'حفظ البحث'));
    final expected = Map<String, dynamic>.from(_filters)
      ..remove('purpose')..remove('latitude')..remove('longitude')..remove('radius_km');
    expect(repository.filters, expected);
    expect(repository.frequency, 'off');
    expect(repository.calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved search numeric and range validation order is unchanged', (tester) async {
    final repository = _Repository();
    await _open(tester, repository);
    await _enter(tester, 'أقل سعر', 'bad');
    await _enter(tester, 'أعلى سعر', 'bad');
    await _enter(tester, 'أقل عدد غرف', 'bad');
    await _enter(tester, 'أقل عدد حمامات', 'bad');
    await _enter(tester, 'أقل مساحة', 'bad');
    await _enter(tester, 'أعلى مساحة', 'bad');
    for (final correction in [
      ('أقل سعر', '200', 'أدخل أقل سعر بشكل صحيح.'),
      ('أعلى سعر', '100', 'أدخل أعلى سعر بشكل صحيح.'),
      ('أقل عدد غرف', '2', 'أدخل عدد الغرف بشكل صحيح.'),
      ('أقل عدد حمامات', '1', 'أدخل عدد الحمامات بشكل صحيح.'),
      ('أقل مساحة', '80', 'أدخل أقل مساحة بشكل صحيح.'),
      ('أعلى مساحة', '50', 'أدخل أعلى مساحة بشكل صحيح.'),
      ('أعلى سعر', '300', 'أقل سعر يجب أن يكون أقل من أو يساوي أعلى سعر.'),
      ('أعلى مساحة', '100', 'أقل مساحة يجب أن تكون أقل من أو تساوي أعلى مساحة.'),
    ]) {
      await _tap(tester, find.widgetWithText(AppButton, 'حفظ البحث'));
      expect(find.text(correction.$3), findsOneWidget);
      expect(repository.calls, 0);
      // Dismiss only the previous transient message before the next validation.
      final context = tester.element(find.byType(SavedSearchBuilderScreen));
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      await _enter(tester, correction.$1, correction.$2);
    }
    await _tap(tester, find.widgetWithText(AppButton, 'حفظ البحث'));
    expect(repository.calls, 1);
    expect(repository.filters!['max_price'], 300);
    expect(repository.filters!['max_area_m2'], 100);
    expect(tester.takeException(), isNull);
  });
}

const _filters = <String, dynamic>{
  'purpose': 'rent', 'type': 'apartment', 'search': 'حدة ABC',
  'min_price': 100.0, 'max_price': 200.0, 'min_bedrooms': 2, 'min_bathrooms': 1,
  'min_area_m2': 50.0, 'max_area_m2': 80.0,
  'latitude': 15.3, 'longitude': 44.2, 'radius_km': 10.0,
};
SavedPropertySearch _saved({String frequency = 'instant'}) => SavedPropertySearch(
  id: 9, name: 'بحث محفوظ للاختبار', filters: _filters,
  alertFrequency: frequency, isActive: true, matchingCount: 3,
);

class _Repository extends SavedSearchRepository {
  _Repository() : super(Dio(), AuthRepository(Dio()));
  int calls = 0;
  int? updatedId;
  String? name;
  String? frequency;
  Map<String, dynamic>? filters;
  @override
  Future<SavedPropertySearch> create({required String name, required Map<String, dynamic> filters, String alertFrequency = 'instant'}) async {
    calls++;
    this.name = name;
    this.filters = filters;
    frequency = alertFrequency;
    return _saved(frequency: alertFrequency);
  }
  @override
  Future<SavedPropertySearch> update(int id, {String? name, Map<String, dynamic>? filters, String? alertFrequency, bool? isActive}) async {
    updatedId = id;
    return create(name: name!, filters: filters!, alertFrequency: alertFrequency!);
  }
}

Finder _field(String label) => find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == label);
Future<void> _reveal(WidgetTester tester, Finder target) async {
  final scroll = find.descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable)).first;
  if (target.evaluate().isEmpty) {
    tester.state<ScrollableState>(scroll).position.jumpTo(0);
    await tester.pumpAndSettle();
  }
  await tester.scrollUntilVisible(target, 250, scrollable: scroll, maxScrolls: 150);
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
Future<void> _open(WidgetTester tester, _Repository repository, {
  Size size = const Size(320, 915), double scale = 1, GlobalKey? captureKey,
  SavedPropertySearch? existing,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  var saved = false;
  await tester.pumpWidget(ProviderScope(overrides: [savedSearchRepositoryProvider.overrideWithValue(repository)],
    child: RepaintBoundary(key: captureKey, child: MaterialApp(theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      home: StatefulBuilder(builder: (context, setState) => Scaffold(body: FilledButton(
        onPressed: () async {
          final result = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => SavedSearchBuilderScreen(
            initialFilters: _filters, existingSearch: existing,
          )));
          setState(() => saved = result == true);
        },
        child: Text(saved ? 'SAVED' : 'OPEN'),
      ))),
    )),
  ));
  await tester.tap(find.text('OPEN'));
  await tester.pumpAndSettle();
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_editor_screen.dart';
import 'support/owner_ux_fixtures.dart' show loadUxFixtures;
import 'support/wave6_fakes.dart';
import 'wave6_product_ui_test.dart' show pumpWave6, finishWave6, editorSnapshot, textField, previewWave6;

Map<String, dynamic> completedRental({bool pin = false}) => {
  ...editorSnapshot(type: 'apartment'), 'editor_version': 10, 'draft_kind': 'recovery',
  'completion_only': true, 'entry_method': 'assistant', 'purpose': 'rent',
  'latitude': pin ? 15.37 : null, 'longitude': pin ? 44.19 : null,
  'sai_touched': true, 'sai_terms_accepted': true, 'sai_amount_type': 'percentage',
  'fields': {'title': 'شقة صناعية للإيجار', 'governorate': 'ذمار', 'district': 'حي اختباري',
    'monthly_rent': '100000', 'bedrooms': '4', 'bathrooms': '2', 'floor_number': '2',
    'phone': '771234567', 'broker_sai_rate_percent': '100', 'description': 'نص راجعه صاحب الإعلان'},
};

void main() {
  setUpAll(loadUxFixtures);
  for (final scale in [1.0, 2.4]) {
    testWidgets('B01 B02 known rental facts are summary text and only gaps are inputs at $scale', (tester) async {
      final boundary = GlobalKey(), recovery = Wave6Recovery(completedRental());
      await pumpWave6(tester, const ListingEditorScreen(), recovery: recovery, scale: scale, boundary: boundary);
      expect(find.byKey(const ValueKey('listing-completed-summary')), findsOneWidget);
      expect(find.textContaining('4 غرف نوم'), findsOneWidget);
      expect(textField('غرف النوم *'), findsNothing);
      expect(textField('الحمامات *'), findsNothing);
      expect(textField('الإيجار الشهري بالريال اليمني *'), findsNothing);
      expect(find.byKey(const ValueKey('listing-floor-select')), findsNothing);
      expect(find.text('تأكيد الموقع على الخريطة'), findsOneWidget);
      expect(find.text('ارفع صورًا حقيقية للعقار.'), findsOneWidget);
      expect(textField('المساحة *'), findsNothing);
      await previewWave6(tester, boundary, 'branch2-missing-only-$scale');
      expect(tester.takeException(), isNull);
      await finishWave6(tester);
    });
  }
  testWidgets('B02 a confirmed pin is retained without asking to locate again', (tester) async {
    final recovery = Wave6Recovery(completedRental(pin: true));
    await pumpWave6(tester, const ListingEditorScreen(), recovery: recovery);
    expect(find.text('تأكيد الموقع على الخريطة'), findsNothing);
    expect(find.text('نقطة العقار مؤكدة'), findsOneWidget);
    expect(find.text('ارفع صورًا حقيقية للعقار.'), findsOneWidget);
    await finishWave6(tester);
  });
  testWidgets('B03 completed review returns to fresh gaps and preserves common facts', (tester) async {
    final recovery = Wave6Recovery(completedRental()), drafts = Wave6Drafts();
    await pumpWave6(tester, const ListingEditorScreen(), recovery: recovery, drafts: drafts);
    await tester.ensureVisible(find.byKey(const ValueKey('listing-review-completed')));
    await tester.tap(find.byKey(const ValueKey('listing-review-completed'))); await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('listing-return-completion')), findsOneWidget);
    await tester.ensureVisible(textField('عنوان الإعلان *'));
    await tester.enterText(textField('عنوان الإعلان *'), 'قص');
    await tester.tap(find.byKey(const ValueKey('listing-return-completion'))); await tester.pumpAndSettle();
    expect(find.text('أكمل الناقص فقط'), findsOneWidget);
    expect(textField('عنوان الإعلان *'), findsOneWidget);
    expect(textField('غرف النوم *'), findsNothing);
    await tester.pump(const Duration(seconds: 1)); await tester.pumpAndSettle();
    expect((recovery.snapshot!['fields'] as Map)['monthly_rent'], '100000');
    expect((recovery.snapshot!['fields'] as Map)['description'], 'نص راجعه صاحب الإعلان');
    expect(recovery.snapshot!['completion_only'], isTrue);
    expect(recovery.snapshot!['completion_reviewing'], isFalse);
    expect(drafts.drafts.length, 1);
    await finishWave6(tester);
  });
  testWidgets('B04 restored review state returns to gaps on Back without exiting or submitting', (tester) async {
    final recovery = Wave6Recovery({...completedRental(), 'completion_only': false, 'completion_reviewing': true, 'step': 0});
    await pumpWave6(tester, const ListingEditorScreen(), recovery: recovery);
    expect(find.byKey(const ValueKey('listing-return-completion')), findsOneWidget);
    await tester.binding.handlePopRoute(); await tester.pumpAndSettle();
    expect(find.text('أكمل الناقص فقط'), findsOneWidget);
    expect(find.byType(ListingEditorScreen), findsOneWidget);
    expect(textField('الإيجار الشهري بالريال اليمني *'), findsNothing);
    await finishWave6(tester);
  });
  testWidgets('B05 B07 invalid shop structure stays missing while valid numbers do not repeat', (tester) async {
    final data = {...editorSnapshot(type: 'shop'), 'editor_version': 10, 'completion_only': true};
    (data['fields'] as Map)['shop_openings'] = '101';
    await pumpWave6(tester, const ListingEditorScreen(), recovery: Wave6Recovery(data));
    expect(find.byKey(const ValueKey('listing-shop-openings')), findsOneWidget);
    expect(textField('المساحة بالمتر المربع *'), findsNothing);
    expect(textField('سعر البيع بالريال اليمني *'), findsNothing);
    expect(find.text('تأكيد الموقع على الخريطة'), findsNothing);
    expect(find.text('إرسال للمراجعة'), findsNothing);
    await finishWave6(tester);
  });
}

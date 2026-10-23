import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/properties/presentation/rental_conditions_editor.dart';

void main() {
  testWidgets('optional rental conditions reveal only advertiser-selected details and preserve exact input', (tester) async {
    var value = <Map<String, dynamic>>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(builder: (context, update) =>
      SingleChildScrollView(child: RentalConditionsEditor(value: value,
        onChanged: (next) => update(() => value = next)))))));
    expect(find.byType(TextFormField), findsNothing);
    expect(find.byType(FilterChip), findsNWidgets(5));
    expect(find.byType(CheckboxListTile), findsNothing);
    await tester.tap(find.byKey(const ValueKey('rent-condition-advance'))); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rent-condition-special'))); await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(TextFormField), findsOneWidget);
    expect(find.text('مدة العقد بالأشهر'), findsNothing);
    expect(find.text('ضمانة تجارية مطلوبة'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('rent-advance-0'))); await tester.pumpAndSettle();
    await tester.tap(find.text('شهران').last); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('rent-special-1')), 'لا يسمح بالتأجير من الباطن');
    expect(value, [{'kind': 'advance', 'months': 2}, {'kind': 'special', 'text': 'لا يسمح بالتأجير من الباطن'}]);
    await tester.ensureVisible(find.text('إضافة شرط خاص آخر'));
    await tester.tap(find.text('إضافة شرط خاص آخر')); await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(2));
    await tester.ensureVisible(find.byTooltip('حذف الشرط').first);
    await tester.tap(find.byTooltip('حذف الشرط').first); await tester.pumpAndSettle();
    expect(value.map((row) => row['kind']), ['special', 'special']);
    expect(value.first['text'], 'لا يسمح بالتأجير من الباطن');
    expect(tester.widget<TextFormField>(find.byKey(const ValueKey('rent-special-0'))).initialValue, 'لا يسمح بالتأجير من الباطن');
    expect(find.text('عدد أشهر المقدم'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rental requirements stay manual without an AI action', (tester) async {
    const original = <Map<String, dynamic>>[{'kind': 'guarantor'}, {'kind': 'duration', 'months': 12}];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RentalConditionsEditor(value: original,
      onChanged: (_) => fail('Rendering must not change selected requirements.')))));
    expect(find.text('تأمين مطلوب'), findsNothing);
    expect(find.text('ترتيب وصياغة الشروط بالذكاء الاصطناعي'), findsNothing);
    expect(find.byIcon(Icons.auto_awesome), findsNothing);
    expect(original, [{'kind': 'guarantor'}, {'kind': 'duration', 'months': 12}]);
    expect(tester.takeException(), isNull);
  });
}

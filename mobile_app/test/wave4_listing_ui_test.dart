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
    expect(find.text('أضف ما تحتاجه فقط؛ يمكنك المتابعة دون شروط.'), findsOneWidget);
    await tester.tap(find.text('إضافة شروط اختيارية')); await tester.pumpAndSettle();
    await tester.tap(find.text('مقدم إيجار')); await tester.tap(find.text('شرط خاص'));
    await tester.tap(find.text('استخدام الشروط المحددة')); await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('مدة العقد بالأشهر'), findsNothing);
    expect(find.text('ضمانة تجارية مطلوبة'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('rent-advance-0')), '٢');
    await tester.enterText(find.byKey(const ValueKey('rent-special-1')), 'لا يسمح بالتأجير من الباطن');
    expect(value, [{'kind': 'advance', 'months': 2}, {'kind': 'special', 'text': 'لا يسمح بالتأجير من الباطن'}]);
    await tester.ensureVisible(find.text('إضافة شرط خاص آخر'));
    await tester.tap(find.text('إضافة شرط خاص آخر')); await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(3));
    await tester.ensureVisible(find.byTooltip('حذف الشرط').first);
    await tester.tap(find.byTooltip('حذف الشرط').first); await tester.pumpAndSettle();
    expect(value.map((row) => row['kind']), ['special', 'special']);
    expect(value.first['text'], 'لا يسمح بالتأجير من الباطن');
    expect(find.text('عدد أشهر المقدم'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('condition assistance is optional and waits for an explicit review action', (tester) async {
    var requests = 0;
    const original = <Map<String, dynamic>>[{'kind': 'guarantor'}, {'kind': 'duration', 'months': 12}];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RentalConditionsEditor(value: original,
      onChanged: (_) => fail('An assistant action must not apply an unreviewed change.'), onPolish: () => requests++))));
    expect(requests, 0);
    expect(find.text('تأمين مطلوب'), findsNothing);
    await tester.tap(find.text('ترتيب وصياغة الشروط بالذكاء الاصطناعي')); await tester.pump();
    expect(requests, 1);
    expect(original, [{'kind': 'guarantor'}, {'kind': 'duration', 'months': 12}]);
    expect(tester.takeException(), isNull);
  });
}

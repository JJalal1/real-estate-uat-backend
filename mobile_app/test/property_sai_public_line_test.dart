import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_sai_public_line.dart';

void main() {
  testWidgets('public sai line renders the approved customer wording only', (tester) async {
    const text = 'السعي 5% - يتحملها المشتري';

    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: PropertySaiDisplayLine(text: text),
          ),
        ),
      ),
    );

    expect(find.text(text), findsOneWidget);
    expect(find.textContaining('عمولة المنصة'), findsNothing);
    expect(find.textContaining('حصة المنصة'), findsNothing);
    expect(find.textContaining('عمولة الدلال'), findsNothing);
    expect(find.textContaining('حصة الدلال'), findsNothing);
  });

  testWidgets('public sai line remains readable at large text scale', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SizedBox(
                width: 320,
                child: PropertySaiDisplayLine(
                  text: 'السعي 100% - يتحملها المستأجر',
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('السعي 100% - يتحملها المستأجر'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

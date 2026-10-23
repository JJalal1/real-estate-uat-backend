import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Flutter test environment loads', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Text('Real Estate test environment'),
        ),
      ),
    );

    expect(find.text('Real Estate test environment'), findsOneWidget);
  });
}

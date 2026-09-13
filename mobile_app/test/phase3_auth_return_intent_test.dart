import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/account/data/auth_return_intent.dart';

void main() {
  testWidgets('auth return location is internal, one-shot and has a fallback',
      (tester) async {
    late WidgetRef capturedRef;

    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(
          builder: (context, ref, child) {
            capturedRef = ref;
            return const MaterialApp(home: SizedBox());
          },
        ),
      ),
    );

    setAuthReturnLocation(capturedRef, '/properties/42');
    expect(capturedRef.read(authReturnLocationProvider), '/properties/42');

    expect(takeAuthReturnLocation(capturedRef), '/properties/42');
    expect(capturedRef.read(authReturnLocationProvider), isNull);
    expect(takeAuthReturnLocation(capturedRef), '/');

    expect(
      () => setAuthReturnLocation(capturedRef, 'https://example.com/properties/42'),
      throwsArgumentError,
    );
  });
}

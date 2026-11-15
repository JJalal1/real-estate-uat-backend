import 'package:flutter_test/flutter_test.dart';

// A stalled private request must fail quickly instead of holding CI for ten minutes.
void phase23WidgetTest(
  String description,
  Future<void> Function(WidgetTester) body,
) {
  testWidgets(description, body,
      timeout: const Timeout(Duration(minutes: 1)));
}

// Advance the fake event queue while the intentionally pending response stays open.
// Zero-duration pumps do not advance Dio's queued timers or route animations.
Future<void> pumpPhase23Request(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

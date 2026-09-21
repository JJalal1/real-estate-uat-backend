import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/router/app_deep_links.dart';

void main() {
  test('Phase 4 message deep link opens the exact conversation', () {
    final link = messageThreadAppDeepLink(91);

    expect(link.toString(), 'realestate://app/messages/91');
    expect(internalLocationForAppLink(link), '/messages/91');
  });

  test('Phase 4 viewing deep link opens the exact booking target', () {
    final link = viewingBookingAppDeepLink(44);

    expect(link.toString(), 'realestate://app/bookings/44');
    expect(internalLocationForAppLink(link), '/bookings?booking=44');
  });

  test('Phase 4 links reject invalid ids and foreign routes', () {
    expect(() => messageThreadAppDeepLink(0), throwsArgumentError);
    expect(() => viewingBookingAppDeepLink(-2), throwsArgumentError);
    expect(
      internalLocationForAppLink(Uri.parse('realestate://app/messages/nope')),
      isNull,
    );
    expect(
      internalLocationForAppLink(Uri.parse('realestate://other/bookings/44')),
      isNull,
    );
  });
}

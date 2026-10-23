import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/router/app_deep_links.dart';

void main() {
  test('property deep links map to the public property route', () {
    final link = propertyAppDeepLink(42);

    expect(link.toString(), 'realestate://app/properties/42');
    expect(internalLocationForAppLink(link), '/properties/42');
  });

  test('foreign or malformed links are not rewritten', () {
    expect(
      internalLocationForAppLink(Uri.parse('https://example.com/properties/42')),
      isNull,
    );
    expect(
      internalLocationForAppLink(Uri.parse('realestate://app/properties/nope')),
      isNull,
    );
    expect(
      internalLocationForAppLink(Uri.parse('realestate://other/properties/42')),
      isNull,
    );
  });

  test('property IDs must be positive', () {
    expect(() => propertyAppDeepLink(0), throwsArgumentError);
    expect(() => propertyAppDeepLink(-5), throwsArgumentError);
  });
}

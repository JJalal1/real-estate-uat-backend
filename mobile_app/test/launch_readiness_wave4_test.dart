import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/router/app_deep_links.dart';

void main() {
  test('public property share link resolves back into property route', () {
    final link = propertyPublicShareLink(42);
    expect(link.scheme, 'https');
    expect(link.path, '/l/properties/42');
    expect(internalLocationForAppLink(link), '/properties/42');
  });

  test('custom property deep link remains supported', () {
    final link = propertyAppDeepLink(7);
    expect(link.toString(), 'realestate://app/properties/7');
    expect(internalLocationForAppLink(link), '/properties/7');
  });

  test('foreign links are ignored', () {
    expect(
      internalLocationForAppLink(Uri.parse('https://example.com/l/properties/7')),
      isNull,
    );
  });
}

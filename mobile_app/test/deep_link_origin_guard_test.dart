import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/router/app_deep_links.dart';

void main() {
  test('canonical deep links still resolve to intended paths', () {
    expect(internalLocationForAppLink(Uri.parse('realestate://app/properties/42')), '/properties/42');
    expect(internalLocationForAppLink(Uri.parse('realestate://app/messages/42')), '/messages/42');
    expect(internalLocationForAppLink(propertyPublicShareLink(42)), '/properties/42');
  });

  test('rejects links with query tokens, fragments, credentials and alternate origins', () {
    for (final link in [
      'realestate://app/properties/42?access_token=example',
      'realestate://app/messages/42#fragment',
      'realestate://user@app/properties/42',
      'realestate://app:4444/properties/42',
      'https://real-estate-uat-api-frankfurt.onrender.com/l/properties/42?token=example',
      'https://real-estate-uat-api-frankfurt.onrender.com/l/properties/42#fragment',
      'https://user@real-estate-uat-api-frankfurt.onrender.com/l/properties/42',
      'http://real-estate-uat-api-frankfurt.onrender.com/l/properties/42',
      'https://real-estate-uat-api-frankfurt.onrender.com:4444/l/properties/42',
    ]) {
      expect(internalLocationForAppLink(Uri.parse(link)), isNull, reason: link);
    }
  });
}

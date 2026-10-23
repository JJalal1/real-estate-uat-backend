import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';

void main() {
  group('Stage 5 property models', () {
    test('details parser orders the primary image first', () {
      final property = PropertyDetails.fromJson(<String, dynamic>{
        'id': 42,
        'title': 'منزل',
        'purpose': 'rent',
        'type': 'house',
        'price': '25000000.00',
        'currency': 'YER',
        'latitude': '15.3694',
        'longitude': '44.1910',
        'images': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 2,
            'url': 'https://example.test/second.jpg',
            'is_primary': false,
            'sort_order': 1,
          },
          <String, dynamic>{
            'id': 1,
            'url': 'https://example.test/primary.jpg',
            'is_primary': true,
            'sort_order': 8,
          },
        ],
      });

      expect(property.id, 42);
      expect(property.price, 25000000);
      expect(property.images.first.id, 1);
      expect(property.mainImage, 'https://example.test/primary.jpg');
    });

    test('land payload never sends room fields', () {
      const input = PropertyListingInput(
        title: 'أرض سكنية',
        purpose: 'sale',
        type: 'land',
        price: 90000000,
        latitude: 15.3,
        longitude: 44.2,
        bedrooms: 4,
        bathrooms: 3,
      );

      final payload = input.toMap();
      expect(payload['currency'], 'YER');
      expect(payload.containsKey('bedrooms'), isFalse);
      expect(payload.containsKey('bathrooms'), isFalse);
    });
  });
}

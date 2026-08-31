import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/properties/domain/property_field_options.dart';

void main() {
  group('UAT Change Phase 2 property contract', () {
    test('v2 payload preserves original area unit and optional contact', () {
      const input = PropertyListingInput(
        title: 'منزل للاختبار',
        purpose: 'sale',
        type: 'house',
        tenureType: 'freehold',
        price: 50000000,
        latitude: 15.3694,
        longitude: 44.1910,
        areaValue: 2,
        areaUnit: 'libna_sanaani',
        bedrooms: 4,
        bathrooms: 3,
        hasParking: false,
        buildingFacade: 'east',
        address: 'صنعاء - حدة',
      );

      final payload = input.toMap();
      expect(payload['listing_input_version'], 2);
      expect(payload['tenure_type'], 'freehold');
      expect(payload['area_value'], 2);
      expect(payload['area_unit'], 'libna_sanaani');
      expect(payload['has_parking'], false);
      expect(payload['building_facade'], 'east');
      expect(payload['contact_phone'], '');
      expect(payload['contact_whatsapp'], '');
    });

    test('details parser reads phase2 listing fields', () {
      final property = PropertyDetails.fromJson(<String, dynamic>{
        'id': 71,
        'title': 'فيلا',
        'purpose': 'sale',
        'type': 'villa',
        'tenure_type': 'waqf',
        'price': 75000000,
        'currency': 'YER',
        'area_m2': 89,
        'area_value': '2.00',
        'area_unit': 'libna_sanaani',
        'bedrooms': 5,
        'bathrooms': 4,
        'has_parking': false,
        'building_facade': 'west',
        'latitude': 15.36,
        'longitude': 44.19,
        'images': <dynamic>[],
      });

      expect(property.tenureType, 'waqf');
      expect(property.areaValue, 2);
      expect(property.areaUnit, 'libna_sanaani');
      expect(property.hasParking, false);
      expect(property.buildingFacade, 'west');
    });

    test('Yemeni local area-unit reference values are stable', () {
      expect(propertyAreaUnitSquareMetres['libna_sanaani'], 44.44);
      expect(propertyAreaUnitSquareMetres['libna_dhamari'], 114.49);
      expect(propertyAreaUnitSquareMetres['qasaba_taizi_ashari'], 20.25);
      expect(propertyAreaUnitSquareMetres['qasaba_taizi_hadawi'], 29.16);
      expect(propertyAreaUnitSquareMetres['qasaba_ibbi'], 56.25);
      expect(propertyFacadeLabel('east'), 'شرقية');
    });
  });
}

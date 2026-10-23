import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:real_estate_mobile/features/map/domain/map_area_geometry.dart';
import 'package:real_estate_mobile/features/map/domain/map_screen_coordinate_space.dart';
import 'package:real_estate_mobile/features/map/presentation/map_screen.dart';
import 'package:real_estate_mobile/features/properties/domain/property_location_address.dart';

void main() {
  group('UAT map price labels', () {
    test('map markers render compact prices instead of anonymous dots', () {
      expect(mapPropertyPriceLabel(194000), '194 ألف');
      expect(mapPropertyPriceLabel(2500000), '2.5 مليون');
      expect(mapPropertyPriceLabel(50000000), '50 مليون');
    });

    test('native price symbols keep a readable map scale', () {
      expect(mapPropertyPriceIconSize, 1.0);
      expect(mapPropertyPriceIconSize, greaterThan(0.5));
    });

    test('native price images have deterministic state-specific names', () {
      final sale = mapPropertyPriceImageName(
        '194 ألف',
        selected: false,
        rent: false,
      );
      final rent = mapPropertyPriceImageName(
        '194 ألف',
        selected: false,
        rent: true,
      );
      final selected = mapPropertyPriceImageName(
        '194 ألف',
        selected: true,
        rent: false,
      );

      expect(sale, startsWith('re_price_'));
      expect(rent, isNot(sale));
      expect(selected, isNot(sale));
      expect(
        mapPropertyPriceImageName(
          '194 ألف',
          selected: false,
          rent: false,
        ),
        sale,
      );
    });
  });

  group('UAT map area geometry', () {
    test('freehand polygon keeps exact point filtering inside its bounding box',
        () {
      final area = MapAreaGeometry.fromPoints(const [
        LatLng(15.3600, 44.1800),
        LatLng(15.3700, 44.1800),
        LatLng(15.3720, 44.1920),
        LatLng(15.3620, 44.1960),
      ]);

      expect(area.isMeaningful, isTrue);
      expect(area.contains(15.3660, 44.1880), isTrue);
      expect(area.contains(15.3695, 44.1955), isFalse);
      expect(area.contains(15.3800, 44.1880), isFalse);
      expect(area.bounds.southwest.latitude, closeTo(15.3600, 0.000001));
      expect(area.bounds.northeast.longitude, closeTo(44.1960, 0.000001));
      expect(area.points.first.latitude, area.points.last.latitude);
      expect(area.points.first.longitude, area.points.last.longitude);
    });
  });

  group('UAT MapLibre screen coordinate conversion', () {
    test('logical drawing coordinates round-trip through Android pixel density',
        () {
      const logical = Offset(120, 360);
      final platform = MapScreenCoordinateSpace.logicalToPlatformPixels(
        logical,
        3,
      );
      expect(platform.x, 360);
      expect(platform.y, 1080);

      final roundTrip = MapScreenCoordinateSpace.platformPixelsToLogical(
        platform,
        3,
      );
      expect(roundTrip.dx, closeTo(logical.dx, 0.0001));
      expect(roundTrip.dy, closeTo(logical.dy, 0.0001));
    });
  });

  group('UAT editable reverse-geocoded address', () {
    test('stored combined address is split into editable fields', () {
      final address = PropertyLocationAddress.fromStoredAddress(
        'أمانة العاصمة - حدة - شارع صفر',
      );

      expect(address.governorate, 'أمانة العاصمة');
      expect(address.district, 'حدة');
      expect(address.street, 'شارع صفر');
      expect(address.combined, 'أمانة العاصمة - حدة - شارع صفر');
    });

    test('partial automatic data remains valid and editable', () {
      const internal = PropertyLocationAddress(
        governorate: 'أمانة العاصمة',
        district: 'المربع 12',
      );
      const external = PropertyLocationAddress(
        district: 'حدة',
        street: 'شارع صفر',
      );
      final merged = external.mergeFallback(internal);

      expect(merged.governorate, 'أمانة العاصمة');
      expect(merged.district, 'حدة');
      expect(merged.street, 'شارع صفر');
      expect(merged.isComplete, isTrue);
      expect(merged.resolvedFieldCount, 3);
    });
  });
}

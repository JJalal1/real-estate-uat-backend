import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/map/domain/property_marker_cluster.dart';
import 'package:real_estate_mobile/features/properties/domain/property_marker.dart';

PropertyMarker marker(int id, double lat, double lon) => PropertyMarker(
  id: id,
  title: 'عقار $id',
  price: 1000000,
  currency: 'YER',
  latitude: lat,
  longitude: lon,
  distanceKm: 0,
  purpose: 'sale',
  type: 'apartment',
);

void main() {
  test('nearby markers cluster at city zoom and separate when zoomed in', () {
    final items = [
      marker(1, 15.36940, 44.19100),
      marker(2, 15.36945, 44.19104),
      marker(3, 15.36949, 44.19108),
    ];

    final city = clusterPropertyMarkers(items, zoom: 11);
    expect(city, hasLength(1));
    expect(city.single.items.map((item) => item.id), containsAll([1, 2, 3]));

    final street = clusterPropertyMarkers(items, zoom: 16);
    expect(street, hasLength(3));
    expect(street.every((cluster) => !cluster.isCluster), isTrue);
  });

  test('selected property remains individually addressable inside crowded area', () {
    final items = [
      marker(1, 15.36940, 44.19100),
      marker(2, 15.36945, 44.19104),
      marker(3, 15.36949, 44.19108),
    ];

    final clusters = clusterPropertyMarkers(
      items,
      zoom: 11,
      selectedPropertyId: 2,
    );

    final selected = clusters.singleWhere(
      (cluster) => cluster.items.any((item) => item.id == 2),
    );
    expect(selected.items, hasLength(1));
    expect(selected.first.id, 2);
    expect(clusters.expand((cluster) => cluster.items).map((item) => item.id).toSet(),
        {1, 2, 3});
  });
}

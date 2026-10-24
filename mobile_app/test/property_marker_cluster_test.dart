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

  test('zoom sweep keeps every property exactly once without mutating input', () {
    final items = <PropertyMarker>[
      marker(1, 15.36940, 44.19100),
      marker(2, 15.36942, 44.19103),
      marker(3, 15.36950, 44.19105),
      marker(4, 15.38500, 44.20500),
      marker(5, 15.39000, 44.21500),
    ];
    final originalIds = items.map((item) => item.id).toList();
    for (final zoom in <double>[8, 10, 11, 12.5, 14, 15.49, 15.5, 16, 19]) {
      for (final selectedId in <int?>[null, 2, 9999]) {
        final clusters = clusterPropertyMarkers(
          items,
          zoom: zoom,
          selectedPropertyId: selectedId,
        );
        final ids = clusters.expand((cluster) => cluster.items)
            .map((item) => item.id).toList();
        expect(ids.toSet(), originalIds.toSet(), reason: 'zoom=$zoom selected=$selectedId');
        expect(ids.length, originalIds.length, reason: 'no duplicate at zoom=$zoom');
        if (selectedId == 2) {
          final selected = clusters.where(
            (cluster) => cluster.items.any((item) => item.id == 2),
          ).single;
          expect(selected.items, hasLength(1), reason: 'selected marker zoom=$zoom');
        }
        if (zoom >= 15.5) {
          expect(clusters, hasLength(items.length));
          expect(clusters.every((cluster) => !cluster.isCluster), isTrue);
        }
      }
    }
    expect(items.map((item) => item.id).toList(), originalIds);
  });

  test('empty and single-item queries have stable display semantics', () {
    expect(clusterPropertyMarkers(const <PropertyMarker>[], zoom: 10), isEmpty);
    final item = marker(91, 15.3694, 44.191);
    for (final zoom in <double>[9, 11, 15.5, 17]) {
      final clusters = clusterPropertyMarkers([item], zoom: zoom);
      expect(clusters, hasLength(1));
      expect(clusters.single.first.id, 91);
      expect(clusters.single.isCluster, isFalse);
      expect(clusters.single.latitude, item.latitude);
      expect(clusters.single.longitude, item.longitude);
    }
  });

}

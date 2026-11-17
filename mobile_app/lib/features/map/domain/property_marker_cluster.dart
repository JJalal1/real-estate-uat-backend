import 'dart:math' as math;

import '../../properties/domain/property_marker.dart';

List<PropertyMarker> propertyMarkersForAnnotations(List<PropertyMarker> items) =>
  (items.any((item) => item.discoveryMatch != null) ? items : items.take(250)).toList(growable: false);

class PropertyMarkerCluster {
  const PropertyMarkerCluster({
    required this.latitude,
    required this.longitude,
    required this.items,
  });

  final double latitude;
  final double longitude;
  final List<PropertyMarker> items;

  bool get isCluster => items.length > 1;
  PropertyMarker get first => items.first;
  int get nearbyCount => items.where((item) => item.discoveryMatch?.nearby == true).length;
  int get exactCount => items.length - nearbyCount;
}

List<PropertyMarkerCluster> clusterPropertyMarkers(
  List<PropertyMarker> items, {
  required double zoom,
  int? selectedPropertyId,
}) {
  if (items.length <= 1) {
    return items
        .map(
          (item) => PropertyMarkerCluster(
            latitude: item.latitude,
            longitude: item.longitude,
            items: [item],
          ),
        )
        .toList(growable: false);
  }

  final cellDegrees = 0.04 / math.pow(2, (zoom - 10).clamp(0, 8));
  final buckets = <String, List<PropertyMarker>>{};

  for (final item in items) {
    final ranked = item.discoveryMatch != null;
    if (!ranked && (item.id == selectedPropertyId || zoom >= 15.5)) {
      buckets['selected:${item.id}'] = [item];
      continue;
    }
    final latCell = (item.latitude / cellDegrees).floor();
    final lonCell = (item.longitude / cellDegrees).floor();
    // One visible cluster shows both classification counts. Separate symbols
    // at the same building would hide each other even with distinct IDs.
    // At street zoom retain only truly co-located ranked units together.
    final key = ranked && zoom >= 15.5
      ? 'point:${item.latitude}:${item.longitude}' : '$latCell:$lonCell:${ranked ? 'ranked' : 'legacy'}';
    buckets.putIfAbsent(key, () => <PropertyMarker>[]).add(item);
  }

  return buckets.values.map((bucket) {
    final latitude =
        bucket.fold<double>(0, (sum, item) => sum + item.latitude) / bucket.length;
    final longitude =
        bucket.fold<double>(0, (sum, item) => sum + item.longitude) / bucket.length;
    return PropertyMarkerCluster(
      latitude: latitude,
      longitude: longitude,
      items: List<PropertyMarker>.unmodifiable(bucket),
    );
  }).toList(growable: false);
}

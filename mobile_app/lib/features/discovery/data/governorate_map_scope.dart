import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/services.dart';

import '../../map/domain/map_area_geometry.dart';
import '../domain/smart_search_filters.dart';

/// Region shapes come from the same pinned ADM1 data used by the listings API.
/// Decode only when a named province meets a previously applied map constraint.
class GovernorateMapScope {
  static const asset = 'assets/regions/yemen-adm1.geojson';

  static Future<Map<String, Path>> _boundaries() => rootBundle.loadStructuredData(asset, (text) async {
    final data = jsonDecode(text) as Map;
    final regions = <String, Path>{};
    for (final feature in data['features'] as List) {
      final geometry = feature['geometry'] as Map;
      final coordinates = geometry['coordinates'] as List;
      final polygons = geometry['type'] == 'MultiPolygon' ? coordinates : [coordinates];
      final multipart = Path()..fillType = PathFillType.evenOdd;
      for (final polygon in polygons) {
        for (final ring in polygon as List) {
          multipart.addPolygon(_points(ring as List), true);
        }
      }
      regions[feature['properties']['code'] as String] = multipart;
    }
    return regions;
  });

  // Local origin retains sub-metre precision in the native float path engine.
  static Offset _point(num longitude, num latitude) =>
      Offset(longitude.toDouble() - 44, latitude.toDouble() - 15);
  static List<Offset> _points(List ring) => [
    for (final point in ring) _point(point[0] as num, point[1] as num),
  ];

  static Path _viewport(double south, double west, double north, double east) {
    Rect box(double left, double right) =>
        Rect.fromPoints(_point(left, south), _point(right, north));
    if (west <= east) return Path()..addRect(box(west, east));
    return Path()..addRect(box(west, 180))..addRect(box(-180, east));
  }

  static Path? _intersection(Path a, Path b) {
    if (!a.getBounds().overlaps(b.getBounds())) return null;
    final common = Path.combine(PathOperation.intersect, a, b);
    return common.computeMetrics().isEmpty ? null : common;
  }

  /// Keep the deliberate drawing first, then the visible map bounds and any
  /// radius only where the remaining constraints still overlap the new region.
  /// Work on a copy, so an enclosing Home, map or saved search retains its scope.
  static Future<SmartSearchFilters> reconcile(SmartSearchFilters filters, String provinceCode) async {
    final regions = await _boundaries();
    final province = regions[provinceCode];
    if (province == null) throw StateError('Unknown governorate boundary: $provinceCode');
    var remaining = province;
    final values = Map<String, dynamic>.of(filters.values);
    void restrictOrRelease(Path area, List<String> keys) {
      final common = _intersection(remaining, area);
      if (common != null) {
        remaining = common;
      } else {
        for (final key in keys) { values.remove(key); }
      }
    }

    final encoded = values['area_polygon'];
    if (encoded is String) {
      try {
        final ring = MapAreaGeometry.fromEncodedRing(encoded).points;
        final drawn = Path()..addPolygon([
          for (final vertex in ring) _point(vertex.longitude, vertex.latitude),
        ], true);
        restrictOrRelease(drawn, ['area_polygon']);
      } on FormatException {
        // A malformed legacy drawing cannot constrain a newly named province.
        values.remove('area_polygon');
      }
    }
    const viewportKeys = ['south', 'west', 'north', 'east'];
    if (viewportKeys.every((key) => values[key] is num)) {
      double coordinate(String key) => (values[key] as num).toDouble();
      restrictOrRelease(_viewport(coordinate('south'), coordinate('west'),
          coordinate('north'), coordinate('east')), viewportKeys);
    }
    final lat = values['latitude'], lon = values['longitude'], radius = values['radius_km'];
    if (lat is num && lon is num && radius is num && radius > 0) {
      final latitudeDegrees = radius / 6371 * 180 / math.pi;
      // Local tangent-plane bounds for map circles; the listings API applies
      // the actual distance criterion whenever the circle is retained.
      final longitudeDegrees = latitudeDegrees / math.max(1e-6, math.cos(lat * math.pi / 180).abs());
      final rect = Rect.fromCenter(center: _point(lon, lat),
          width: 2 * longitudeDegrees, height: 2 * latitudeDegrees);
      restrictOrRelease(Path()..addOval(rect), ['latitude', 'longitude', 'radius_km']);
    }
    return SmartSearchFilters.fromMap(values);
  }
}

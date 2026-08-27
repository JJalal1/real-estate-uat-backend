import 'package:maplibre_gl/maplibre_gl.dart';

class MapAreaGeometry {
  const MapAreaGeometry._({
    required this.points,
    required this.bounds,
    required this.center,
  });

  factory MapAreaGeometry.fromPoints(List<LatLng> rawPoints) {
    if (rawPoints.length < 3) {
      throw ArgumentError('A map area needs at least three points.');
    }

    final points = List<LatLng>.from(rawPoints);
    if (!_samePoint(points.first, points.last)) {
      points.add(points.first);
    }

    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    var latSum = 0.0;
    var lngSum = 0.0;
    var count = 0;

    for (final point in points.take(points.length - 1)) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
      latSum += point.latitude;
      lngSum += point.longitude;
      count++;
    }

    return MapAreaGeometry._(
      points: List<LatLng>.unmodifiable(points),
      bounds: LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      ),
      center: LatLng(latSum / count, lngSum / count),
    );
  }

  final List<LatLng> points;
  final LatLngBounds bounds;
  final LatLng center;

  bool contains(double latitude, double longitude) {
    var inside = false;
    final ring = points;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final xi = ring[i].longitude;
      final yi = ring[i].latitude;
      final xj = ring[j].longitude;
      final yj = ring[j].latitude;
      final crosses = ((yi > latitude) != (yj > latitude)) &&
          (longitude <
              (xj - xi) *
                      (latitude - yi) /
                      ((yj - yi).abs() < 1.0e-12 ? 1.0e-12 : (yj - yi)) +
                  xi);
      if (crosses) inside = !inside;
    }
    return inside;
  }

  bool get isMeaningful =>
      (bounds.northeast.latitude - bounds.southwest.latitude).abs() > 0.00002 &&
      (bounds.northeast.longitude - bounds.southwest.longitude).abs() > 0.00002;

  static bool _samePoint(LatLng a, LatLng b) {
    return (a.latitude - b.latitude).abs() < 1.0e-9 &&
        (a.longitude - b.longitude).abs() < 1.0e-9;
  }
}

import 'dart:convert';
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

  factory MapAreaGeometry.fromEncodedRing(String encoded) {
    final ring = jsonDecode(encoded);
    if (ring is! List || ring.length < 4 || ring.length > 81) throw const FormatException('Invalid map area.');
    final points = <LatLng>[];
    for (final point in ring) {
      if (point is! List || point.length != 2 || point[0] is! num || point[1] is! num) throw const FormatException('Invalid map point.');
      final lon = (point[0] as num).toDouble(), lat = (point[1] as num).toDouble();
      if (!lat.isFinite || !lon.isFinite || lat.abs() > 90 || lon.abs() > 180) throw const FormatException('Invalid map point.');
      points.add(LatLng(lat, lon));
    }
    if (!_samePoint(points.first, points.last)) throw const FormatException('Open map area.');
    return MapAreaGeometry.fromPoints(points);
  }

  String get encodedRing => jsonEncode(points.map((point) => [point.longitude, point.latitude]).toList(growable: false));

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
      // Include the boundary, matching the server's ST_Covers contract.
      final cross = (longitude - xi) * (yj - yi) - (latitude - yi) * (xj - xi);
      if (cross.abs() < 1.0e-10 &&
          longitude >= (xi < xj ? xi : xj) - 1.0e-10 &&
          longitude <= (xi > xj ? xi : xj) + 1.0e-10 &&
          latitude >= (yi < yj ? yi : yj) - 1.0e-10 &&
          latitude <= (yi > yj ? yi : yj) + 1.0e-10) return true;
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

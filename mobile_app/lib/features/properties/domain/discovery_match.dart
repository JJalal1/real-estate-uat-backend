/// Server classification and ranking data, retained across the list and map.
class DiscoveryMatch {
  const DiscoveryMatch({required this.nearby, this.reasons = const [], this.distanceMetres, this.distanceReference,
    this.criteriaMisses, this.rankDistanceMetres});
  final bool nearby;
  final List<String> reasons;
  final double? distanceMetres;
  final String? distanceReference;
  final int? criteriaMisses;
  final double? rankDistanceMetres;

  static DiscoveryMatch? fromJson(dynamic value) {
    if (value == null) return null; // Legacy exact-only discovery.
    if (value is! Map || !const ['exact', 'nearby'].contains(value['kind']) || value['reasons'] is! List) {
      throw const FormatException('Invalid discovery classification.');
    }
    final reasons = <String>[];
    for (final reason in value['reasons'] as List) {
      if (reason is! Map || reason['message'] is! String || (reason['message'] as String).trim().isEmpty) {
        throw const FormatException('Invalid discovery explanation.');
      }
      reasons.add(reason['message'] as String);
    }
    final nearby = value['kind'] == 'nearby';
    if (nearby && reasons.isEmpty || !nearby && reasons.isNotEmpty) {
      throw const FormatException('Inconsistent discovery explanation.');
    }
    final misses = value['criteria_misses'];
    if (misses != null && (misses is! int || misses < 0 || !nearby && misses != 0)) {
      throw const FormatException('Invalid discovery match degree.');
    }
    return DiscoveryMatch(nearby: nearby, reasons: List.unmodifiable(reasons),
      distanceMetres: _distance(value['distance_m']), distanceReference: value['distance_reference'] as String?,
      criteriaMisses: misses as int?, rankDistanceMetres: _distance(value['rank_distance_m']));
  }

  static double? _distance(dynamic value) {
    if (value == null) return null;
    if (value is! num || !value.isFinite || value < 0) {
      throw const FormatException('Invalid discovery distance.');
    }
    return value.toDouble();
  }
}

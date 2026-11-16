/// Public server explanation, shared by cards, map pins and map results.
class DiscoveryMatch {
  const DiscoveryMatch({required this.nearby, this.reasons = const [], this.distanceMetres, this.distanceReference});
  final bool nearby;
  final List<String> reasons;
  final double? distanceMetres;
  final String? distanceReference;

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
    final distance = value['distance_m'];
    if (distance != null && (distance is! num || !distance.isFinite || distance < 0)) {
      throw const FormatException('Invalid discovery distance.');
    }
    final nearby = value['kind'] == 'nearby';
    if (nearby && reasons.isEmpty || !nearby && reasons.isNotEmpty) {
      throw const FormatException('Inconsistent discovery explanation.');
    }
    return DiscoveryMatch(nearby: nearby, reasons: List.unmodifiable(reasons),
      distanceMetres: (distance as num?)?.toDouble(), distanceReference: value['distance_reference'] as String?);
  }

  String get explanation {
    final distance = distanceMetres;
    final label = distance == null || distance <= 0 ? null : distance < 1000
      ? '${distance < 1 ? 'أقل من متر' : '${distance.round()} مترًا'} عن ${distanceReference == 'drawn_boundary' ? 'حدود الرسم' : 'النطاق المطلوب'}'
      : '${(distance / 1000).toStringAsFixed(1)} كم عن ${distanceReference == 'drawn_boundary' ? 'حدود الرسم' : 'النطاق المطلوب'}';
    return [...reasons, if (label != null) label].join(' · ');
  }
}

class PropertyNearbyLandmark {
  const PropertyNearbyLandmark({required this.name, required this.kind, required this.distanceMetres,
    required this.source, required this.sourceUrl});
  final String name, kind, source, sourceUrl;
  final int distanceMetres;
  static PropertyNearbyLandmark? fromJson(Map<String, dynamic> value) {
    final name = value['name'], kind = value['kind'], distance = value['distance_m'], url = value['source_url'];
    if (name is! String || name.trim().isEmpty || name.length > 200 || kind is! String ||
        distance is! num || !distance.isFinite || distance < 0 || distance > 1000 || url is! String ||
        !RegExp(r'^https://www\.openstreetmap\.org/(node|way|relation)/[1-9][0-9]*$').hasMatch(url)) return null;
    return PropertyNearbyLandmark(name: name, kind: kind, distanceMetres: distance.round(),
      source: value['source'] == 'nominatim' ? 'Nominatim' : 'Photon', sourceUrl: url);
  }
  Map<String, dynamic> toJson() => {'name': name, 'kind': kind, 'distance_m': distanceMetres,
    'source': source.toLowerCase(), 'source_url': sourceUrl};
  String get description => 'قرب $name، على بُعد تقريبي $distanceMetres مترًا بخط مستقيم.';
}

class PropertyLocationAddress {
  const PropertyLocationAddress({this.governorate, this.city, this.district, this.neighborhood, this.street,
    this.formattedAddress, this.sources = const {}, this.providerStatus = '', this.landmarks = const [],
    this.attribution = '', this.legacyMixedArea = false});
  final String? governorate, city, district, neighborhood, street, formattedAddress;
  final Map<String, String> sources;
  final String providerStatus, attribution;
  final List<PropertyNearbyLandmark> landmarks;
  final bool legacyMixedArea;

  bool get isEmpty => [governorate, city, district, neighborhood, street].every((v) => _clean(v) == null);
  bool get isComplete => _clean(governorate) != null && (_clean(district) != null || _clean(neighborhood) != null) && _clean(street) != null;
  int get resolvedFieldCount => [governorate, city, district, neighborhood, street].where((v) => _clean(v) != null).length;
  String get combined {
    // Historical three-part strings retain their existing display. Explicit
    // hierarchy labels let a new address round-trip through the existing column.
    if (_clean(city) == null && _clean(neighborhood) == null) {
      return [governorate, district, street].map(_clean).whereType<String>().join(' - ');
    }
    final fields = {'المحافظة': governorate, 'المدينة': city, 'المديرية': district, 'الحي': neighborhood, 'الشارع': street};
    return fields.entries.where((e) => _clean(e.value) != null).map((e) => '${e.key}: ${e.value!.trim()}').join(' - ');
  }
  factory PropertyLocationAddress.fromJson(Map<String, dynamic> value) => PropertyLocationAddress(
    governorate: _text(value['governorate']), city: _text(value['city']), district: _text(value['district']),
    neighborhood: _text(value['neighborhood']), street: _text(value['street']), formattedAddress: _text(value['formatted_address']),
    providerStatus: _text(value['provider_status']) ?? '', attribution: _text(value['attribution']) ?? '',
    sources: value['field_sources'] is Map ? {for (final e in (value['field_sources'] as Map).entries) if (e.value is String) e.key.toString(): e.value as String} : const {},
    landmarks: [for (final raw in value['landmarks'] is List ? value['landmarks'] as List : const [])
      if (raw is Map) ...[PropertyNearbyLandmark.fromJson(Map<String, dynamic>.from(raw))].whereType<PropertyNearbyLandmark>()],
  );
  Map<String, dynamic> toJson() => {'governorate': governorate, 'city': city, 'district': district, 'neighborhood': neighborhood,
    'street': street, 'formatted_address': formattedAddress, 'field_sources': sources, 'provider_status': providerStatus,
    'attribution': attribution, 'landmarks': landmarks.map((v) => v.toJson()).toList()};
  PropertyLocationAddress mergeFallback(PropertyLocationAddress fallback) => PropertyLocationAddress(
    governorate: _clean(governorate) ?? _clean(fallback.governorate), city: _clean(city) ?? _clean(fallback.city),
    district: _clean(district) ?? _clean(fallback.district), neighborhood: _clean(neighborhood) ?? _clean(fallback.neighborhood),
    street: _clean(street) ?? _clean(fallback.street), formattedAddress: _clean(formattedAddress) ?? _clean(fallback.formattedAddress),
    sources: {...fallback.sources, ...sources}, providerStatus: providerStatus.isEmpty ? fallback.providerStatus : providerStatus,
    attribution: attribution.isEmpty ? fallback.attribution : attribution, landmarks: landmarks.isEmpty ? fallback.landmarks : landmarks,
  );
  static PropertyLocationAddress fromStoredAddress(String? value) {
    final text = _clean(value);
    if (text == null) return const PropertyLocationAddress();
    final parts = text.split(RegExp(r'\s+-\s+')).map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return const PropertyLocationAddress();
    const labels = ['المحافظة', 'المدينة', 'المديرية', 'الحي', 'الشارع'];
    if (parts.first.startsWith('المحافظة:') && parts.every((p) => labels.any((l) => p.startsWith('$l:')))) {
      String? field(String label) { for (final p in parts) { if (p.startsWith('$label:')) return _clean(p.substring(label.length + 1)); } return null; }
      return PropertyLocationAddress(governorate: field('المحافظة'), city: field('المدينة'), district: field('المديرية'),
        neighborhood: field('الحي'), street: field('الشارع'), formattedAddress: text);
    }
    return PropertyLocationAddress(governorate: parts[0], district: parts.length > 1 ? parts[1] : null,
      street: parts.length > 2 ? parts.sublist(2).join(' - ') : null, formattedAddress: text, legacyMixedArea: true);
  }
}
String? _text(dynamic value) => value is String ? _clean(value) : null;
String? _clean(String? value) { final text = value?.trim(); return text == null || text.isEmpty ? null : text; }

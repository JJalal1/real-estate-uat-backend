class PropertyIdentityCandidate {
  const PropertyIdentityCandidate({
    this.listingId,
    this.propertyAssetId,
    required this.published,
    required this.title,
    required this.type,
    required this.distanceM,
    this.areaM2,
  });

  final int? listingId;
  final int? propertyAssetId;
  final bool published;
  final String title;
  final String type;
  final int distanceM;
  final int? areaM2;

  factory PropertyIdentityCandidate.fromJson(Map<String, dynamic> json) {
    return PropertyIdentityCandidate(
      listingId: _int(json['listing_id']),
      propertyAssetId: _int(json['property_asset_id']),
      published: json['published'] == true || json['published'] == 1,
      title: json['title']?.toString() ?? 'عقار مشابه',
      type: json['type']?.toString() ?? '',
      distanceM: _int(json['distance_m']) ?? 0,
      areaM2: _int(json['area_m2']),
    );
  }
}

class PropertyIdentityResult {
  const PropertyIdentityResult({
    required this.decision,
    required this.status,
    required this.score,
    required this.signals,
    required this.message,
    this.candidate,
  });

  final String decision;
  final String status;
  final int score;
  final List<String> signals;
  final String message;
  final PropertyIdentityCandidate? candidate;

  bool get isDistinct => decision == 'distinct';
  bool get isConfirmedDuplicate => decision == 'confirmed_duplicate';
  bool get requiresSelfVerification => status == 'self_verification_required';
  bool get needsSupport => status == 'needs_support';

  factory PropertyIdentityResult.fromJson(Map<String, dynamic> json) {
    final rawCandidate = json['candidate'];
    final rawSignals = json['signals'];
    return PropertyIdentityResult(
      decision: json['decision']?.toString() ?? 'distinct',
      status: json['status']?.toString() ?? 'distinct',
      score: _int(json['score']) ?? 0,
      signals: rawSignals is List
          ? rawSignals.map((value) => value.toString()).toList(growable: false)
          : const <String>[],
      message: json['message']?.toString() ?? '',
      candidate: rawCandidate is Map<String, dynamic>
          ? PropertyIdentityCandidate.fromJson(rawCandidate)
          : null,
    );
  }
}

int? _int(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

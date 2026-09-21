class ListingDuplicateCandidate {
  const ListingDuplicateCandidate({
    required this.listingId,
    required this.propertyAssetId,
    required this.title,
    required this.status,
    required this.reviewStatus,
    required this.distanceM,
    required this.score,
    required this.signals,
    this.address,
    this.areaM2,
    this.bedrooms,
    this.bathrooms,
    this.mainImageId,
  });

  final int listingId;
  final int propertyAssetId;
  final String title;
  final String status;
  final String reviewStatus;
  final int distanceM;
  final int score;
  final List<String> signals;
  final String? address;
  final int? areaM2;
  final int? bedrooms;
  final int? bathrooms;
  final int? mainImageId;

  factory ListingDuplicateCandidate.fromJson(Map<String, dynamic> json) {
    final rawSignals = json['signals'];
    return ListingDuplicateCandidate(
      listingId: _int(json['listing_id']),
      propertyAssetId: _int(json['property_asset_id']),
      title: json['title']?.toString() ?? 'إعلان مشابه',
      status: json['status']?.toString() ?? '',
      reviewStatus: json['review_status']?.toString() ?? '',
      distanceM: _int(json['distance_m']),
      score: _int(json['score']),
      signals: rawSignals is List
          ? rawSignals.map((item) => item.toString()).toList(growable: false)
          : const <String>[],
      address: _string(json['address']),
      areaM2: _nullableInt(json['area_m2']),
      bedrooms: _nullableInt(json['bedrooms']),
      bathrooms: _nullableInt(json['bathrooms']),
      mainImageId: _nullableInt(json['main_image_id']),
    );
  }

  String get severityLabel => score >= 10
      ? 'اشتباه قوي جداً'
      : score >= 8
          ? 'اشتباه قوي'
          : 'يحتاج مراجعة';

  List<String> get signalLabels => signals.map((signal) {
        return switch (signal) {
          'same_property_asset' => 'نفس هوية العقار الفيزيائية',
          'location_within_30m' => 'الموقع ضمن 30 متر',
          'location_within_100m' => 'الموقع ضمن 100 متر',
          'location_within_250m' => 'الموقع ضمن 250 متر',
          'address_exact_normalized' => 'العنوان متطابق بعد التنظيف',
          'address_high_similarity' => 'تشابه مرتفع في العنوان',
          'address_partial_similarity' => 'تشابه جزئي في العنوان',
          'area_within_5_percent' => 'المساحة متقاربة جداً',
          'area_within_10_percent' => 'المساحة متقاربة',
          'bedrooms_equal' => 'عدد الغرف مطابق',
          'bathrooms_equal' => 'عدد الحمامات مطابق',
          _ => signal,
        };
      }).toList(growable: false);
}

int _int(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _nullableInt(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

String? _string(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

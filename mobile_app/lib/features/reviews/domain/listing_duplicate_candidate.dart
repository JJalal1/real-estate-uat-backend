enum ListingDuplicateSource { algorithm, ai }

class ListingDuplicateDetection {
  const ListingDuplicateDetection({required this.source, this.reason});

  final ListingDuplicateSource source;
  final String? reason;

  static ListingDuplicateDetection? fromJson(Map<String, dynamic> json) {
    final source = switch (json['duplicate_detection_source']) {
      'algorithm' => ListingDuplicateSource.algorithm,
      'ai' => ListingDuplicateSource.ai,
      _ => null,
    };
    if (source == null) return null;
    return ListingDuplicateDetection(
      source: source,
      reason: _string(json['duplicate_detection_reason']),
    );
  }
}

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
    this.published,
    this.detection,
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
  final bool? published;
  final ListingDuplicateDetection? detection;

  bool get canRejectAsDuplicate =>
      listingId > 0 && (published ?? (status == 'published'));

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
      published: json['published'] is bool ? json['published'] as bool : null,
      detection: ListingDuplicateDetection.fromJson(json),
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
          'same_building_same_unit' => 'المبنى والوحدة متطابقان',
          'nearby_unit_requires_building_review' => 'وحدة قريبة تحتاج إلى مقارنة بيانات المبنى',
          'same_explicit_house_reference' => 'رقم المنزل مطابق',
          'location_within_25m' => 'الموقع ضمن 25 متر',
          'location_within_30m' => 'الموقع ضمن 30 متر',
          'location_within_40m' => 'الموقع ضمن 40 متر',
          'location_within_60m' => 'الموقع ضمن 60 متر',
          'location_within_100m' => 'الموقع ضمن 100 متر',
          'location_within_120m' => 'الموقع ضمن 120 متر',
          'location_within_250m' => 'الموقع ضمن 250 متر',
          'address_exact_normalized' => 'العنوان متطابق بعد التنظيف',
          'address_high_similarity' => 'تشابه مرتفع في العنوان',
          'address_partial_similarity' => 'تشابه جزئي في العنوان',
          'area_within_5_percent' => 'المساحة متقاربة جداً',
          'area_within_10_percent' => 'المساحة متقاربة',
          'area_within_12_percent' => 'فرق المساحة حتى 12٪',
          'area_within_20_percent' => 'فرق المساحة حتى 20٪',
          'bedrooms_equal' => 'عدد الغرف مطابق',
          'bathrooms_equal' => 'عدد الحمامات مطابق',
          'facade_equal' => 'واجهة المبنى متطابقة في المواصفات',
          'land_overlap_85_percent' => 'تداخل حدود الأرض بنسبة 85٪ فأكثر',
          'land_overlap_50_percent' => 'تداخل حدود الأرض بنسبة 50٪ فأكثر',
          'land_overlap_20_percent' => 'تداخل حدود الأرض بنسبة 20٪ فأكثر',
          'land_boundaries_distinct' => 'حدود الأرض مختلفة',
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

class PropertyMarketContext {
  const PropertyMarketContext({
    required this.sufficientData,
    required this.sampleCount,
    required this.minimumSampleSize,
    this.message,
    this.radiusKm,
    this.medianPrice,
    this.medianPricePerM2,
    this.lowerQuartilePrice,
    this.upperQuartilePrice,
    this.deltaFromMedianPercent,
    this.position,
    this.disclaimer,
  });

  final bool sufficientData;
  final int sampleCount;
  final int minimumSampleSize;
  final String? message;
  final double? radiusKm;
  final double? medianPrice;
  final double? medianPricePerM2;
  final double? lowerQuartilePrice;
  final double? upperQuartilePrice;
  final double? deltaFromMedianPercent;
  final String? position;
  final String? disclaimer;

  factory PropertyMarketContext.fromJson(Map<String, dynamic> json) {
    final market = json['market'] is Map<String, dynamic>
        ? json['market'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final target = json['target'] is Map<String, dynamic>
        ? json['target'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final basis = json['basis'] is Map<String, dynamic>
        ? json['basis'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return PropertyMarketContext(
      sufficientData: json['sufficient_data'] == true,
      sampleCount: _int(json['sample_count']),
      minimumSampleSize: _int(json['minimum_sample_size'], fallback: 5),
      message: _text(json['message']),
      radiusKm: _double(basis['radius_km']),
      medianPrice: _double(market['median_price']),
      medianPricePerM2: _double(market['median_price_per_m2']),
      lowerQuartilePrice: _double(market['lower_quartile_price']),
      upperQuartilePrice: _double(market['upper_quartile_price']),
      deltaFromMedianPercent: _double(target['delta_from_median_percent']),
      position: _text(target['position']),
      disclaimer: _text(json['disclaimer']),
    );
  }
}

int _int(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

double? _double(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

String? _text(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

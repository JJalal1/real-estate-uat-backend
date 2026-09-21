import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

final propertyMarketRepositoryProvider = Provider<PropertyMarketRepository>((ref) {
  return PropertyMarketRepository(ref.watch(dioProvider));
});

class PropertyMarketRepository {
  const PropertyMarketRepository(this._dio);

  final Dio _dio;

  Future<PropertyMarketContext> context(int propertyId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/properties/$propertyId/market-context',
    );
    final raw = response.data?['data'];
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Invalid property market context response.');
    }
    return PropertyMarketContext.fromJson(raw);
  }
}

class PropertyMarketContext {
  const PropertyMarketContext({
    required this.sufficientData,
    required this.sampleCount,
    this.minimumSampleSize,
    this.message,
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
  final int? minimumSampleSize;
  final String? message;
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
    return PropertyMarketContext(
      sufficientData: json['sufficient_data'] == true,
      sampleCount: _int(json['sample_count']) ?? 0,
      minimumSampleSize: _int(json['minimum_sample_size']),
      message: _text(json['message']),
      medianPrice: _double(market['median_price']),
      medianPricePerM2: _double(market['median_price_per_m2']),
      lowerQuartilePrice: _double(market['lower_quartile_price']),
      upperQuartilePrice: _double(market['upper_quartile_price']),
      deltaFromMedianPercent: _double(target['delta_from_median_percent']),
      position: _text(target['position']),
      disclaimer: _text(json['disclaimer']),
    );
  }

  String get positionLabel => switch (position) {
        'below_comparable_median' => 'أقل من وسيط العقارات المقارنة',
        'above_comparable_median' => 'أعلى من وسيط العقارات المقارنة',
        'near_comparable_median' => 'قريب من وسيط العقارات المقارنة',
        _ => 'لا توجد مقارنة كافية',
      };
}

String? _text(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int? _int(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

double? _double(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

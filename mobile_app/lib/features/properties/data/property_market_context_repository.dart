import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/property_market_context.dart';

final propertyMarketContextRepositoryProvider =
    Provider<PropertyMarketContextRepository>((ref) {
  return PropertyMarketContextRepository(ref.watch(dioProvider));
});

final propertyMarketContextProvider = FutureProvider.autoDispose
    .family<PropertyMarketContext, int>((ref, propertyId) {
  return ref.watch(propertyMarketContextRepositoryProvider).load(propertyId);
});

class PropertyMarketContextRepository {
  PropertyMarketContextRepository(this._dio);

  final Dio _dio;

  Future<PropertyMarketContext> load(int propertyId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/properties/$propertyId/market-context',
    );
    final data = response.data?['data'];
    if (data is! Map<String, dynamic>) {
      throw StateError('Invalid market context response.');
    }
    return PropertyMarketContext.fromJson(data);
  }
}

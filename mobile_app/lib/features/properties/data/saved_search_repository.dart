import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../account/data/auth_repository.dart';
import '../domain/property_marker.dart';
import '../domain/saved_property_search.dart';

final savedSearchRepositoryProvider = Provider<SavedSearchRepository>((ref) {
  return SavedSearchRepository(
    ref.watch(dioProvider),
    ref.watch(authRepositoryProvider),
  );
});

final savedSearchRevisionProvider = StateProvider<int>((ref) => 0);

final savedSearchesProvider =
    FutureProvider.autoDispose<List<SavedPropertySearch>>((ref) {
  ref.watch(savedSearchRevisionProvider);
  return ref.watch(savedSearchRepositoryProvider).all();
});

class SavedSearchRepository {
  SavedSearchRepository(this._dio, this._auth);

  final Dio _dio;
  final AuthRepository _auth;

  Future<List<SavedPropertySearch>> all() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/saved-searches',
      options: await _auth.requiredAuthOptions(),
    );
    final rows = response.data?['data'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(SavedPropertySearch.fromJson)
        .toList(growable: false);
  }

  Future<SavedPropertySearch> create({
    required String name,
    required Map<String, dynamic> filters,
    String alertFrequency = 'instant',
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/saved-searches',
      data: {
        'name': name,
        'filters': filters,
        'alert_frequency': alertFrequency,
      },
      options: await _auth.requiredAuthOptions(),
    );
    final data = response.data?['data'];
    if (data is! Map<String, dynamic>) {
      throw StateError('Saved search response is missing data.');
    }
    return SavedPropertySearch.fromJson(data);
  }

  Future<List<PropertyMarker>> results(SavedPropertySearch search) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/properties',
      queryParameters: {
        ...search.filters,
        'per_page': 50,
        'sort': 'latest',
      },
    );
    final rows = response.data?['data'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(PropertyMarker.fromJson)
        .toList(growable: false);
  }

  Future<void> updateAlert(
    int id, {
    required String alertFrequency,
    bool? isActive,
  }) async {
    await _dio.patch<Map<String, dynamic>>(
      '/saved-searches/$id',
      data: {
        'alert_frequency': alertFrequency,
        if (isActive != null) 'is_active': isActive,
      },
      options: await _auth.requiredAuthOptions(),
    );
  }

  Future<void> delete(int id) async {
    await _dio.delete<Map<String, dynamic>>(
      '/saved-searches/$id',
      options: await _auth.requiredAuthOptions(),
    );
  }
}

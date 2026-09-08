import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../account/data/auth_repository.dart';
import '../domain/property_marker.dart';

final favoritesRepositoryProvider = Provider<FavoritesRepository>((ref) {
  return FavoritesRepository(
    ref.watch(dioProvider),
    ref.watch(authRepositoryProvider),
  );
});

/// Bumped after any successful favorite mutation so details, cards and the
/// Favorites screen converge on the same server-owned state.
final favoriteDataRevisionProvider = StateProvider<int>((ref) => 0);

final favoritePropertiesProvider =
    FutureProvider.autoDispose<List<PropertyMarker>>((ref) {
  ref.watch(favoriteDataRevisionProvider);
  return ref.watch(favoritesRepositoryProvider).favorites();
});

final favoritePropertyIdsProvider =
    FutureProvider.autoDispose<Set<int>>((ref) {
  ref.watch(favoriteDataRevisionProvider);
  return ref.watch(favoritesRepositoryProvider).favoriteIds();
});

class FavoritesRepository {
  FavoritesRepository(this._dio, this._auth);

  final Dio _dio;
  final AuthRepository _auth;

  Future<List<PropertyMarker>> favorites() async {
    final options = await _auth.requiredAuthOptions();
    final items = <PropertyMarker>[];
    var page = 1;
    var lastPage = 1;

    do {
      final response = await _dio.get<Map<String, dynamic>>(
        '/favorites',
        queryParameters: {'page': page, 'per_page': 50},
        options: options,
      );
      final rows = response.data?['data'];
      if (rows is List) {
        for (final row in rows.whereType<Map<String, dynamic>>()) {
          final property = row['property'];
          if (property is Map<String, dynamic>) {
            items.add(PropertyMarker.fromJson(property));
          }
        }
      }

      final meta = response.data?['meta'];
      lastPage = meta is Map<String, dynamic>
          ? _positiveInt(meta['last_page'], fallback: page)
          : page;
      page++;
    } while (page <= lastPage && page <= 100);

    return List<PropertyMarker>.unmodifiable(items);
  }

  Future<Set<int>> favoriteIds() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/favorites/ids',
      options: await _auth.requiredAuthOptions(),
    );
    final data = response.data?['data'];
    final raw = data is Map<String, dynamic> ? data['property_ids'] : null;
    if (raw is! List) return <int>{};

    return raw
        .map(_asInt)
        .whereType<int>()
        .where((id) => id > 0)
        .toSet();
  }

  Future<bool> isFavorite(int propertyId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/properties/$propertyId/favorite',
      options: await _auth.requiredAuthOptions(),
    );
    final data = response.data?['data'];
    return data is Map<String, dynamic> && data['is_favorited'] == true;
  }

  Future<void> add(int propertyId) async {
    await _dio.put<Map<String, dynamic>>(
      '/properties/$propertyId/favorite',
      options: await _auth.requiredAuthOptions(),
    );
  }

  Future<void> remove(int propertyId) async {
    await _dio.delete<Map<String, dynamic>>(
      '/properties/$propertyId/favorite',
      options: await _auth.requiredAuthOptions(),
    );
  }

  int _positiveInt(dynamic value, {required int fallback}) {
    final parsed = _asInt(value);
    return parsed != null && parsed > 0 ? parsed : fallback;
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

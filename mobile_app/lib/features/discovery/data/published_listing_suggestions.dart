import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../account/data/auth_controller.dart';
import '../../properties/data/property_repository.dart';
import '../../properties/domain/property_details.dart';
import '../domain/smart_search_filters.dart';
import 'discovery_suggestions.dart';

String publishedSuggestionKey(SmartSearchFilters filters) {
  final values = filters.apiFilters, keys = values.keys.toList()..sort();
  return jsonEncode({for (final key in keys) key: values[key]});
}

class PublishedListingSuggestions {
  PublishedListingSuggestions(this.dio, {DateTime Function()? now}) : now = now ?? DateTime.now;
  final Dio dio;
  final DateTime Function() now;
  final _cache = <String, ({DateTime at, List<PropertySummary> rows})>{};
  static const limit = 6;
  static const ttl = Duration(seconds: 10);

  List<PropertySummary> cached(String key) {
    final result = _cache[key];
    if (result == null || now().difference(result.at) > ttl) { _cache.remove(key); return const []; }
    return result.rows;
  }
  Future<List<PropertySummary>> load(String key, CancelToken transfer) async {
    final filters = Map<String, dynamic>.from(jsonDecode(key) as Map);
    final text = filters['search']?.toString().trim() ?? '';
    if (text.isEmpty || text.length > 120 || transfer.isCancelled) return const [];
    final response = await dio.get<Map<String, dynamic>>('/properties', queryParameters: {
      ...filters, 'page': 1, 'per_page': limit, 'sort': 'latest',
    }, cancelToken: transfer, options: Options(receiveTimeout: const Duration(seconds: 12)));
    if (transfer.isCancelled) throw transfer.cancelError!;
    final raw = response.data?['data'];
    if (raw is! List) throw const FormatException('Invalid public suggestions response');
    final seen = <int>{}, tokens = normalizeDiscoveryText(text).split(' ');
    final rows = raw.whereType<Map>().map((r) => PropertySummary.fromJson(Map<String, dynamic>.from(r)))
      .where((r) => r.id > 0 && r.status == 'published' && seen.add(r.id)
        && (filters['purpose'] == null || r.purpose == filters['purpose'])
        && (filters['type'] == null || r.type == filters['type'] || (filters['type'] == 'apartment' && r.type == 'floor')))
      // Description may match even when title/address do not; the server owns
      // normalized AND-token relevance and all visibility/availability checks.
      .take(limit).toList(growable: false);
    if (tokens.every((t) => t.isEmpty)) return const [];
    _cache[key] = (at: now(), rows: List.unmodifiable(rows));
    while (_cache.length > 12) { _cache.remove(_cache.keys.first); }
    return rows;
  }
  void clear() => _cache.clear();
}

final publishedListingSuggestionsRepositoryProvider = Provider<PublishedListingSuggestions>((ref) {
  ref.watch(authControllerProvider.select((value) => value.asData?.value?.id));
  ref.watch(propertyDataRevisionProvider);
  final repo = PublishedListingSuggestions(ref.watch(dioProvider));
  ref.onDispose(repo.clear);
  return repo;
});
final publishedListingSuggestionsProvider = FutureProvider.autoDispose.family<List<PropertySummary>, String>((ref, key) async {
  final repo = ref.watch(publishedListingSuggestionsRepositoryProvider), transfer = CancelToken();
  ref.onDispose(() => transfer.cancel('Suggestions changed or account left'));
  await Future<void>.delayed(const Duration(milliseconds: 250));
  if (transfer.isCancelled) return const [];
  return repo.load(key, transfer);
});

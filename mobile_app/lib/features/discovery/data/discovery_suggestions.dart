import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/network/api_client.dart';
import '../../broker/domain/broker_models.dart';
import '../../map/domain/map_area_geometry.dart';
import '../../properties/domain/property_coordinates.dart';
import '../domain/smart_search_filters.dart';
import 'marketplace_repository.dart';

String normalizeDiscoveryText(String value) => value.trim().toLowerCase()
  .replaceAll(RegExp(r'[أإآ]'), 'ا').replaceAll('ى', 'ي')
  .replaceAll(RegExp(r'[\u064B-\u065F\u0670ـ]'), '')
  .replaceAll(RegExp(r'\s+'), ' ');

class DiscoverySuggestion {
  const DiscoverySuggestion({required this.label, required this.kind, this.type, this.location});
  final String label, kind;
  final String? type;
  final HomeLocation? location;
}

class DiscoverySearchChoice {
  const DiscoverySearchChoice(this.text, {this.suggestion});
  final String text;
  final DiscoverySuggestion? suggestion;
}

class DiscoverySuggestionsRepository {
  DiscoverySuggestionsRepository(this._dio);
  final Dio _dio;
  Future<List<Map<String, dynamic>>> _areaRows(String query, CancelToken? cancelToken) async {
    final response = await _dio.get<Map<String, dynamic>>('/regions/cells',
      queryParameters: {'search': query, 'limit': 6}, cancelToken: cancelToken);
    return brokerRows(response.data?['data']);
  }

  Future<List<DiscoverySuggestion>> areas(String query, {CancelToken? cancelToken}) async {
    final rows = await _areaRows(query, cancelToken);
    final normalized = normalizeDiscoveryText(query), result = <DiscoverySuggestion>[];
    for (final row in rows.whereType<Map>()) {
      if (row['is_active'] != true || row['name_ar'] is! String) continue;
      final label = row['name_ar'] as String;
      if (!normalizeDiscoveryText(label).contains(normalized)) continue;
      result.add(DiscoverySuggestion(label: label, kind: 'حي / منطقة'));
      if (result.length == 6) break;
    }
    return result;
  }

  Future<List<MapAddressMatch>> areasOnMap(String query, CancelToken cancelToken) async {
    final rows = await _areaRows(query, cancelToken);
    return rows.map(_registeredArea).whereType<MapAddressMatch>().toList(growable: false);
  }

  MapAddressMatch? _registeredArea(Map<String, dynamic> row) {
    final name = row['name_ar'];
    final boundary = row['boundary'];
    if (row['is_active'] != true || name is! String || name.trim().isEmpty ||
        boundary is! Map || boundary['type'] != 'Polygon') {
      return null;
    }
    final rings = boundary['coordinates'];
    if (rings is! List || rings.isEmpty || rings.first is! List) return null;
    final points = <LatLng>[];
    for (final coordinate in rings.first as List) {
      if (coordinate is! List || coordinate.length < 2) return null;
      final lon = coordinate[0], lat = coordinate[1];
      if (lon is! num || lat is! num ||
          !hasValidPropertyCoordinates(lat.toDouble(), lon.toDouble())) {
        return null;
      }
      points.add(LatLng(lat.toDouble(), lon.toDouble()));
    }
    if (points.length < 4) return null;
    final center = MapAreaGeometry.fromPoints(points).center;
    final governorate = row['governorate'];
    final province = governorate is Map ? governorate['name_ar'] : null;
    return MapAddressMatch(
      label: province is String && province.isNotEmpty && province != name ? '$name، $province' : name,
      latitude: center.latitude, longitude: center.longitude, zoom: 14, partial: true,
    );
  }
}

final discoverySuggestionsRepositoryProvider = Provider<DiscoverySuggestionsRepository>((ref) =>
  DiscoverySuggestionsRepository(ref.watch(dioProvider)));

final discoverySuggestionsProvider = FutureProvider.autoDispose.family<List<DiscoverySuggestion>, String>((ref, text) async {
  final query = text.trim();
  if (query.length < 2 || query.length > 120) return const [];
  final transfer = CancelToken();
  ref.onDispose(() => transfer.cancel('Suggestion superseded'));
  await Future<void>.delayed(const Duration(milliseconds: 250));
  if (transfer.isCancelled) return const [];
  final normal = normalizeDiscoveryText(query), suggestions = <DiscoverySuggestion>[];
  for (final entry in SmartSearchFilters.types.entries) {
    if (normalizeDiscoveryText(entry.value).contains(normal)) {
      suggestions.add(DiscoverySuggestion(label: entry.value, kind: 'نوع العقار', type: entry.key));
    }
  }
  // Registry locations are already shared/cached with Home. A source failure
  // never invents areas or prevents the user submitting their own text.
  try {
    final locations = await ref.watch(homeLocationsProvider.future);
    for (final location in locations) {
      if (normalizeDiscoveryText(location.label).contains(normal)) {
        suggestions.add(DiscoverySuggestion(label: location.label, kind: 'محافظة', location: location));
      }
    }
  } catch (_) { /* Other real sources and free text remain available. */ }
  if (transfer.isCancelled) return const [];
  try {
    suggestions.addAll(await ref.read(discoverySuggestionsRepositoryProvider).areas(query, cancelToken: transfer));
  } catch (_) { /* Typed search is independent of autocomplete availability. */ }
  final seen = <String>{};
  return suggestions.where((item) => seen.add('${item.kind}:${item.label}')).take(8).toList(growable: false);
});

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../broker/domain/broker_models.dart';
import '../../properties/data/property_repository.dart';
import '../../properties/domain/property_details.dart';
import '../domain/smart_search_filters.dart';

class HomeLocation {
  const HomeLocation({this.latitude = 15.3694, this.longitude = 44.1910, this.governorate, this.governorateCode,
    this.label = 'صنعاء', this.manual = false, this.device = false, this.accuracyMetres, this.needsConfirmation = false});
  final double latitude, longitude;
  final String? governorate, governorateCode;
  final String label;
  final bool manual, device, needsConfirmation;
  final double? accuracyMetres;
  Map<String, dynamic> get searchContext => !manual && !device && governorate == null ? const {} : {
    if (governorate != null && !needsConfirmation) 'governorate': governorate,
    if (governorateCode != null && !needsConfirmation) 'governorate_code': governorateCode,
    // A manual governorate covers its complete boundary, not a city-center circle.
    if (device) ...{'latitude': latitude, 'longitude': longitude, 'radius_km': 30},
  };
  factory HomeLocation.fromJson(Map<String, dynamic> j) => HomeLocation(
    latitude: (j['latitude'] as num).toDouble(), longitude: (j['longitude'] as num).toDouble(),
    governorate: j['governorate']?.toString(), governorateCode: j['governorate_code']?.toString(),
    label: j['label']?.toString() ?? 'المنطقة', manual: true);
}

class HomeFeedQuery {
  const HomeFeedQuery({required this.latitude, required this.longitude, this.governorate, this.governorateCode, this.accuracyMetres, this.type, this.purpose,
    required this.device, this.filters = const SmartSearchFilters()});
  final double latitude, longitude;
  final String? governorate, governorateCode, type, purpose;
  final double? accuracyMetres;
  final bool device;
  final SmartSearchFilters filters;
  SmartSearchFilters get effectiveFilters => SmartSearchFilters.fromMap({...filters.values,
    if (type != null) 'type': type, if (purpose != null) 'purpose': purpose});
  @override
  bool operator ==(Object other) => other is HomeFeedQuery && other.latitude == latitude && other.longitude == longitude &&
    other.governorate == governorate && other.governorateCode == governorateCode && other.accuracyMetres == accuracyMetres && other.device == device && effectiveFilters.sameAs(other.effectiveFilters);
  @override
  int get hashCode => Object.hash(latitude, longitude, governorate, governorateCode, accuracyMetres, device, effectiveFilters.signature);
}

class MarketplaceFeed {
  const MarketplaceFeed({required this.label, this.governorate, this.source = 'default', this.sections = const {}, this.brokers = const [], this.sectionOrder = const ['spotlight','latest','sale','rent']});
  final String label;
  final String? governorate;
  final String source;
  final Map<String, List<PropertySummary>> sections;
  final List<BrokerProfile> brokers;
  final List<String> sectionOrder;
  factory MarketplaceFeed.fromJson(Map<String, dynamic> j) {
    final context = brokerMap(j['context']), sections = brokerMap(j['sections']);
    return MarketplaceFeed(label: context['label']?.toString() ?? 'صنعاء', governorate: context['governorate']?.toString(),
      sectionOrder:(j['section_order'] as List? ?? const ['spotlight','latest','sale','rent']).whereType<String>().where((key)=>const ['nearby','spotlight','latest','sale','rent'].contains(key)).toList(),
      source: context['source']?.toString() ?? 'default', brokers: brokerRows(j['brokers']).map(BrokerProfile.fromJson).toList(growable: false),
      sections: {for (final key in const ['nearby', 'spotlight', 'latest', 'sale', 'rent']) key: brokerRows(sections[key]).map(PropertySummary.fromJson).toList(growable: false)});
  }
}

class MarketplaceRepository {
  MarketplaceRepository(this._dio, {DateTime Function()? now}) : _now = now ?? DateTime.now;
  final Dio _dio;
  final DateTime Function() _now;
  final _cache = <({HomeFeedQuery query, int revision}), ({DateTime at, MarketplaceFeed feed})>{};
  int _cacheEpoch = 0;
  void invalidateFeed(HomeFeedQuery query) { _cacheEpoch++; _cache.removeWhere((key, _) => key.query == query); }
  Future<MarketplaceFeed> feed(HomeFeedQuery query, {CancelToken? cancelToken, int cacheRevision = 0}) async {
    if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
    final key = (query: query, revision: cacheRevision), now = _now(), epoch = _cacheEpoch;
    _cache.removeWhere((_, entry) => now.difference(entry.at) > const Duration(seconds: 20));
    final cached = _cache[key];
    if (cached != null) return cached.feed;
    final filters = query.effectiveFilters.apiFilters;
    final r = await _dio.get<Map<String, dynamic>>('/marketplace', queryParameters: {
      ...filters,
      if (!query.device && query.governorate != null) 'governorate': query.governorate,
      if (!query.device && query.governorateCode != null) 'governorate_code': query.governorateCode,
      if (query.device) ...{'latitude': query.latitude, 'longitude': query.longitude,
        if (query.accuracyMetres != null) 'accuracy_m': query.accuracyMetres},
    }, cancelToken: cancelToken, options: Options(listFormat: ListFormat.multiCompatible));
    ensurePropertyFilterContract(r, filters, requireAcknowledgement: filters.keys.any((key) => !const ['type', 'purpose'].contains(key)));
    final body = r.data?['data'];
    if (body is! Map) throw StateError('Invalid marketplace response.');
    var feed = MarketplaceFeed.fromJson(Map<String, dynamic>.from(body));
    final purpose = filters['purpose'];
    if (purpose != null && brokerMap(body['context'])['purpose'] != purpose) {
      // Older UAT servers do not accept a purpose on /marketplace. Obtain all
      // displayed property rows from the existing server-filtered public API;
      // never present, or merely hide locally, an unscoped marketplace feed.
      final keys = [if (query.device && query.governorate == null) 'nearby', 'spotlight', 'latest'];
      final sections = await Future.wait(keys.map((section) async {
        final response = await _dio.get<Map<String, dynamic>>('/properties', queryParameters: {
          ...filters, 'per_page': 6, 'sort': 'latest',
          if (section == 'nearby') ...{'latitude': query.latitude, 'longitude': query.longitude, 'radius_km': 30}
          else if (feed.governorate != null) 'governorate': feed.governorate,
          if (section == 'spotlight') 'spotlight': 1,
        }, cancelToken: cancelToken, options: Options(listFormat: ListFormat.multiCompatible));
        ensurePropertyFilterContract(response, filters);
        return MapEntry(section, brokerRows(response.data?['data']).map(PropertySummary.fromJson).toList(growable: false));
      }));
      feed = MarketplaceFeed(label: feed.label, governorate: feed.governorate, source: feed.source,
        brokers: feed.brokers, sections: Map.fromEntries(sections), sectionOrder: keys);
    }
    if (purpose != null && feed.sections.values.expand((rows) => rows).any((row) => row.purpose != purpose)) {
      throw StateError('The public server returned properties for another purpose.');
    }
    if (cancelToken?.isCancelled != true && epoch == _cacheEpoch) {
      _cache[key] = (at: _now(), feed: feed);
      while (_cache.length > 8) { _cache.remove(_cache.keys.first); }
    }
    return feed;
  }
  Future<HomeLocation> resolveLocation(HomeLocation fix) async {
    final r = await _dio.get<Map<String, dynamic>>('/marketplace/location-context', queryParameters: {
      'latitude': fix.latitude, 'longitude': fix.longitude,
      if (fix.accuracyMetres != null) 'accuracy_m': fix.accuracyMetres,
    });
    final body = r.data?['data'];
    if (body is! Map || body['source'] != 'device') throw StateError('Invalid location context.');
    return HomeLocation(latitude: fix.latitude, longitude: fix.longitude, accuracyMetres: fix.accuracyMetres,
      governorate: body['governorate']?.toString(), governorateCode: body['governorate_code']?.toString(),
      label: body['needs_confirmation'] == false ? (body['label']?.toString() ?? 'اختر محافظتك') : 'أكّد المحافظة', device: true, needsConfirmation: body['needs_confirmation'] != false);
  }
  Future<List<HomeLocation>> locations() async {
    final r = await _dio.get<Map<String, dynamic>>('/marketplace/locations');
    return brokerRows(r.data?['data']).where((row) => row['latitude'] is num && row['longitude'] is num).map(HomeLocation.fromJson).toList(growable: false);
  }
}

final marketplaceRepositoryProvider = Provider<MarketplaceRepository>((ref) => MarketplaceRepository(ref.watch(dioProvider)));
final homeLocationProvider = StateProvider<HomeLocation>((ref) => const HomeLocation());
final homeLocationAttemptedProvider = StateProvider<bool>((ref) => false);
final homeLocationsProvider = FutureProvider<List<HomeLocation>>((ref) => ref.watch(marketplaceRepositoryProvider).locations());
final marketplaceFeedProvider = FutureProvider.autoDispose.family<MarketplaceFeed, HomeFeedQuery>((ref, query) async {
  final revision = ref.watch(propertyDataRevisionProvider);
  final transfer = CancelToken();
  ref.onDispose(() => transfer.cancel('Marketplace disposed'));
  return ref.watch(marketplaceRepositoryProvider).feed(query, cancelToken: transfer, cacheRevision: revision);
});

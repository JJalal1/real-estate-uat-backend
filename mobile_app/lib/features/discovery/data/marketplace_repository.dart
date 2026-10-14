import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/public_startup_read.dart';
import '../../broker/domain/broker_models.dart';
import '../../properties/data/property_repository.dart';
import '../../properties/domain/property_details.dart';

class HomeLocation {
  const HomeLocation({this.latitude = 15.3694, this.longitude = 44.1910, this.governorate,
    this.label = 'صنعاء', this.manual = false, this.device = false});
  final double latitude, longitude;
  final String? governorate;
  final String label;
  final bool manual;
  final bool device;
  factory HomeLocation.fromJson(Map<String, dynamic> j) => HomeLocation(
    latitude: (j['latitude'] as num).toDouble(), longitude: (j['longitude'] as num).toDouble(),
    governorate: j['governorate']?.toString(), label: j['label']?.toString() ?? 'المنطقة', manual: true);
}

typedef HomeFeedQuery = ({double latitude, double longitude, String? governorate, String? type, bool device});

class MarketplaceFeed {
  const MarketplaceFeed({required this.label, this.governorate, this.source = 'default', this.sections = const {}, this.brokers = const []});
  final String label;
  final String? governorate;
  final String source;
  final Map<String, List<PropertySummary>> sections;
  final List<BrokerProfile> brokers;
  factory MarketplaceFeed.fromJson(Map<String, dynamic> j) {
    final context = brokerMap(j['context']), sections = brokerMap(j['sections']);
    return MarketplaceFeed(label: context['label']?.toString() ?? 'صنعاء', governorate: context['governorate']?.toString(),
      source: context['source']?.toString() ?? 'default', brokers: brokerRows(j['brokers']).map(BrokerProfile.fromJson).toList(growable: false),
      sections: {for (final key in const ['spotlight', 'latest', 'sale', 'rent']) key: brokerRows(sections[key]).map(PropertySummary.fromJson).toList(growable: false)});
  }
}

class MarketplaceRepository {
  MarketplaceRepository(Dio dio, {bool? startupRecovery})
      : _reads = PublicStartupRead(dio,
          enabled: startupRecovery ?? ApiEnvironmentConfig.isUat);
  final PublicStartupRead _reads;
  Future<MarketplaceFeed> feed(HomeFeedQuery query, {CancelToken? cancelToken}) async {
    final r = await _reads.get('/marketplace', cancelToken: cancelToken, queryParameters: {
      if (query.governorate != null) 'governorate': query.governorate,
      if (query.governorate == null && query.device) ...{'latitude': query.latitude, 'longitude': query.longitude},
      if (query.type != null) 'type': query.type,
    });
    final body = r.data?['data'];
    if (body is! Map) throw StateError('Invalid marketplace response.');
    return MarketplaceFeed.fromJson(Map<String, dynamic>.from(body));
  }
  Future<List<HomeLocation>> locations({CancelToken? cancelToken}) async {
    final r = await _reads.get('/marketplace/locations', cancelToken: cancelToken);
    return brokerRows(r.data?['data']).where((row) => row['latitude'] is num && row['longitude'] is num).map(HomeLocation.fromJson).toList(growable: false);
  }
}

final marketplaceRepositoryProvider = Provider<MarketplaceRepository>((ref) => MarketplaceRepository(ref.watch(dioProvider)));
final homeLocationProvider = StateProvider<HomeLocation>((ref) => const HomeLocation());
final homeLocationAttemptedProvider = StateProvider<bool>((ref) => false);
final homeLocationsProvider = FutureProvider<List<HomeLocation>>((ref) {
  final token = CancelToken();
  ref.onDispose(() => token.cancel('Home locations disposed'));
  return ref.watch(marketplaceRepositoryProvider).locations(cancelToken: token);
});
final marketplaceFeedProvider = FutureProvider.autoDispose.family<MarketplaceFeed, HomeFeedQuery>((ref, query) async {
  ref.watch(propertyDataRevisionProvider);
  final token = CancelToken();
  ref.onDispose(() => token.cancel('Home feed disposed'));
  final result = await ref.watch(marketplaceRepositoryProvider).feed(query, cancelToken: token);
  if (token.isCancelled) throw token.cancelError!;
  // Preserve only successful public results during short trips to another tab.
  final link = ref.keepAlive();
  final expiry = Timer(const Duration(seconds: 45), link.close);
  ref.onDispose(expiry.cancel);
  return result;
});

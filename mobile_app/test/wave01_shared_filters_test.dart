import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_search_session.dart';
import 'package:real_estate_mobile/features/discovery/data/smart_search_session.dart';
import 'package:real_estate_mobile/features/discovery/domain/smart_search_filters.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'support/owner_ux_fixtures.dart';
import 'support/wave3_fakes.dart';

class _NoCredentials implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Public search requested authentication: $invocation');
}

void main() {
  test('T06 T07 empty, independently toggled types and schema share one canonical contract', () {
    var filters = const SmartSearchFilters();
    expect(filters.apiFilters, isEmpty);
    filters = filters.toggleType('villa').toggleType('apartment');
    expect(filters.selectedTypes, ['apartment', 'villa']);
    expect(filters.apiFilters['types'], ['apartment', 'villa']);
    expect(filters.apiFilters.containsKey('type'), isFalse);
    expect(filters.chips.map((chip) => chip.$1), containsAll(['type:apartment', 'type:villa']));
    expect(filters.sameAs(SmartSearchFilters.fromMap({'types': ['villa', 'apartment']})), isTrue);
    expect(() => (filters.values['types'] as List).add('land'), throwsUnsupportedError);
    filters = SmartSearchFilters.fromMap({...filters.values, 'purpose': 'rent', 'min_bedrooms': 3, 'max_price': 250000});
    expect(filters.apiFilters['max_monthly_rent'], 250000);
    expect(filters.apiFilters['currency'], 'YER');
    filters = filters.without('type:apartment');
    expect(filters.selectedTypes, ['villa']);
    expect(filters.values['min_bedrooms'], 3);
    filters = filters.toggleType('land');
    expect(filters.values.containsKey('min_bedrooms'), isFalse);
    expect(filters.values['max_price'], 250000);
    filters = filters.without('type:villa').without('type');
    expect(filters.selectedTypes, isEmpty);
    expect(filters.values.containsKey('types'), isFalse);
    expect(filters.without('purpose').apiFilters.containsKey('purpose'), isFalse);
  });

  test('T07 HTTP serializes actual PHP arrays in list, map and Home and retains legacy scalar clients', () async {
    final uris = <Uri>[], dio = Dio(BaseOptions(baseUrl: 'https://fixture.example/api'));
    addTearDown(() => dio.close(force: true));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      uris.add(options.uri);
      handler.resolve(Response(requestOptions: options, statusCode: 200,
        headers: Headers.fromMap({'x-aqer-filter-contract': ['2']}), data: {
          'data': options.path == '/marketplace' ? {'context': {'purpose': 'rent'}, 'sections': <String, dynamic>{}} : <Object>[],
        }));
    }));
    final repository = PropertyRepository(dio, _NoCredentials());
    final filters = SmartSearchFilters.fromMap({'types': ['villa', 'apartment'], 'purpose': 'rent', 'max_price': 250000}).apiFilters;
    await repository.searchListings(filters);
    await repository.nearbyFiltered({...filters, 'south': 15, 'west': 44, 'north': 16, 'east': 45});
    await MarketplaceRepository(dio).feed(HomeFeedQuery(latitude: 15, longitude: 44, device: false,
      filters: SmartSearchFilters.fromApiFilters(filters)));
    expect(uris, hasLength(3));
    for (final uri in uris) {
      expect(uri.queryParametersAll['types[]'], ['apartment', 'villa']);
      expect(uri.queryParameters['max_monthly_rent'], '250000');
      expect(uri.queryParameters['currency'], 'YER');
      expect(uri.queryParameters.containsKey('type'), isFalse);
    }
    await repository.searchListings(filters);
    expect(uris, hasLength(3), reason: 'A repeated identical public query uses its existing cache.');
    await repository.searchListings({'type': 'apartment'});
    expect(uris.last.queryParameters['type'], 'apartment');
    expect(uris.last.queryParametersAll.containsKey('types[]'), isFalse);
  });

  test('T12 an old server cannot silently claim multi-type success, even with empty results', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://fixture.example/api'));
    addTearDown(() => dio.close(force: true));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) => handler.resolve(
      Response(requestOptions: options, statusCode: 200, data: {'data': options.path == '/marketplace'
        ? {'context': <String, dynamic>{}, 'sections': <String, dynamic>{}} : <Object>[]}))));
    final repository = PropertyRepository(dio, _NoCredentials());
    final filters = {'types': ['apartment', 'villa']};
    await expectLater(repository.searchListings(filters), throwsStateError);
    await expectLater(repository.nearbyFiltered(filters), throwsStateError);
    await expectLater(MarketplaceRepository(dio).feed(HomeFeedQuery(latitude: 15, longitude: 44, device: false,
      filters: SmartSearchFilters.fromMap(filters))), throwsStateError);
    expect((await repository.searchListings({'type': 'apartment'})).$1, isEmpty);
  });

  test('T07 T08 map and list keep multi types and budget across repeated entry without duplicate reloads', () async {
    final properties = Wave3PropertiesFake(), scope = uxContainer(extra: [propertyRepositoryProvider.overrideWithValue(properties)]);
    await scope.read(authControllerProvider.future);
    final controller = scope.read(marketplaceSearchControllerProvider.notifier);
    controller.chooseType('apartment'); controller.chooseType('villa'); controller.choosePurpose('rent');
    controller.setChoice('max_price', 250000);
    await Future<void>.delayed(Duration.zero);
    controller.enterMap();
    await Future<void>.delayed(Duration.zero);
    scope.read(marketplaceMapResultsProvider.notifier).updateViewport(south: 15, west: 44, north: 16, east: 45);
    await Future<void>.delayed(Duration.zero);
    final before = properties.queries.length;
    controller.leaveMap(); controller.enterMap(); controller.enterMap();
    await Future<void>.delayed(Duration.zero);
    expect(properties.queries.length, before);
    expect(scope.read(marketplaceMapResultsProvider).filters.selectedTypes, ['apartment', 'villa']);
    expect(scope.read(marketplaceMapResultsProvider).filters.apiFilters['max_monthly_rent'], 250000);
    expect(scope.read(homeSearchResultsProvider).filters.values.containsKey('south'), isFalse);
    controller.toggleType('apartment');
    await Future<void>.delayed(Duration.zero);
    expect(scope.read(homeSearchResultsProvider).filters.selectedTypes, ['villa']);
    expect(scope.read(marketplaceMapResultsProvider).filters.selectedTypes, ['villa']);
  });

  test('T03 an unsent typed amendment invalidates an earlier in-flight AI final', () async {
    final response = Completer<Map<String, dynamic>>(), ai = Wave3AiFake(), properties = Wave3PropertiesFake();
    ai.onRefine = (_, __, ___) => response.future;
    final session = SmartSearchSession(ai, properties);
    addTearDown(session.dispose);
    session.setDraftText('فلل');
    final pending = session.interpret('فلل');
    session.setDraftText('أريد أراضي بدل ذلك');
    response.complete({'revision': ai.requests.single.revision, 'filters': {'type': 'villa'}});
    await pending;
    expect(session.snapshot.draftText, 'أريد أراضي بدل ذلك');
    expect(session.snapshot.filters.values, isEmpty);
    expect(properties.queries, isEmpty);
  });
}

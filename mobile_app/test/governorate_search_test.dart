import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/ai_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/discovery_location.dart';
import 'package:real_estate_mobile/features/discovery/data/governorate_map_scope.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_search_session.dart';
import 'package:real_estate_mobile/features/discovery/data/smart_search_session.dart';
import 'package:real_estate_mobile/features/discovery/domain/governorate_search.dart';
import 'package:real_estate_mobile/features/discovery/domain/smart_search_filters.dart';

import 'support/wave3_fakes.dart';

class _UnusedAuth implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FixAccess extends DiscoveryLocationAccess {
  final fix = Completer<HomeLocation>();
  int fixes = 0;
  @override
  bool get supportsSearchFix => true;
  @override
  Future<LocationPermission> permission() async => LocationPermission.whileInUse;
  @override
  Future<LocationPermission> requestPermission() => throw StateError('An existing search cannot open a permission prompt');
  @override
  Future<HomeLocation> locate() { fixes++; return fix.future; }
}

class _Preferences extends DiscoveryLocationStore {
  @override
  Future<DiscoveryLocationPreferences> load() async => const DiscoveryLocationPreferences();
  @override
  Future<void> save(DiscoveryLocationPreferences preferences) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const dhamar = HomeLocation(governorate: 'ذمار', governorateCode: 'DHAMAR',
      device: true, latitude: 14.55, longitude: 44.4);
  const sanaa = HomeLocation(governorate: 'صنعاء', governorateCode: 'SANAA', manual: true);
  test('confirmed province covers the entire region; an unresolved location never invents Sanaa', () {
    expect(dhamar.provinceSearchContext, {'governorate': 'ذمار', 'governorate_code': 'DHAMAR'});
    expect(dhamar.searchContext['radius_km'], 30);
    const oldLabel = HomeLocation(governorate: 'صنعاء', governorateCode: 'AMANAT_AL_ASIMAH');
    expect(oldLabel.provinceSearchContext['governorate'], 'أمانة العاصمة');
    expect(const HomeLocation().provinceSearchContext, isEmpty);
    expect(const HomeLocation(device: true, needsConfirmation: true, governorate: 'ذمار').provinceSearchContext, isEmpty);
  });

  test('home and map use structured sale, rent and province for every property type', () async {
    final properties = Wave3PropertiesFake();
    final home = SmartSearchSession(Wave3AiFake(), properties);
    final map = SmartSearchSession(Wave3AiFake(), properties);
    final controller = MarketplaceSearchController(home, map, () => dhamar);
    addTearDown(() {controller.dispose(); home.dispose(); map.dispose();});
    for (final type in SmartSearchFilters.types.entries) {
      for (final purpose in {'للبيع': 'sale', 'للإيجار': 'rent'}.entries) {
        controller.edit('${type.value} ${purpose.key}');
        await controller.submit();
        expect(properties.queries.last.filters, {...dhamar.provinceSearchContext, 'type': type.key, 'purpose': purpose.value});
        controller.edit('${type.value} ${purpose.key} في محافظة صنعاء');
        await controller.submit();
        expect(properties.queries.last.filters, {...sanaa.provinceSearchContext, 'type': type.key, 'purpose': purpose.value});
      }
    }
    controller.enterMap();
    controller.edit('بيت للبيع في ذماء', onMap: true);
    await controller.submit(onMap: true);
    expect(map.snapshot.filters.apiFilters, {...dhamar.provinceSearchContext, 'purpose': 'sale', 'type': 'house'});
    expect(home.snapshot.filters.apiFilters['governorate_code'], 'SANAA');
  });

  const dhamarRing = '[[44.39,14.54],[44.41,14.54],[44.41,14.56],[44.39,14.56],[44.39,14.54]]';
  const dhamarViewport = {'west': 44.38, 'east': 44.42, 'south': 14.53, 'north': 14.57};
  test('ordinary map releases incompatible shapes for the named province and keeps subsequent independent pans', () async {
    final properties = Wave3PropertiesFake();
    final home = SmartSearchSession(Wave3AiFake(), properties);
    final map = SmartSearchSession(Wave3AiFake(), properties);
    final controller = MarketplaceSearchController(home, map, () => dhamar);
    addTearDown(() { controller.dispose(); home.dispose(); map.dispose(); });
    controller.edit('بيت للبيع');
    await controller.submit();
    final parent = home.snapshot;
    controller.enterMap();
    map.updateViewport(south: 14.53, west: 44.38, north: 14.57, east: 44.42);
    await map.applyDrawnArea(dhamarRing);
    controller.edit('بيت للبيع في ذمار', onMap: true);
    await controller.submit(onMap: true);
    expect(map.snapshot.filters.values['area_polygon'], dhamarRing);
    expect(map.snapshot.filters.values['west'], 44.38);
    controller.edit('شقة للإيجار في صنعاء', onMap: true);
    await controller.submit(onMap: true);
    expect(map.snapshot.filters.apiFilters, {...sanaa.provinceSearchContext, 'type': 'apartment', 'purpose': 'rent'});

    // An intentional subsequent pan is an independent search area. Changing
    // a property attribute doesn't silently resubmit the last typed province.
    map.updateViewport(south: 14.53, west: 44.38, north: 14.57, east: 44.42);
    controller.choosePurpose('sale', onMap: true);
    await Future<void>.delayed(Duration.zero);
    expect(map.snapshot.filters.values['west'], 44.38);
    expect(map.snapshot.filters.values.containsKey('governorate_code'), isFalse);
    await controller.submit(onMap: true);
    expect(map.snapshot.filters.values['governorate_code'], 'SANAA');
    expect(map.snapshot.filters.hasMapArea, isFalse);
    controller.leaveMap();
    expect(home.snapshot, same(parent));
  });

  test('typed or transcribed smart turns replace only incompatible scoped geometry', () async {
    final properties = Wave3PropertiesFake();
    final dio = Dio();
    addTearDown(() => dio.close(force: true));
    final inputs = <Map<String, dynamic>>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      final input = request.data as Map;
      inputs.add(Map.from(input['filters'] as Map));
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {'data': {
        'revision': input['revision'], 'filters': {...inputs.last, 'type': 'house'},
      }}));
    }));
    final smart = SmartSearchSession(AiRepository(dio, _UnusedAuth()), properties);
    addTearDown(smart.dispose);
    final saved = SmartSearchFilters.fromMap({
      ...dhamarViewport, 'area_polygon': dhamarRing, 'advertiser_id': 7,
    });
    smart.beginJourney(savedFilters: saved);
    await smart.interpret('بيت في ذمار');
    expect(properties.queries.last.filters, {...saved.values, ...dhamar.provinceSearchContext, 'type': 'house'});
    await smart.interpret('بيت في صنعاء');
    expect(inputs.last.containsKey('area_polygon'), isFalse);
    expect(properties.queries.last.filters, {...sanaa.provinceSearchContext, 'type': 'house', 'advertiser_id': 7});
    expect(saved.values['area_polygon'], dhamarRing);
  });

  test('governorate holes, crossing viewports and drawn areas use actual shared geometry', () async {
    final source = File('../backend-api-runtime/resources/regions/yemen-adm1.geojson');
    expect(await File(GovernorateMapScope.asset).readAsString(), await source.readAsString());
    const capital = {'west': 44.185, 'east': 44.195, 'south': 15.365, 'north': 15.375};
    final capitalScope = SmartSearchFilters.fromMap(capital);
    expect((await GovernorateMapScope.reconcile(capitalScope, 'AMANAT_AL_ASIMAH')).hasMapArea, isTrue);
    expect((await GovernorateMapScope.reconcile(capitalScope, 'SANAA')).hasMapArea, isFalse);
    final mixed = SmartSearchFilters.fromMap({'area_polygon': dhamarRing, ...capital});
    final matchDraw = await GovernorateMapScope.reconcile(mixed, 'DHAMAR');
    expect(matchDraw.values, {'area_polygon': dhamarRing});
    final matchViewport = await GovernorateMapScope.reconcile(mixed, 'AMANAT_AL_ASIMAH');
    expect(matchViewport.values, capital);
    final crossing = SmartSearchFilters.fromMap({'west': 44.3, 'east': 44.7, 'south': 14.5, 'north': 15.5});
    expect((await GovernorateMapScope.reconcile(crossing, 'SANAA')).values, crossing.values);
    expect((await GovernorateMapScope.reconcile(crossing, 'DHAMAR')).values, crossing.values);
  });

  test('smart typed and transcribed turns use the same province and pagination filters', () async {
    final dio = Dio();
    addTearDown(() => dio.close(force: true));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (r, handler) {
      final request = r.data as Map;
      final message = request['message'] as String;
      final values = Map<String, dynamic>.from(request['filters'] as Map);
      values.addAll({'purpose': 'rent', 'type': 'apartment'});
      if (message.contains('صنعاء')) values['search'] = 'صنعاء';
      if (message.contains('ذماء')) values['search'] = 'ذمار';
      if (message.contains('شارع')) values['search'] = 'شارع الجامعة';
      if (message.contains('تعز')) values['search'] = 'تعز'; // Misread a street or a negation.
      handler.resolve(Response(requestOptions: r, statusCode: 200,
        data: {'data': {'revision': request['revision'], 'filters': values}}));
    }));
    var current = const HomeLocation();
    final properties = Wave3PropertiesFake();
    final session = SmartSearchSession(AiRepository(dio, _UnusedAuth()), properties,
        defaultLocation: () => SmartSearchFilters.fromMap(current.provinceSearchContext));
    addTearDown(session.dispose);
    session.beginJourney();
    current = dhamar; // GPS resolves while the search composer is open.
    await session.interpret('شقة للإيجار');
    expect(properties.queries.last.filters, {...dhamar.provinceSearchContext, 'purpose': 'rent', 'type': 'apartment'});
    await session.interpret('شقة للإيجار في صنعاء');
    expect(properties.queries.last.filters, {...sanaa.provinceSearchContext, 'purpose': 'rent', 'type': 'apartment'});
    await session.interpret('في شارع الجامعة');
    expect(properties.queries.last.filters['governorate_code'], 'SANAA');
    expect(properties.queries.last.filters['search'], 'شارع الجامعة');
    current = sanaa;
    session.beginJourney(entryFilters: SmartSearchFilters.fromMap({'type': 'house'}));
    expect(properties.queries.last.filters, {...sanaa.provinceSearchContext, 'type': 'house'});
    await session.interpret('شقة للإيجار في محافظة ذماء');
    expect(properties.queries.last.filters, {...dhamar.provinceSearchContext, 'purpose': 'rent', 'type': 'apartment'});
  });

  test('replaying a saved query preserves its scope and subsequent local searches get a province', () async {
    final properties = Wave3PropertiesFake();
    final dio = Dio();
    addTearDown(() => dio.close(force: true));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      final payload = r.data as Map;
      final filters = Map<String, dynamic>.from(payload['filters'] as Map);
      final text = payload['message'] as String;
      filters['search'] = text.contains('تعز') ? 'تعز' : 'صنعاء';
      h.resolve(Response(requestOptions: r, statusCode: 200, data: {'data': {
        'revision': payload['revision'], 'filters': filters,
      }}));
    }));
    final session = SmartSearchSession(AiRepository(dio, _UnusedAuth()), properties,
        defaultLocation: () => SmartSearchFilters.fromMap(dhamar.provinceSearchContext));
    addTearDown(session.dispose);
    final stored = SmartSearchFilters.fromMap({'type': 'house'});
    session.beginJourney(savedFilters: stored);
    await Future<void>.delayed(Duration.zero);
    expect(properties.queries.last.filters, {'type': 'house'});
    await session.interpret('بيت في شارع تعز');
    expect(properties.queries.last.filters['governorate_code'], 'DHAMAR');
    await session.interpret('لا أريد في تعز');
    expect(properties.queries.last.filters['governorate_code'], 'DHAMAR');
    session.beginJourney(savedFilters: SmartSearchFilters.fromMap({
      ...dhamar.searchContext, 'purpose': 'sale', 'advertiser_id': 17,
    }));
    await session.interpret('بيت للبيع في صنعاء');
    expect(properties.queries.last.filters, {...sanaa.provinceSearchContext, 'purpose': 'sale', 'advertiser_id': 17});
    expect(stored.values, {'type': 'house'});
  });

  test('search refresh checks an existing grant once, respects manual choices and leaves Home alone', () async {
    final access = _FixAccess();
    var home = const HomeLocation(governorate: 'ذمار', governorateCode: 'DHAMAR');
    final coordinator = DiscoveryLocationCoordinator(_Preferences(), access, () => home, (p) => home = p,
        resolve: (_) async => sanaa);
    final first = coordinator.refreshForSearch()!;
    final simultaneous = coordinator.refreshForSearch()!;
    access.fix.complete(sanaa);
    expect((await first).provinceSearchContext['governorate_code'], 'SANAA');
    expect((await simultaneous).provinceSearchContext['governorate_code'], 'SANAA');
    expect((await coordinator.refreshForSearch()!).provinceSearchContext['governorate_code'], 'SANAA');
    expect(home.governorateCode, 'DHAMAR');
    expect(access.fixes, 1);
    await coordinator.selectManual(sanaa);
    expect(coordinator.refreshForSearch(), isNull);
  });

  test('a slower old location fix cannot overwrite an explicit newer ordinary search', () async {
    final location = Completer<HomeLocation>();
    final properties = Wave3PropertiesFake();
    final home = SmartSearchSession(Wave3AiFake(), properties);
    final map = SmartSearchSession(Wave3AiFake(), properties);
    final controller = MarketplaceSearchController(home, map, () => dhamar, refreshLocation: () => location.future);
    addTearDown(() { controller.dispose(); home.dispose(); map.dispose(); });
    controller.edit('بيت للبيع');
    final older = controller.submit();
    controller.edit('شقة للإيجار في صنعاء');
    await controller.submit();
    location.complete(dhamar);
    await older;
    expect(properties.queries, hasLength(1));
    expect(properties.queries.single.filters, {...sanaa.provinceSearchContext, 'purpose': 'rent', 'type': 'apartment'});
  });

  test('province and capital remain different and street names do not relocate the search', () {
    expect(GovernorateSearch.inRequest('أرض للبيع في أمانة العاصمة')!.filters['governorate_code'], 'AMANAT_AL_ASIMAH');
    expect(GovernorateSearch.inRequest('أرض للبيع في صنعاء')!.filters['governorate_code'], 'SANAA');
    expect(GovernorateSearch.inRequest('شقة في شارع تعز'), isNull);
    expect(GovernorateSearch.inRequest('لا أريد في تعز'), isNull);
    expect(GovernorateSearch.inRequest('شقة في تعز أو عدن'), isNull);
    expect(GovernorateSearch.inRequest('شقة أو منزل في تعز')!.filters['governorate_code'], 'TAIZ');
  });
}

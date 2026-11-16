import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:real_estate_mobile/features/discovery/data/discovery_location.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_repository.dart';
import 'package:real_estate_mobile/features/discovery/domain/smart_search_filters.dart';
import 'package:real_estate_mobile/features/discovery/presentation/marketplace_home_screen.dart';

class _Store extends DiscoveryLocationStore {
  DiscoveryLocationPreferences saved = const DiscoveryLocationPreferences();
  @override
  Future<DiscoveryLocationPreferences> load() async => saved;
  @override
  Future<void> save(DiscoveryLocationPreferences preferences) async { saved = preferences; }
}

class _Access extends DiscoveryLocationAccess {
  LocationPermission allowed = LocationPermission.whileInUse;
  int fixes = 0;
  @override
  Future<LocationPermission> permission() async => allowed;
  @override
  Future<LocationPermission> requestPermission() async => allowed;
  @override
  Future<HomeLocation> locate() async {
    fixes++;
    return const HomeLocation(latitude: 13.9667, longitude: 44.1833, accuracyMetres: 7, device: true);
  }
}

void main() {
  test('manual governorate spans the full boundary and code is retained in list/map filters', () {
    final location = HomeLocation.fromJson({'latitude': 14.55, 'longitude': 44.4, 'governorate': 'ذمار', 'governorate_code': 'DHAMAR', 'label': 'ذمار'});
    expect(location.searchContext, {'governorate': 'ذمار', 'governorate_code': 'DHAMAR'});
    final filters = SmartSearchFilters.fromMap(location.searchContext);
    expect(filters.apiFilters['governorate_code'], 'DHAMAR');
    expect(filters.hasMapArea, isFalse);
    expect(filters.chips, [('governorate', 'المحافظة: ذمار')]);
    expect(filters.without('governorate').apiFilters, isEmpty);
  });

  test('server classification receives original coordinates and GPS accuracy without moving the point', () async {
    final dio = Dio(); final requests = <RequestOptions>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      requests.add(request);
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {'data': {
        'source': 'device', 'governorate': 'إب', 'governorate_code': 'IBB', 'label': 'إب', 'needs_confirmation': false,
      }}));
    }));
    const fix = HomeLocation(latitude: 13.9667, longitude: 44.1833, accuracyMetres: 7, device: true);
    final resolved = await MarketplaceRepository(dio).resolveLocation(fix);
    expect(requests.single.path, '/marketplace/location-context');
    expect(requests.single.queryParameters, {'latitude': 13.9667, 'longitude': 44.1833, 'accuracy_m': 7.0});
    expect((resolved.latitude, resolved.longitude, resolved.accuracyMetres), (fix.latitude, fix.longitude, 7));
    expect(resolved.governorateCode, 'IBB'); expect(resolved.needsConfirmation, isFalse);
  });

  test('manual selection wins over a delayed server classification and GPS stays out of preferences', () async {
    final store = _Store(), access = _Access(), response = Completer<HomeLocation>();
    var state = const HomeLocation();
    final coordinator = DiscoveryLocationCoordinator(store, access, () => state, (value) => state = value, resolve: (_) => response.future);
    await coordinator.initialize(); final request = coordinator.useDevice();
    await Future<void>.delayed(Duration.zero);
    const manual = HomeLocation(latitude: 16.1, longitude: 52.2, governorate: 'المهرة', governorateCode: 'AL_MAHRAH', label: 'المهرة', manual: true);
    await coordinator.selectManual(manual);
    response.complete(const HomeLocation(latitude: 13.9667, longitude: 44.1833, governorate: 'إب', governorateCode: 'IBB', device: true));
    await request;
    expect(state, same(manual)); expect(store.saved.manual, same(manual)); expect(store.saved.lastPublicRegion, isNull);
  });

  test('denied permission and a failed classification preserve manual choice', () async {
    final store = _Store(), access = _Access()..allowed = LocationPermission.deniedForever;
    var state = const HomeLocation(governorate: 'ذمار', governorateCode: 'DHAMAR', manual: true);
    var resolutions = 0;
    final coordinator = DiscoveryLocationCoordinator(store, access, () => state, (value) => state = value,
      resolve: (_) async { resolutions++; throw StateError('offline'); });
    await coordinator.selectManual(state);
    await expectLater(coordinator.useDevice(), throwsStateError);
    expect(access.fixes, 0); expect(resolutions, 0); expect(state.governorateCode, 'DHAMAR');
    access.allowed = LocationPermission.whileInUse;
    await expectLater(coordinator.useDevice(), throwsStateError);
    expect(resolutions, 1); expect(state.governorateCode, 'DHAMAR'); expect(store.saved.manual?.governorateCode, 'DHAMAR');
  });

  test('uncertain border fixes are explicit and cannot cache a falsely confirmed region', () async {
    final store = _Store(); var state = const HomeLocation();
    final coordinator = DiscoveryLocationCoordinator(store, _Access(), () => state, (value) => state = value,
      resolve: (fix) async => HomeLocation(latitude: fix.latitude, longitude: fix.longitude, device: true,
        governorate: 'إب', governorateCode: 'IBB', needsConfirmation: true));
    await coordinator.useDevice();
    expect(state.needsConfirmation, isTrue); expect(state.searchContext.containsKey('governorate_code'), isFalse);
    await coordinator.rememberPublicRegion('إب', const [HomeLocation(governorate: 'إب', governorateCode: 'IBB')]);
    expect(store.saved.lastPublicRegion, isNull); expect(store.saved.manual, isNull);
  });

  testWidgets('picker shows all 22 server governorates including separate capital and selects Socotra', (tester) async {
    const names = ['أمانة العاصمة', 'صنعاء', 'عدن', 'تعز', 'الحديدة', 'إب', 'ذمار', 'حضرموت', 'حجة', 'صعدة', 'عمران', 'الجوف', 'مأرب', 'المحويت', 'ريمة', 'شبوة', 'لحج', 'أبين', 'الضالع', 'البيضاء', 'المهرة', 'أرخبيل سقطرى'];
    final rows = [for (var i = 0; i < names.length; i++) HomeLocation(latitude: 12.65, longitude: 54.02,
      governorate: names[i], governorateCode: i == 21 ? 'SOCOTRA' : 'test-$i', label: names[i], manual: true)];
    HomeLocation? selected;
    await tester.pumpWidget(ProviderScope(overrides: [homeLocationsProvider.overrideWith((ref) async => rows)], child: MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () async { selected = await showModalBottomSheet<HomeLocation>(context: context, builder: (_) => const MarketplaceLocationSheet()); }, child: const Text('المحافظات')))))));
    await tester.tap(find.text('المحافظات')); await tester.pumpAndSettle();
    expect(find.text('أمانة العاصمة'), findsOneWidget); expect(find.text('صنعاء'), findsOneWidget);
    final last = find.byKey(const ValueKey('home-governorate-SOCOTRA'));
    await tester.scrollUntilVisible(last, 250); await tester.tap(last); await tester.pumpAndSettle();
    expect(selected?.governorate, 'أرخبيل سقطرى'); expect(selected?.governorateCode, 'SOCOTRA'); expect(selected?.manual, isTrue);
    expect(tester.takeException(), isNull);
  });
}

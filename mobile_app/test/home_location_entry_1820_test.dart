import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:real_estate_mobile/features/discovery/data/discovery_location.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_repository.dart';
import 'package:real_estate_mobile/features/discovery/presentation/marketplace_home_screen.dart';

import 'support/owner_ux_fixtures.dart';
import 'support/wave3_fakes.dart';

const _dhamar = HomeLocation(latitude: 14.55, longitude: 44.4,
  governorate: 'ذمار', governorateCode: 'DHAMAR', label: 'ذمار', manual: true);

class _Preferences extends DiscoveryLocationStore {
  _Preferences(this.value);
  DiscoveryLocationPreferences value;
  int loads = 0;
  @override
  Future<DiscoveryLocationPreferences> load() async { loads++; return value; }
  @override
  Future<void> save(DiscoveryLocationPreferences preferences) async { value = preferences; }
}

class _Access extends DiscoveryLocationAccess {
  int permissionChecks = 0, permissionRequests = 0, fixes = 0;
  @override
  Future<LocationPermission> permission() async { permissionChecks++; return LocationPermission.denied; }
  @override
  Future<LocationPermission> requestPermission() async { permissionRequests++; return LocationPermission.denied; }
  @override
  Future<HomeLocation> locate() async { fixes++; return _dhamar; }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadUxFixtures);

  for (final saved in [false, true]) {
    testWidgets('${saved ? 'saved' : 'fresh'} Home requests the system permission only for a new install and retains manual selection', (tester) async {
      final store = _Preferences(DiscoveryLocationPreferences(manual: saved ? _dhamar : null));
      final access = _Access();
      final scope = uxContainer(extra: [
        homeLocationAttemptedProvider.overrideWith((ref) => false),
        discoveryLocationStoreProvider.overrideWithValue(store),
        discoveryLocationAccessProvider.overrideWithValue(access),
        homeLocationsProvider.overrideWith((ref) async => const [_dhamar]),
        marketplaceRepositoryProvider.overrideWithValue(Wave3MarketplaceFake(onFeed: (query) async =>
          MarketplaceFeed(label: query.governorate ?? 'اليمن', governorate: query.governorate))),
      ]);
      await pumpUx(tester, scope, const MarketplaceHomeScreen());
      await tester.pumpAndSettle();
      expect(store.loads, 1);
      expect(find.text('عقارات في منطقتك'), findsNothing);
      expect(find.byKey(const ValueKey('location-introduction-device')), findsNothing);
      expect(find.text('المتابعة الآن'), findsNothing);
      expect(find.text('أين تبحث؟'), findsNothing);
      expect(access.permissionChecks, saved ? 0 : 1);
      expect(access.permissionRequests, saved ? 0 : 1);
      expect(access.fixes, 0);
      if (!saved) {
        expect(store.value.permissionResolved, isTrue);
        final restarted = DiscoveryLocationCoordinator(store, access, () => scope.read(homeLocationProvider), (_) {});
        await restarted.initialize();
        expect(access.permissionRequests, 1);
      }
      if (saved) expect(scope.read(homeLocationProvider).governorateCode, 'DHAMAR');

      await tester.tap(find.byKey(const ValueKey('home-location')));
      await tester.pumpAndSettle();
      expect(find.text('أين تبحث؟'), findsOneWidget);
      expect(find.text('استخدم موقعي'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('home-governorate-DHAMAR')));
      await tester.pumpAndSettle();
      expect(scope.read(homeLocationProvider).governorateCode, 'DHAMAR');
      expect(store.value.manual?.governorateCode, 'DHAMAR');
      expect(find.text('أين تبحث؟'), findsNothing);
      expect(access.permissionChecks, saved ? 0 : 1);
      expect(access.permissionRequests, saved ? 0 : 1);
      expect(access.fixes, 0);
      expect(tester.takeException(), isNull);
      await closeUx(tester);
    });
  }
}

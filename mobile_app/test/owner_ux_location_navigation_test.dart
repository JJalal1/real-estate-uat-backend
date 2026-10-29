import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:real_estate_mobile/core/local/stage6_secure_session_store.dart';
import 'package:real_estate_mobile/core/widgets/app_components.dart';
import 'package:real_estate_mobile/features/app_shell/presentation/app_shell_screen.dart';
import 'package:real_estate_mobile/features/properties/domain/property_coordinates.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_editor_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_details_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_location_picker_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_location_preview.dart';
import 'broker_experience_ui_test.dart' show BrokerTestRepository;
import 'support/owner_ux_fixtures.dart';
import 'support/wave6_fakes.dart';
import 'wave6_product_ui_test.dart' show pumpWave6, editorSnapshot, finishWave6;

class _Work extends BrokerTestRepository {
  int calls = 0;
  @override
  Future<Map<String, dynamic>> workspace() async { calls++; return super.workspace(); }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadUxFixtures);
  test('missing, nonfinite, out-of-range and legacy coordinates cannot become a map pin', () {
    for (final point in <(double?, double?)>[(null, 44), (15, null), (0, 0), (double.nan, 44), (15, double.infinity), (91, 44), (15, 181)]) {
      expect(hasValidPropertyCoordinates(point.$1, point.$2), isFalse);
    }
    expect(hasValidPropertyCoordinates(13.966, 44.182), isTrue);
    for (final fields in <Map<String, dynamic>>[{}, {'latitude': 13.966}, {'latitude': 'bad', 'longitude': 44.182}, {'latitude': 0, 'longitude': 0}]) {
      expect(PropertyDetails.fromJson({'id': 11, ...fields}).hasValidLocation, isFalse);
    }
  });

  for (final valid in [true, false]) {
    testWidgets('details ${valid ? 'routes the exact saved point' : 'shows no fabricated point'} and removes questions', (tester) async {
      const lat = 13.966723, lon = 44.182451;
      final seen = <(double, double)>[];
      Uri? opened;
      final scope = uxContainer(extra: [
        propertyDetailsProvider.overrideWith((ref, id) async => PropertyDetails.fromJson({
          'id': id, 'title': 'منزل اختبار في إب', 'type': 'house', 'purpose': 'sale', 'price': 20000000, 'currency': 'YER',
          'status': 'published', 'images': <Object>[], if (valid) 'latitude': lat, if (valid) 'longitude': lon,
        })),
        propertyMapPreviewBuilderProvider.overrideWithValue((context, latitude, longitude) {
          seen.add((latitude, longitude)); return const ColoredBox(color: Colors.teal, child: Center(child: Text('خريطة اختبار صناعية')));
        }),
      ]);
      final router = GoRouter(initialLocation: '/property/11', routes: [
        GoRoute(path: '/property/:id', builder: (_, state) => const PropertyDetailsScreen(propertyId: 11)),
        GoRoute(path: '/property-market', builder: (_, state) { opened = state.uri; return const Scaffold(body: Text('خريطة')); }),
      ]);
      addTearDown(router.dispose);
      await pumpUx(tester, scope, const SizedBox.shrink(), router: router);
      expect(find.text('اسأل عن هذا العقار'), findsNothing);
      if (valid) {
        expect(seen, isNotEmpty); expect(seen.every((point) => point == (lat, lon)), isTrue);
        final open = find.byKey(const ValueKey('property-open-map'));
        await tester.scrollUntilVisible(open, 300, scrollable: find.byType(Scrollable).first);
        await tester.ensureVisible(open); await tester.pumpAndSettle();
        await tester.tap(open); await uxFrames(tester);
        expect(opened!.queryParameters['lat'], '$lat'); expect(opened!.queryParameters['lon'], '$lon');
      } else {
        expect(seen, isEmpty); expect(find.byType(PropertyLocationPreview), findsNothing);
        final missing = find.byKey(const ValueKey('property-location-unspecified'));
        await tester.scrollUntilVisible(missing, 300, scrollable: find.byType(Scrollable).first);
        expect(missing, findsOneWidget);
      }
      expect(tester.takeException(), isNull); await closeUx(tester);
    });
  }

  for (final initial in [LocationPermission.whileInUse, LocationPermission.denied, LocationPermission.deniedForever]) {
    testWidgets('GPS native permission contract from $initial', (tester) async {
      const channel = MethodChannel('flutter.baseflow.com/geolocator');
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        switch (call.method) {
          case 'isLocationServiceEnabled': return true;
          case 'checkPermission': return initial.index;
          case 'requestPermission': return LocationPermission.whileInUse.index;
          case 'getCurrentPosition': return {'latitude': 13.966, 'longitude': 44.182, 'timestamp': 1793059200000,
            'accuracy': 5.0, 'altitude': 0.0, 'heading': 0.0, 'speed': 0.0, 'speed_accuracy': 0.0};
        }
        throw StateError(call.method);
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
      final scope = uxContainer();
      if (initial == LocationPermission.deniedForever) {
        await expectLater(scope.read(propertyCurrentLocationProvider)(), throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'LOCATION_DENIED_FOREVER')));
        expect(calls, isNot(contains('requestPermission'))); expect(calls, isNot(contains('getCurrentPosition')));
      } else {
        final point = await scope.read(propertyCurrentLocationProvider)();
        expect((point.latitude, point.longitude), (13.966, 44.182));
        expect(calls.where((name) => name == 'requestPermission').length, initial == LocationPermission.denied ? 1 : 0);
        expect(calls.where((name) => name == 'getCurrentPosition').length, 1);
      }
    });
  }

  testWidgets('location service off never requests permission or fabricates coordinates', (tester) async {
    const channel = MethodChannel('flutter.baseflow.com/geolocator'); final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async { calls.add(call.method); return false; });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    await expectLater(uxContainer().read(propertyCurrentLocationProvider)(), throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'LOCATION_DISABLED')));
    expect(calls, ['isLocationServiceEnabled']);
  });

  for (final code in ['LOCATION_DENIED', 'LOCATION_DENIED_FOREVER', 'LOCATION_DISABLED']) {
    testWidgets('$code retains manual selection and shows only the applicable settings action', (tester) async {
      final recovery = Wave6Recovery(editorSnapshot()..['step'] = 1..['latitude'] = null..['longitude'] = null);
      var manual = 0;
      await pumpWave6(tester, ProviderScope(overrides: [
        propertyCurrentLocationProvider.overrideWithValue(() async => throw PlatformException(code: code, message: 'تعذّر الإذن للاختبار')),
        propertyLocationPickerProvider.overrideWithValue((context, {initialLatitude, initialLongitude}) async { manual++; return const PropertyLocationSelection(latitude: 13.966, longitude: 44.182); }),
        propertyMapPreviewBuilderProvider.overrideWithValue((context, lat, lon) => Text('$lat,$lon')),
      ], child: const ListingEditorScreen()), recovery: recovery);
      final gps = find.byKey(const ValueKey('listing-current-location'));
      await tester.ensureVisible(gps); await tester.tap(gps); await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('listing-location-settings')), code == 'LOCATION_DENIED_FOREVER' ? findsOneWidget : findsNothing);
      expect(find.byKey(const ValueKey('listing-enable-location-service')), code == 'LOCATION_DISABLED' ? findsOneWidget : findsNothing);
      final map = find.byKey(const ValueKey('listing-select-location')); await tester.ensureVisible(map); await tester.tap(map); await tester.pumpAndSettle();
      expect(manual, 1); expect(recovery.snapshot!['latitude'], 13.966); expect(recovery.snapshot!['longitude'], 44.182);
      expect(tester.takeException(), isNull); await finishWave6(tester);
    });
  }

  testWidgets('late GPS fix after a session change is discarded', (tester) async {
    final fix = Completer<PropertyLocationSelection>();
    final recovery = Wave6Recovery(editorSnapshot()..['step'] = 1..['latitude'] = null..['longitude'] = null);
    await pumpWave6(tester, ProviderScope(overrides: [propertyCurrentLocationProvider.overrideWithValue(() => fix.future)],
      child: const ListingEditorScreen()), recovery: recovery);
    final gps = find.byKey(const ValueKey('listing-current-location'));
    await tester.ensureVisible(gps); await tester.tap(gps); await tester.pump();
    Stage6SecureSessionStore.instance.beginSessionChange();
    fix.complete(const PropertyLocationSelection(latitude: 13.966, longitude: 44.182)); await tester.pumpAndSettle();
    expect(recovery.snapshot!['latitude'], isNull); expect(recovery.snapshot!['longitude'], isNull);
    expect(find.byKey(const ValueKey('listing-location-preview')), findsNothing);
    await finishWave6(tester);
  });

  for (final type in ['broker', 'office', 'regular']) {
    testWidgets('actual server account $type selects its own navigation', (tester) async {
      final boundary = GlobalKey();
      await pumpUx(tester, uxContainer(user: uxUser(type: type == 'regular' ? null : type)), const AppShellScreen(), boundary: boundary);
      final nav = tester.widget<AppNavigationBar>(find.byType(AppNavigationBar));
      expect(nav.destinations.map((d) => d.label), switch (type) {
        'broker' => ['الرئيسية', 'عملي', 'العملاء', 'حسابي'],
        'office' => ['العقارات', 'الخريطة', 'الرسائل', 'حسابي'],
        _ => ['العقارات', 'الرسائل', 'إعلاناتي', 'حسابي'],
      });
      await uxPreview(tester, boundary, 'navigation-$type');
      expect(tester.takeException(), isNull); await closeUx(tester);
    });
  }

  testWidgets('pending broker tools remain gated and plus chooses a creation method before the existing manual route', (tester) async {
    final work = _Work(); Uri? opened;
    final router = GoRouter(routes: [GoRoute(path: '/', builder: (_, state) => const AppShellScreen()),
      GoRoute(path: '/add-property', builder: (_, state) { opened = state.uri; return const Scaffold(body: Text('محرر الإعلان')); })]);
    addTearDown(router.dispose);
    final scope = uxContainer(user: uxUser(type: 'broker', status: 'pending'), broker: work);
    await pumpUx(tester, scope, const SizedBox.shrink(), router: router);
    final nav = tester.widget<AppNavigationBar>(find.byType(AppNavigationBar));
    nav.onSelected(1); await uxFrames(tester);
    expect(work.calls, 0); expect(find.text('يحتاج إجراء منك'), findsNothing);
    nav.onCreate!(); await uxFrames(tester);
    expect(opened,isNull); await tester.tap(find.byKey(const ValueKey('create-listing-manual'))); await uxFrames(tester);
    expect(opened!.path, '/add-property'); expect(opened!.queryParameters['assistant'], '0');
    expect(tester.takeException(), isNull); await closeUx(tester);
  });

  testWidgets('switching from broker to regular removes work and customer pages', (tester) async {
    final auth = UxAuth(uxUser(type: 'broker'));
    await pumpUx(tester, uxContainer(auth: auth), const AppShellScreen());
    tester.widget<AppNavigationBar>(find.byType(AppNavigationBar)).onSelected(1); await uxFrames(tester);
    auth.change(uxUser(id: 2)); await uxFrames(tester);
    expect(tester.widget<AppNavigationBar>(find.byType(AppNavigationBar)).destinations.map((d) => d.label), ['العقارات', 'الرسائل', 'إعلاناتي', 'حسابي']);
    expect(find.text('يحتاج إجراء منك'), findsNothing);
    expect(tester.takeException(), isNull); await closeUx(tester);
  });
}

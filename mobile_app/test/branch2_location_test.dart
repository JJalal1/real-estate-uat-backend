import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:real_estate_mobile/core/widgets/app_components.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/property_location_address.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_editor_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_location_picker_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_location_preview.dart';
import 'package:real_estate_mobile/features/properties/presentation/location_landmark_review_sheet.dart';
import 'support/owner_ux_fixtures.dart' show loadUxFixtures;
import 'support/wave6_fakes.dart';
import 'wave6_product_ui_test.dart' show pumpWave6, finishWave6, editorSnapshot, textField, previewWave6;

const _address = PropertyLocationAddress(governorate: 'محافظة صناعية', city: 'مدينة صناعية', district: 'مديرية صناعية',
  neighborhood: 'حي صناعي', street: 'شارع صناعي');
class _NoAuth implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Geocoding must not request account credentials');
}
class _Addresses extends Wave6Properties {
  Completer<PropertyLocationAddress>? pending;
  @override
  Future<PropertyLocationAddress> resolveLocationAddress({required double latitude, required double longitude, bool includeLandmarks = false}) async => pending?.future ?? _address;
}

void main() {
  setUpAll(loadUxFixtures);
  test('C03 five address levels round-trip without changing historical display', () {
    final restored = PropertyLocationAddress.fromStoredAddress(_address.combined);
    expect(restored.city, _address.city); expect(restored.district, _address.district);
    expect(restored.neighborhood, _address.neighborhood); expect(restored.street, _address.street);
    final legacy = PropertyLocationAddress.fromStoredAddress('صنعاء - حدة - شارع اختباري');
    expect(legacy.legacyMixedArea, isTrue); expect(legacy.combined, 'صنعاء - حدة - شارع اختباري');
    final missingStreet = PropertyLocationAddress.fromJson({'neighborhood': 'حي فقط', 'formatted_address': 'حي فقط، مدينة'});
    expect(missingStreet.street, isNull);
  });
  test('C06 proxy debounce and cache coalesce the same point, with coordinates absent from URLs', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test')), requests = <RequestOptions>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      requests.add(request); handler.resolve(Response(requestOptions: request, statusCode: 200, data: {'data': _address.toJson()}));
    }));
    final repo = PropertyRepository(dio, _NoAuth());
    final values = await Future.wait([repo.resolveLocationAddress(latitude: 14.54, longitude: 44.4), repo.resolveLocationAddress(latitude: 14.54, longitude: 44.4)]);
    expect(values.first.city, 'مدينة صناعية'); expect(requests.length, 1);
    expect(requests.single.method, 'POST'); expect(requests.single.uri.query, isEmpty);
    expect(requests.single.data, {'latitude': 14.54, 'longitude': 44.4, 'include_landmarks': false});
    await repo.resolveLocationAddress(latitude: 14.54, longitude: 44.4); expect(requests.length, 1);
    dio.close();
  });
  test('C05 C06 provider failure returns manual mode without direct device requests', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test')); var calls = 0;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) { calls++;
      handler.reject(DioException(requestOptions: request, type: DioExceptionType.connectionError)); }));
    final value = await PropertyRepository(dio, _NoAuth()).resolveLocationAddress(latitude: 14.54, longitude: 44.4);
    expect(value.isEmpty, isTrue); expect(value.providerStatus, 'unavailable'); expect(calls, 1); dio.close();
  });
  testWidgets('C01 C06 approximate permission reports actual accuracy without requesting a precision upgrade', (tester) async {
    const channel = MethodChannel('flutter.baseflow.com/geolocator'); final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'isLocationServiceEnabled': return true;
        case 'checkPermission': return LocationPermission.whileInUse.index;
        case 'getLocationAccuracy': return LocationAccuracyStatus.reduced.index;
        case 'getCurrentPosition': return {'latitude': 14.54, 'longitude': 44.4, 'timestamp': 1793059200000,
          'accuracy': 67.5, 'altitude': 0.0, 'heading': 0.0, 'speed': 0.0, 'speed_accuracy': 0.0};
      }
      throw StateError(call.method);
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    final scope = ProviderContainer(); addTearDown(scope.dispose);
    final point = await scope.read(propertyCurrentLocationProvider)();
    expect(point.accuracyMetres, 67.5); expect(point.reducedAccuracy, isTrue);
    expect(point.accuracyLabel, contains('±68')); expect(point.accuracyLabel, contains('تقريبي'));
    expect(calls, isNot(contains('requestTemporaryFullAccuracy')));
  });
  testWidgets('C02 C03 C06 late address fills only untouched fields and never replaces the confirmed point', (tester) async {
    final addresses = _Addresses()..pending = Completer(), recovery = Wave6Recovery(editorSnapshot()..['step'] = 1);
    await pumpWave6(tester, ProviderScope(overrides: [propertyRepositoryProvider.overrideWithValue(addresses),
      propertyCurrentLocationProvider.overrideWithValue(() async => const PropertyLocationSelection(latitude: 14.54, longitude: 44.4,
        method: 'gps', accuracyMetres: 67.5, reducedAccuracy: true)),
      propertyMapPreviewBuilderProvider.overrideWithValue((context, lat, lon) => const Text('دبوس صناعي للاختبار')),
    ], child: const ListingEditorScreen()), recovery: recovery);
    await tester.ensureVisible(find.byKey(const ValueKey('listing-current-location')));
    await tester.tap(find.byKey(const ValueKey('listing-current-location'))); await tester.pump();
    await tester.ensureVisible(textField('المحافظة *')); await tester.enterText(textField('المحافظة *'), 'محافظتي المعدلة');
    addresses.pending!.complete(_address); await tester.pumpAndSettle();
    expect(tester.widget<TextField>(textField('المحافظة *')).controller!.text, 'محافظتي المعدلة');
    expect(tester.widget<TextField>(textField('المدينة')).controller!.text, 'مدينة صناعية');
    expect(tester.widget<TextField>(textField('المديرية')).controller!.text, 'مديرية صناعية');
    expect(tester.widget<TextField>(textField('الحي')).controller!.text, 'حي صناعي');
    await tester.pump(const Duration(seconds: 1)); await tester.pumpAndSettle();
    expect(recovery.snapshot!['latitude'], 14.54); expect(recovery.snapshot!['longitude'], 44.4);
    expect(recovery.snapshot!['location_accuracy_m'], 67.5);
    await finishWave6(tester);
  });
  testWidgets('C02 manual correction retains its point and clears stale GPS accuracy', (tester) async {
    final recovery = Wave6Recovery({...editorSnapshot(), 'editor_version': 11, 'step': 1,
      'location_method': 'gps', 'location_accuracy_m': 70.0, 'location_reduced_accuracy': true});
    await pumpWave6(tester, ProviderScope(overrides: [
      propertyLocationPickerProvider.overrideWithValue((context, {initialLatitude, initialLongitude}) async =>
        const PropertyLocationSelection(latitude: 14.541, longitude: 44.401, address: _address)),
      propertyMapPreviewBuilderProvider.overrideWithValue((context, lat, lon) => const Text('دبوس صناعي للاختبار')),
    ], child: const ListingEditorScreen()), recovery: recovery);
    expect(find.byKey(const ValueKey('listing-gps-accuracy')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('listing-select-location')));
    await tester.tap(find.byKey(const ValueKey('listing-select-location'))); await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('listing-gps-accuracy')), findsNothing);
    await tester.pump(const Duration(seconds: 3)); await tester.pumpAndSettle();
    expect(recovery.snapshot!['latitude'], 14.541); expect(recovery.snapshot!['longitude'], 44.401);
    expect(recovery.snapshot!['location_method'], 'manual'); expect(recovery.snapshot!['location_accuracy_m'], isNull);
    await finishWave6(tester);
  });
  for (final scale in [1.0, 2.4]) {
    testWidgets('C03 C04 source distance and edited landmark text require explicit acceptance at $scale', (tester) async {
      final boundary = GlobalKey(); String? accepted;
      await pumpWave6(tester, Builder(builder: (context) => Scaffold(body: TextButton(child: const Text('افتح'),
        onPressed: () async { accepted = await AppBottomSheet.show<String>(context, builder: (_) => const LocationLandmarkReviewSheet(landmarks: [
          PropertyNearbyLandmark(name: 'قاعة اختبار صناعية', kind: 'قاعة مناسبات', distanceMetres: 111, source: 'Photon',
            sourceUrl: 'https://www.openstreetmap.org/node/999999001'),
        ])); }))), scale: scale, boundary: boundary);
      await tester.tap(find.text('افتح')); await tester.pumpAndSettle(); expect(accepted, isNull);
      await tester.tap(find.byType(RadioListTile<String>)); await tester.pumpAndSettle();
      expect(find.textContaining('بخط مستقيم'), findsWidgets);
      await tester.ensureVisible(find.byKey(const ValueKey('landmark-description')));
      await tester.enterText(find.byKey(const ValueKey('landmark-description')), 'وصف الموقع بعد مراجعة صاحبه');
      FocusManager.instance.primaryFocus?.unfocus(); await tester.pumpAndSettle();
      await previewWave6(tester, boundary, 'branch2-landmark-review-$scale');
      expect(accepted, isNull); await tester.tap(find.byKey(const ValueKey('landmark-apply'))); await tester.pumpAndSettle();
      expect(accepted, 'وصف الموقع بعد مراجعة صاحبه'); expect(tester.takeException(), isNull); await finishWave6(tester);
    });
  }
  testWidgets('C05 empty landmark coverage offers manual text without inventing a nearby feature', (tester) async {
    await pumpWave6(tester, const Scaffold(body: LocationLandmarkReviewSheet(landmarks: [])));
    expect(find.byType(RadioListTile<String>), findsNothing); expect(find.textContaining('لم يرجع المصدر'), findsOneWidget);
    expect(find.byKey(const ValueKey('landmark-description')), findsOneWidget); await finishWave6(tester);
  });
}

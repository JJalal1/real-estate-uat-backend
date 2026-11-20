import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformViewCreatedCallback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as google;
// Replace the native Google renderer for the widget test.
// ignore: depend_on_referenced_packages
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;
import 'package:real_estate_mobile/core/network/api_client.dart';
import 'package:real_estate_mobile/features/map/presentation/aqer_map.dart';

class _TestGoogleMaps extends GoogleMapsFlutterPlatform {
  @override
  Widget buildViewWithConfiguration(
    int creationId,
    PlatformViewCreatedCallback onPlatformViewCreated, {
    required MapWidgetConfiguration widgetConfiguration,
    MapConfiguration mapConfiguration = const MapConfiguration(),
    MapObjects mapObjects = const MapObjects(),
  }) =>
      const SizedBox.expand();
}

void main() {
  testWidgets('map layers switch on the same Google map at the same point', (
    tester,
  ) async {
    final original = GoogleMapsFlutterPlatform.instance;
    GoogleMapsFlutterPlatform.instance = _TestGoogleMaps();
    addTearDown(() => GoogleMapsFlutterPlatform.instance = original);

    const point = maplibre.LatLng(15.35, 44.18);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            appBar: AppBar(actions: const [AqerMapLayerButton()]),
            body: AqerMap(
              initialCameraPosition: const maplibre.CameraPosition(
                target: point,
                zoom: 16,
              ),
              onMapCreated: (_) {},
              onStyleLoadedCallback: () {},
            ),
          ),
        ),
      ),
    ));

    final map = find.byType(google.GoogleMap);
    final originalElement = tester.element(map);
    final initialMap = tester.widget<google.GoogleMap>(map);
    expect(initialMap.mapType, google.MapType.normal);

    for (final (label, type) in [
      ('قمر صناعي', google.MapType.satellite),
      ('هجين (صور وأسماء الشوارع)', google.MapType.hybrid),
      ('خريطة الشوارع', google.MapType.normal),
    ]) {
      await tester.tap(find.byTooltip('طبقات الخريطة'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(
        CheckedPopupMenuItem<google.MapType>,
        label,
      ));
      await tester.pumpAndSettle();

      final currentMap = tester.widget<google.GoogleMap>(map);
      expect(currentMap.mapType, type);
      expect(
          currentMap.initialCameraPosition, initialMap.initialCameraPosition);
      expect(tester.element(map), same(originalElement));
    }
  },
      skip: !const bool.fromEnvironment('AQER_GOOGLE_MAPS_UAT') ||
          !ApiEnvironmentConfig.isUat);
}

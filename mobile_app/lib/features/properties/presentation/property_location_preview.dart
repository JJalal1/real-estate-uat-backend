import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

typedef PropertyMapPreviewBuilder = Widget Function(BuildContext context, double latitude, double longitude);

final propertyMapPreviewBuilderProvider = Provider<PropertyMapPreviewBuilder>((ref) => (_, lat, lon) => _PublicPropertyMap(latitude: lat, longitude: lon));

class PropertyLocationPreview extends ConsumerWidget {
  const PropertyLocationPreview({required this.latitude, required this.longitude, required this.onOpen, super.key});
  final double latitude, longitude;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(height: 210,
      child: ref.watch(propertyMapPreviewBuilderProvider)(context, latitude, longitude))),
    const SizedBox(height: 8),
    TextButton.icon(key: const ValueKey('property-open-map'), onPressed: onOpen, icon: const Icon(Icons.map_outlined), label: const Text('فتح الموقع على الخريطة')),
  ]);
}

class _PublicPropertyMap extends StatelessWidget {
  const _PublicPropertyMap({required this.latitude, required this.longitude});
  final double latitude, longitude;
  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
    MapLibreMap(styleString: 'https://tiles.openfreemap.org/styles/liberty',
      initialCameraPosition: CameraPosition(target: LatLng(latitude, longitude), zoom: 15),
      scrollGesturesEnabled: false, zoomGesturesEnabled: false, rotateGesturesEnabled: false, tiltGesturesEnabled: false,
      doubleClickZoomEnabled: false, myLocationEnabled: false),
    IgnorePointer(child: Center(child: Padding(padding: const EdgeInsets.only(bottom: 28),
      child: Icon(Icons.location_on, size: 38, color: Theme.of(context).colorScheme.primary)))),
  ]);
}

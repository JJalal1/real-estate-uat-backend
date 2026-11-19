import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../map/presentation/aqer_map.dart';

typedef PropertyMapPreviewBuilder = Widget Function(BuildContext context, double latitude, double longitude);

final propertyMapPreviewBuilderProvider = Provider<PropertyMapPreviewBuilder>((ref) => (_, lat, lon) => _PublicPropertyMap(key: ValueKey((lat, lon)), latitude: lat, longitude: lon));

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

class PropertyLocationScreen extends StatelessWidget {
  const PropertyLocationScreen({
    required this.latitude,
    required this.longitude,
    super.key,
  });

  final double latitude, longitude;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('موقع العقار')),
    body: _PublicPropertyMap(
      latitude: latitude,
      longitude: longitude,
      interactive: true,
    ),
  );
}

class _PublicPropertyMap extends StatefulWidget {
  const _PublicPropertyMap({
    required this.latitude,
    required this.longitude,
    this.interactive = false,
    super.key,
  });

  final double latitude, longitude;
  final bool interactive;
  @override
  State<_PublicPropertyMap> createState() => _PublicPropertyMapState();
}

class _PublicPropertyMapState extends State<_PublicPropertyMap> {
  AqerMapController? _controller;
  Timer? _timeout;
  int _attempt = 0;
  bool _ready = false, _failed = false;
  @override
  void initState() {
    super.initState();
    _startTimeout();
  }
  void _startTimeout() {
    _timeout?.cancel();
    _timeout = Timer(const Duration(seconds: 20), () {
      if (mounted && !_ready) setState(() => _failed = true);
    });
  }
  @override
  void dispose() { _timeout?.cancel(); super.dispose(); }

  void _retry() {
    setState(() { _attempt++; _ready = false; _failed = false; _controller = null; });
    _startTimeout();
  }

  Future<void> _styleLoaded(int attempt) async {
    final controller = _controller;
    if (controller == null || !mounted || attempt != _attempt) return;
    try {
      // This is a geographic annotation, not a screen-centered placeholder pin.
      await controller.addCircle(CircleOptions(
        geometry: LatLng(widget.latitude, widget.longitude), circleRadius: 8,
        circleColor: '#127C7E', circleStrokeColor: '#FFFFFF', circleStrokeWidth: 3,
      )).timeout(const Duration(seconds: 5));
      if (mounted && attempt == _attempt && _controller == controller) {
        setState(() { _ready = true; _failed = false; });
      }
    } catch (_) {
      if (mounted && attempt == _attempt && _controller == controller) {
        setState(() => _failed = true);
      }
    } finally { if (attempt == _attempt && _controller == controller) _timeout?.cancel(); }
  }

  @override
  Widget build(BuildContext context) {
    final attempt = _attempt;
    return Stack(fit: StackFit.expand, children: [
    AqerMap(key: ValueKey(attempt),
      initialCameraPosition: CameraPosition(
        target: LatLng(widget.latitude, widget.longitude),
        zoom: widget.interactive ? 17 : 15,
      ),
      onMapCreated: (controller) {
        if (!mounted || attempt != _attempt) return;
        setState(() {
          _controller = controller;
          _ready = false;
          _failed = false;
        });
        _startTimeout();
      },
      onStyleLoadedCallback: () => _styleLoaded(attempt),
      scrollGesturesEnabled: widget.interactive, zoomGesturesEnabled: widget.interactive,
      rotateGesturesEnabled: false, tiltGesturesEnabled: false,
      doubleClickZoomEnabled: widget.interactive),
    if (_failed) ColoredBox(color: Theme.of(context).colorScheme.surface,
      child: Center(child: Padding(padding: const EdgeInsets.all(12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('تعذّر عرض الخريطة الآن.', textAlign: TextAlign.center),
          TextButton(onPressed: _retry, child: const Text('إعادة تحميل الخريطة')),
        ])))),
    if (!_ready && !_failed) const IgnorePointer(child: Center(child: SizedBox.square(dimension: 22,
      child: CircularProgressIndicator(strokeWidth: 2)))),
  ]);
  }
}

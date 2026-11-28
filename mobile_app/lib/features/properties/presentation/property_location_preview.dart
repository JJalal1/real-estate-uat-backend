import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/theme/app_theme.dart';
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
    this.listingTitle,
    super.key,
  });

  final double latitude, longitude;
  final String? listingTitle;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(listingTitle ?? 'موقع العقار', maxLines: 1, overflow: TextOverflow.ellipsis)),
    body: _PublicPropertyMap(
      latitude: latitude,
      longitude: longitude,
      interactive: true,
      listingTitle: listingTitle,
    ),
  );
}

class _PublicPropertyMap extends StatefulWidget {
  const _PublicPropertyMap({
    required this.latitude,
    required this.longitude,
    this.interactive = false,
    this.listingTitle,
    super.key,
  });

  final double latitude, longitude;
  final bool interactive;
  final String? listingTitle;
  @override
  State<_PublicPropertyMap> createState() => _PublicPropertyMapState();
}

class _PublicPropertyMapState extends State<_PublicPropertyMap> {
  AqerMapController? _controller;
  Timer? _timeout;
  int _attempt = 0;
  bool _ready = false, _failed = false;
  bool _alternate = false;
  bool _slow = false;
  Timer? _slowTimer;
  bool get _isReview => widget.listingTitle != null;
  @override
  void initState() {
    super.initState();
    _startTimeout();
  }
  void _startTimeout() {
    _timeout?.cancel();
    _slowTimer?.cancel();
    if (_isReview) {
      _slowTimer = Timer(const Duration(seconds: 6), () {
        if (mounted && !_ready) setState(() => _slow = true);
      });
    }
    _timeout = Timer(const Duration(seconds: 20), () {
      if (mounted && !_ready) setState(() => _failed = true);
    });
  }
  @override
  void dispose() { _timeout?.cancel(); _slowTimer?.cancel(); super.dispose(); }

  void _retry({bool changeRenderer = false}) {
    setState(() {
      _attempt++;
      _ready = false;
      _failed = false;
      _slow = false;
      _controller = null;
      if (changeRenderer) _alternate = !_alternate;
    });
    _startTimeout();
  }

  Future<void> _styleLoaded(int attempt) async {
    final controller = _controller;
    if (controller == null || !mounted || attempt != _attempt) return;
    try {
      final location = LatLng(widget.latitude, widget.longitude);
      final title = widget.listingTitle;
      if (title == null) {
        await controller.addCircle(CircleOptions(
          geometry: location, circleRadius: 8,
          circleColor: '#127C7E', circleStrokeColor: '#FFFFFF', circleStrokeWidth: 3,
        )).timeout(const Duration(seconds: 5));
      } else {
        const markerName = 'reviewed-listing-location';
        final image = await _listingMarker(title);
        if (!mounted || attempt != _attempt || _controller != controller) return;
        await controller.addImage(markerName, image).timeout(const Duration(seconds: 5));
        if (!mounted || attempt != _attempt || _controller != controller) return;
        await controller.addSymbols([
          SymbolOptions(geometry: location, iconImage: markerName, iconAnchor: 'bottom', iconSize: .85),
        ], [<String, dynamic>{}]).timeout(const Duration(seconds: 5));
      }
      if (mounted && attempt == _attempt && _controller == controller) {
        setState(() { _ready = true; _failed = false; });
      }
    } catch (_) {
      if (mounted && attempt == _attempt && _controller == controller) {
        setState(() => _failed = true);
      }
    } finally {
      if (attempt == _attempt && _controller == controller) {
        _timeout?.cancel();
        _slowTimer?.cancel();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final attempt = _attempt;
    return Stack(fit: StackFit.expand, children: [
    AqerMap(key: ValueKey(attempt),
      useAlternateRenderer: _alternate,
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
        if (!_isReview) _startTimeout();
      },
      onStyleLoadedCallback: () => _styleLoaded(attempt),
      scrollGesturesEnabled: widget.interactive, zoomGesturesEnabled: widget.interactive,
      rotateGesturesEnabled: false, tiltGesturesEnabled: false,
      doubleClickZoomEnabled: widget.interactive),
    if (_failed) ColoredBox(color: Theme.of(context).colorScheme.surface,
      child: Center(child: Padding(padding: const EdgeInsets.all(12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('تعذّر عرض الخريطة الآن.', textAlign: TextAlign.center),
          TextButton(onPressed: () => _retry(), child: const Text('إعادة تحميل الخريطة')),
        ])))),
    if (!_ready && !_failed) IgnorePointer(child: Center(child: _isReview
      ? Card(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(_slow ? 'تأخر تحميل الخريطة…' : 'جارٍ تحميل موقع العقار…'),
          ]),
        ))
      : const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2)))),
    if (_isReview && AqerMap.supportsGoogle)
      PositionedDirectional(start: 12, end: 12, top: 12,
        child: SafeArea(bottom: false, child: Wrap(spacing: 8, children: [
          ActionChip(
            avatar: const Icon(Icons.layers_outlined, size: 18),
            label: Text(_alternate ? 'خرائط Google' : 'خريطة بديلة'),
            onPressed: () => _retry(changeRenderer: true),
          ),
          if (_ready)
            ActionChip(
              avatar: const Icon(Icons.refresh, size: 18),
              label: const Text('إعادة التحميل'),
              onPressed: () => _retry(),
            ),
        ]))),
  ]);
  }
}

Future<Uint8List> _listingMarker(String title) async {
  const scale = 2.0;
  const color = Color(0xFF0B7778);
  final label = TextPainter(
    text: TextSpan(text: title, style: const TextStyle(
      fontFamily: AppTypography.fontFamily,
      fontFamilyFallback: AppTypography.fontFamilyFallback,
      color: Color(0xFF152C41), fontSize: 13, fontWeight: FontWeight.w600,
    )),
    textDirection: TextDirection.rtl,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: 146);
  final width = (label.width + 20).clamp(48.0, 166.0).toDouble();
  final center = width / 2;
  final height = label.height + 36;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(scale);
  final caption = RRect.fromRectAndRadius(
    Rect.fromLTWH(2, 2, width - 4, label.height + 10),
    const Radius.circular(8),
  );
  canvas.drawRRect(caption, Paint()..color = Colors.white);
  canvas.drawRRect(caption, Paint()..color = color..style = PaintingStyle.stroke);
  label.paint(canvas, Offset((width - label.width) / 2, 7));
  label.dispose();

  final top = height - 24;
  final pin = Path()
    ..moveTo(center, height)
    ..cubicTo(center - 26, top, center - 5, top - 6, center, top)
    ..cubicTo(center + 5, top - 6, center + 26, top, center, height)
    ..close();
  canvas.drawPath(pin, Paint()..color = color);
  canvas.drawCircle(Offset(center, top + 7), 3.5, Paint()..color = Colors.white);
  final picture = recorder.endRecording();
  final image = await picture.toImage((width * scale).ceil(), (height * scale).ceil());
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) throw StateError('Could not encode listing marker.');
  return data.buffer.asUint8List();
}

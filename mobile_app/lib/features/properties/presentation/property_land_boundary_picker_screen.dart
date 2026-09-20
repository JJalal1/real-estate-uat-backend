import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/design/app_design.dart';
import 'listing_map_dock.dart';

class PropertyLandBoundarySelection {
  const PropertyLandBoundarySelection(this.points);

  final List<LatLng> points;

  Map<String, dynamic> get geoJson => <String, dynamic>{
        'type': 'Polygon',
        'coordinates': <dynamic>[
          <dynamic>[
            ...points.map((point) => <double>[point.longitude, point.latitude]),
            if (points.isNotEmpty)
              <double>[points.first.longitude, points.first.latitude],
          ],
        ],
      };
}

class PropertyLandBoundaryPickerScreen extends StatefulWidget {
  const PropertyLandBoundaryPickerScreen({
    super.key,
    required this.initialLatitude,
    required this.initialLongitude,
    this.initialBoundary,
  });

  final double initialLatitude;
  final double initialLongitude;
  final Map<String, dynamic>? initialBoundary;

  @override
  State<PropertyLandBoundaryPickerScreen> createState() =>
      _PropertyLandBoundaryPickerScreenState();
}

class _PropertyLandBoundaryPickerScreenState
    extends State<PropertyLandBoundaryPickerScreen> {
  static const _mapStyle = 'https://tiles.openfreemap.org/styles/liberty';
  MapLibreMapController? _map;
  bool _styleLoaded = false;
  late final List<LatLng> _points;

  @override
  void initState() {
    super.initState();
    _points = _decode(widget.initialBoundary);
  }

  List<LatLng> _decode(Map<String, dynamic>? value) {
    final coordinates = value?['coordinates'];
    if (coordinates is! List ||
        coordinates.isEmpty ||
        coordinates.first is! List) {
      return <LatLng>[];
    }
    final ring = coordinates.first as List;
    final points = <LatLng>[];
    for (final raw in ring) {
      if (raw is! List || raw.length < 2) continue;
      final lon = (raw[0] as num?)?.toDouble();
      final lat = (raw[1] as num?)?.toDouble();
      if (lat == null || lon == null) continue;
      final point = LatLng(lat, lon);
      if (points.isEmpty ||
          points.last.latitude != point.latitude ||
          points.last.longitude != point.longitude) {
        points.add(point);
      }
    }
    if (points.length > 1 &&
        points.first.latitude == points.last.latitude &&
        points.first.longitude == points.last.longitude) {
      points.removeLast();
    }
    return points;
  }

  void _onMapCreated(MapLibreMapController controller) => _map = controller;

  Future<void> _onStyleLoaded() async {
    _styleLoaded = true;
    await _syncDrawing();
  }

  void _onMapClick(math.Point<double> _, LatLng point) {
    if (!_styleLoaded) return;
    setState(() => _points.add(point));
    _syncDrawing();
  }

  Future<void> _syncDrawing() async {
    final map = _map;
    if (map == null || !_styleLoaded) return;
    try {
      await map.clearFills();
      await map.clearLines();
      await map.clearCircles();
      for (final point in _points) {
        await map.addCircle(CircleOptions(
          geometry: point,
          circleRadius: 6,
          circleColor: '#0B8A55',
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 2,
        ));
      }
      if (_points.length >= 2) {
        final line =
            _points.length >= 3 ? <LatLng>[..._points, _points.first] : _points;
        await map.addLine(LineOptions(
          geometry: line,
          lineColor: '#0B8A55',
          lineWidth: 3,
        ));
      }
      if (_points.length >= 3) {
        await map.addFill(FillOptions(
          geometry: <List<LatLng>>[
            <LatLng>[..._points, _points.first],
          ],
          fillColor: '#95D5B2',
          fillOpacity: 0.30,
        ));
      }
    } catch (_) {
      // Backend geometry validation remains authoritative.
    }
  }

  void _undo() {
    if (_points.isEmpty) return;
    setState(() => _points.removeLast());
    _syncDrawing();
  }

  void _clear() {
    if (_points.isEmpty) return;
    setState(_points.clear);
    _syncDrawing();
  }

  void _confirm() {
    if (_points.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حدد ثلاث زوايا على الأقل لحدود الأرض.')),
      );
      return;
    }
    Navigator.of(context)
        .pop(PropertyLandBoundarySelection(List.unmodifiable(_points)));
  }

  @override
  Widget build(BuildContext context) {
    final center = LatLng(widget.initialLatitude, widget.initialLongitude);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppAppBar(
          title: 'رسم حدود الأرض',
          actions: [
            IconButton(
              tooltip: 'تراجع عن آخر نقطة',
              onPressed: _points.isEmpty ? null : _undo,
              icon: const Icon(Icons.undo_rounded),
            ),
            IconButton(
              tooltip: 'مسح الحدود',
              onPressed: _points.isEmpty ? null : _clear,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: MapLibreMap(
                styleString: _mapStyle,
                initialCameraPosition: CameraPosition(target: center, zoom: 17),
                onMapCreated: _onMapCreated,
                onStyleLoadedCallback: _onStyleLoaded,
                onMapClick: _onMapClick,
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: false,
                minMaxZoomPreference: const MinMaxZoomPreference(4, 20),
              ),
            ),
            PositionedDirectional(
              start: 0,
              end: 0,
              bottom: 0,
              child: ListingMapDock(
                instruction: _points.isEmpty
                    ? 'اضغط على زوايا الأرض بالترتيب. لا تعتمد على الدبوس وحده.'
                    : 'تم تحديد ${_points.length} نقطة. أكمل محيط الأرض ثم أكد الحدود.',
                primaryLabel: 'اعتماد حدود الأرض',
                onPrimary: _points.length >= 3 ? _confirm : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

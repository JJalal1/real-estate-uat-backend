import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as google;
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/network/api_client.dart';
import '../../../core/offline/offline_connection.dart';

final _mapLayerProvider = StateProvider<google.MapType>(
  (ref) => google.MapType.normal,
);

class AqerMapLayerButton extends ConsumerWidget {
  const AqerMapLayerButton({this.enabled = true, super.key});

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(_mapLayerProvider);
    const labels = {
      google.MapType.normal: 'خريطة الشوارع',
      google.MapType.satellite: 'قمر صناعي',
      google.MapType.hybrid: 'هجين (صور وأسماء الشوارع)',
    };
    return PopupMenuButton<google.MapType>(
      tooltip: 'طبقات الخريطة',
      icon: const Icon(Icons.layers_outlined),
      enabled: enabled,
      position: PopupMenuPosition.under,
      onSelected: (layer) => ref.read(_mapLayerProvider.notifier).state = layer,
      itemBuilder: (context) => [
        for (final entry in labels.entries)
          CheckedPopupMenuItem<google.MapType>(
            value: entry.key,
            checked: entry.key == selected,
            child: Text(entry.value),
          ),
      ],
    );
  }
}

/// The common property map. Android UAT uses the configured Google SDK online.
class AqerMap extends ConsumerStatefulWidget {
  const AqerMap({
    required this.initialCameraPosition,
    required this.onMapCreated,
    required this.onStyleLoadedCallback,
    this.onCameraIdle,
    this.onMapClick,
    this.minMaxZoomPreference = const MinMaxZoomPreference(3, 19),
    this.padding = EdgeInsets.zero,
    this.rememberCameraAcrossRenderers = true,
    this.myLocationEnabled = false,
    this.rotateGesturesEnabled = true,
    this.tiltGesturesEnabled = true,
    this.scrollGesturesEnabled = true,
    this.zoomGesturesEnabled = true,
    this.doubleClickZoomEnabled = true,
    super.key,
  });

  final CameraPosition initialCameraPosition;
  final ValueChanged<AqerMapController> onMapCreated;
  final VoidCallback onStyleLoadedCallback;
  final VoidCallback? onCameraIdle;
  final ValueChanged<LatLng>? onMapClick;
  final MinMaxZoomPreference minMaxZoomPreference;
  final EdgeInsets padding;
  final bool rememberCameraAcrossRenderers;
  final bool myLocationEnabled,
      rotateGesturesEnabled,
      tiltGesturesEnabled,
      scrollGesturesEnabled,
      zoomGesturesEnabled,
      doubleClickZoomEnabled;

  @override
  ConsumerState<AqerMap> createState() => _AqerMapState();
}

class _AqerMapState extends ConsumerState<AqerMap> {
  AqerMapController? _controller;
  CameraPosition? _lastPosition;

  void _onCreated(AqerMapController controller) {
    _controller = controller;
    widget.onMapCreated(controller);
  }

  void _onIdle() {
    _lastPosition = widget.rememberCameraAcrossRenderers
        ? _controller?.cameraPosition ?? _lastPosition
        : null;
    widget.onCameraIdle?.call();
  }

  @override
  Widget build(BuildContext context) {
    final online =
        ref.watch(offlineConnectionProvider) != OfflineConnection.offline;
    final initialPosition =
        (widget.rememberCameraAcrossRenderers ? _lastPosition : null) ??
            widget.initialCameraPosition;
    if (const bool.fromEnvironment('AQER_GOOGLE_MAPS_UAT') &&
        ApiEnvironmentConfig.isUat &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        online) {
      return _GoogleCanvas(
        options: widget,
        position: initialPosition,
        onCreated: _onCreated,
        onIdle: _onIdle,
      );
    }
    return MapLibreMap(
      styleString: 'https://tiles.openfreemap.org/styles/liberty',
      initialCameraPosition: initialPosition,
      onMapCreated: (controller) =>
          _onCreated(AqerMapController._mapLibre(controller)),
      onStyleLoadedCallback: widget.onStyleLoadedCallback,
      onCameraIdle: _onIdle,
      onMapClick: (_, point) => widget.onMapClick?.call(point),
      trackCameraPosition: true,
      myLocationEnabled: widget.myLocationEnabled,
      myLocationTrackingMode: MyLocationTrackingMode.none,
      minMaxZoomPreference: widget.minMaxZoomPreference,
      rotateGesturesEnabled: widget.rotateGesturesEnabled,
      tiltGesturesEnabled: widget.tiltGesturesEnabled,
      scrollGesturesEnabled: widget.scrollGesturesEnabled,
      zoomGesturesEnabled: widget.zoomGesturesEnabled,
      doubleClickZoomEnabled: widget.doubleClickZoomEnabled,
    );
  }
}

class _GoogleCanvas extends ConsumerStatefulWidget {
  const _GoogleCanvas({
    required this.options,
    required this.position,
    required this.onCreated,
    required this.onIdle,
  });

  final AqerMap options;
  final CameraPosition position;
  final ValueChanged<AqerMapController> onCreated;
  final VoidCallback onIdle;

  @override
  ConsumerState<_GoogleCanvas> createState() => _GoogleCanvasState();
}

class _GoogleCanvasState extends ConsumerState<_GoogleCanvas> {
  AqerMapController? _controller;

  void _onCreated(google.GoogleMapController native) {
    if (!mounted) return;
    final controller = AqerMapController._google(native, widget.position, () {
      if (mounted) setState(() {});
    });
    setState(() => _controller = controller);
    widget.onCreated(controller);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.options.onStyleLoadedCallback();
    });
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.options;
    final controller = _controller;
    return google.GoogleMap(
      initialCameraPosition: _googlePosition(widget.position),
      mapType: ref.watch(_mapLayerProvider),
      onMapCreated: _onCreated,
      onCameraMove: (position) {
        _controller?._position = CameraPosition(
          target: _point(position.target),
          zoom: position.zoom,
          bearing: position.bearing,
          tilt: position.tilt,
        );
      },
      onCameraIdle: widget.onIdle,
      onTap: options.onMapClick == null
          ? null
          : (position) => options.onMapClick!(_point(position)),
      markers: controller?._markers.values.toSet() ?? const {},
      polygons: controller?._polygons.values.toSet() ?? const {},
      polylines: controller?._lines.values.toSet() ?? const {},
      padding: options.padding,
      compassEnabled: false,
      mapToolbarEnabled: false,
      zoomControlsEnabled: false,
      myLocationButtonEnabled: false,
      myLocationEnabled: options.myLocationEnabled,
      minMaxZoomPreference: google.MinMaxZoomPreference(
        options.minMaxZoomPreference.minZoom,
        options.minMaxZoomPreference.maxZoom,
      ),
      rotateGesturesEnabled: options.rotateGesturesEnabled,
      tiltGesturesEnabled: options.tiltGesturesEnabled,
      scrollGesturesEnabled: options.scrollGesturesEnabled,
      zoomGesturesEnabled: options.zoomGesturesEnabled,
    );
  }
}

google.LatLng _googlePoint(LatLng point) =>
    google.LatLng(point.latitude, point.longitude);
LatLng _point(google.LatLng point) => LatLng(point.latitude, point.longitude);

google.CameraPosition _googlePosition(CameraPosition position) =>
    google.CameraPosition(
      target: _googlePoint(position.target),
      zoom: position.zoom,
      tilt: position.tilt,
      bearing: position.bearing,
    );

google.CameraUpdate _googleUpdate(CameraUpdate update) {
  final values = update.toJson() as List<dynamic>;
  google.LatLng readPoint(dynamic value) {
    final pair = value as List<dynamic>;
    return google.LatLng(
        (pair[0] as num).toDouble(), (pair[1] as num).toDouble());
  }

  switch (values.first) {
    case 'newCameraPosition':
      final view = values[1] as Map<String, dynamic>;
      return google.CameraUpdate.newCameraPosition(google.CameraPosition(
        target: readPoint(view['target']),
        zoom: view['zoom'] as double,
        tilt: view['tilt'] as double,
        bearing: view['bearing'] as double,
      ));
    case 'newLatLngZoom':
      return google.CameraUpdate.newLatLngZoom(
          readPoint(values[1]), values[2] as double);
    case 'newLatLngBounds':
      final corners = values[1] as List<dynamic>;
      return google.CameraUpdate.newLatLngBounds(
          google.LatLngBounds(
            southwest: readPoint(corners[0]),
            northeast: readPoint(corners[1]),
          ),
          math.max(values[2] as double, values[4] as double));
    default:
      throw UnsupportedError(
          'Unsupported property map camera update: ${values.first}');
  }
}

Color _mapColor(String? value, [double opacity = 1]) => value == null
    ? Colors.transparent
    : Color(0xff000000 | int.parse(value.replaceFirst('#', ''), radix: 16))
        .withValues(alpha: opacity.clamp(0, 1).toDouble());

class AqerMapController {
  AqerMapController._mapLibre(this._libre)
      : _google = null,
        _redraw = null;
  AqerMapController._google(this._google, this._position, this._redraw)
      : _libre = null;

  final MapLibreMapController? _libre;
  final google.GoogleMapController? _google;
  final VoidCallback? _redraw;
  CameraPosition? _position;
  ValueChanged<Symbol>? _onSymbolTap;
  int _nextId = 0;
  final _images = <String, Uint8List>{};
  final _markers = <String, google.Marker>{};
  final _polygons = <String, google.Polygon>{};
  final _lines = <String, google.Polyline>{};
  final _circleIcons =
      <(double, double, Color, Color), Future<google.BitmapDescriptor>>{};

  CameraPosition? get cameraPosition => _libre?.cameraPosition ?? _position;
  bool get usesGoogle => _google != null;

  void listenForSymbolTaps(ValueChanged<Symbol> callback) {
    _libre?.onSymbolTapped.add(callback);
    _onSymbolTap = callback;
  }

  Future<void> animateCamera(CameraUpdate update) async {
    if (_libre != null) {
      await _libre.animateCamera(update);
    } else {
      await _google!.animateCamera(_googleUpdate(update));
    }
  }

  Future<void> moveCamera(CameraUpdate update) async {
    if (_libre != null) {
      await _libre.moveCamera(update);
    } else {
      await _google!.moveCamera(_googleUpdate(update));
    }
  }

  Future<LatLngBounds> getVisibleRegion() async {
    if (_libre != null) return _libre.getVisibleRegion();
    final bounds = await _google!.getVisibleRegion();
    return LatLngBounds(
        southwest: _point(bounds.southwest),
        northeast: _point(bounds.northeast));
  }

  Future<math.Point<num>> toScreenLocation(LatLng point) async {
    if (_libre != null) return _libre.toScreenLocation(point);
    final pixel = await _google!.getScreenCoordinate(_googlePoint(point));
    return math.Point(pixel.x, pixel.y);
  }

  Future<LatLng> toLatLng(math.Point<num> pixel) async {
    if (_libre != null) return _libre.toLatLng(pixel);
    return _point(await _google!.getLatLng(
      google.ScreenCoordinate(x: pixel.x.round(), y: pixel.y.round()),
    ));
  }

  Future<void> addImage(String name, Uint8List bytes) async {
    if (_libre != null) {
      await _libre.addImage(name, bytes);
    } else {
      _images[name] = bytes;
    }
  }

  void _paintSymbol(Symbol symbol) {
    final options = symbol.options;
    final image = _images[options.iconImage];
    _markers[symbol.id] = google.Marker(
      markerId: google.MarkerId(symbol.id),
      position: _googlePoint(options.geometry!),
      icon: image == null
          ? google.BitmapDescriptor.defaultMarker
          : google.BitmapDescriptor.bytes(image,
              imagePixelRatio: 2 / (options.iconSize ?? 1)),
      anchor: options.iconAnchor == 'center'
          ? const Offset(.5, .5)
          : const Offset(.5, 1),
      zIndexInt: options.zIndex ?? 0,
      consumeTapEvents: true,
      onTap: () => _onSymbolTap?.call(symbol),
    );
  }

  Future<List<Symbol>> addSymbols(
      List<SymbolOptions> options, List<Map<String, dynamic>> data) async {
    if (_libre != null) return _libre.addSymbols(options, data);
    final symbols = [
      for (var i = 0; i < options.length; i++)
        Symbol('listing-${_nextId++}', options[i], data[i]),
    ];
    symbols.forEach(_paintSymbol);
    _redraw?.call();
    return symbols;
  }

  Future<void> updateSymbol(Symbol symbol, SymbolOptions options) async {
    if (_libre != null) return _libre.updateSymbol(symbol, options);
    symbol.options = symbol.options.copyWith(options);
    _paintSymbol(symbol);
    _redraw?.call();
  }

  Future<void> removeSymbols(Iterable<Symbol> symbols) async {
    if (_libre != null) return _libre.removeSymbols(symbols);
    for (final symbol in symbols) {
      _markers.remove(symbol.id);
    }
    _redraw?.call();
  }

  Future<void> allowSymbolOverlap() async {
    if (_libre == null) return;
    await _libre.setSymbolIconAllowOverlap(true);
    await _libre.setSymbolIconIgnorePlacement(true);
  }

  Future<Fill> addFill(FillOptions options) async {
    if (_libre != null) return _libre.addFill(options);
    final fill = Fill('area-${_nextId++}', options);
    final rings = options.geometry!;
    _polygons[fill.id] = google.Polygon(
      polygonId: google.PolygonId(fill.id),
      points: rings.first.map(_googlePoint).toList(),
      holes: [
        for (final ring in rings.skip(1)) ring.map(_googlePoint).toList()
      ],
      fillColor: _mapColor(options.fillColor, options.fillOpacity ?? 1),
      strokeColor: _mapColor(options.fillOutlineColor),
      strokeWidth: options.fillOutlineColor == null ? 0 : 1,
    );
    _redraw?.call();
    return fill;
  }

  Future<void> removeFill(Fill fill) async {
    if (_libre != null) return _libre.removeFill(fill);
    _polygons.remove(fill.id);
    _redraw?.call();
  }

  Future<void> clearFills() async {
    if (_libre != null) return _libre.clearFills();
    _polygons.clear();
    _redraw?.call();
  }

  Future<Line> addLine(LineOptions options) async {
    if (_libre != null) return _libre.addLine(options);
    final line = Line('line-${_nextId++}', options);
    _lines[line.id] = google.Polyline(
      polylineId: google.PolylineId(line.id),
      points: options.geometry!.map(_googlePoint).toList(),
      color: _mapColor(options.lineColor, options.lineOpacity ?? 1),
      width: (options.lineWidth ?? 3).round(),
    );
    _redraw?.call();
    return line;
  }

  Future<void> removeLine(Line line) async {
    if (_libre != null) return _libre.removeLine(line);
    _lines.remove(line.id);
    _redraw?.call();
  }

  Future<void> clearLines() async {
    if (_libre != null) return _libre.clearLines();
    _lines.clear();
    _redraw?.call();
  }

  Future<void> addCircle(CircleOptions options) async {
    if (_libre != null) {
      await _libre.addCircle(options);
      return;
    }
    final circle = (
      options.circleRadius ?? 6,
      options.circleStrokeWidth ?? 0,
      _mapColor(options.circleColor, options.circleOpacity ?? 1),
      _mapColor(options.circleStrokeColor, options.circleStrokeOpacity ?? 1),
    );
    final icon =
        await _circleIcons.putIfAbsent(circle, () => _circleIcon(circle));
    final id = 'point-${_nextId++}';
    _markers[id] = google.Marker(
      markerId: google.MarkerId(id),
      position: _googlePoint(options.geometry!),
      anchor: const Offset(.5, .5),
      icon: icon,
      consumeTapEvents: true,
    );
    _redraw?.call();
  }

  Future<void> clearCircles() async {
    if (_libre != null) return _libre.clearCircles();
    _markers.removeWhere((key, _) => key.startsWith('point-'));
    _redraw?.call();
  }
}

Future<google.BitmapDescriptor> _circleIcon(
    (double, double, Color, Color) paint) async {
  final (radius, stroke, fillColor, strokeColor) = paint;
  final size = ((radius + stroke + 1) * 4).ceil();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final middle = Offset(size / 2, size / 2);
  canvas.drawCircle(
      middle, (radius + stroke) * 2, Paint()..color = strokeColor);
  canvas.drawCircle(middle, radius * 2, Paint()..color = fillColor);
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(size, size);
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) {
        throw StateError('Could not draw the property map marker.');
      }
      return google.BitmapDescriptor.bytes(png.buffer.asUint8List(),
          imagePixelRatio: 2);
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

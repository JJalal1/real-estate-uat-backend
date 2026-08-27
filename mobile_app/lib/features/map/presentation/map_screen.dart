import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/map_area_geometry.dart';
import '../domain/map_screen_coordinate_space.dart';
import '../../properties/data/property_repository.dart';
import '../../properties/domain/property_marker.dart';

const double mapPropertyPriceIconSize = 1.0;

String mapPropertyPriceLabel(double price) {
  if (!price.isFinite || price <= 0) return 'السعر';
  if (price >= 1000000000) {
    return '${_compactMapAmount(price / 1000000000)} مليار';
  }
  if (price >= 1000000) {
    return '${_compactMapAmount(price / 1000000)} مليون';
  }
  if (price >= 1000) {
    return '${_compactMapAmount(price / 1000)} ألف';
  }
  return price.round().toString();
}

String _compactMapAmount(double value) {
  final whole = value.roundToDouble();
  if ((value - whole).abs() < 0.05) {
    return whole.toInt().toString();
  }
  if (value >= 100) {
    return value.toStringAsFixed(0);
  }
  if (value >= 10) {
    return value.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
  }
  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

String mapPropertyPriceImageName(
  String label, {
  required bool selected,
  required bool rent,
}) {
  var hash = 0x811C9DC5;
  for (final unit in label.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  final state = selected ? 'selected' : (rent ? 'rent' : 'sale');
  return 're_price_${hash.toRadixString(16)}_$state';
}

Future<Uint8List> renderMapPropertyPriceImage(
  String label, {
  required bool selected,
  required bool rent,
}) async {
  const renderScale = 2.0;
  final borderColor = selected
      ? const Color(0xFF246BFD)
      : rent
          ? const Color(0xFF147D92)
          : const Color(0xFF0B8A55);
  final background = selected ? const Color(0xFF246BFD) : Colors.white;
  final foreground = selected ? Colors.white : borderColor;
  final height = selected ? 32.0 : 30.0;
  final borderWidth = selected ? 2.2 : 1.5;

  final textPainter = TextPainter(
    text: TextSpan(
      text: label,
      style: TextStyle(
        color: foreground,
        fontSize: selected ? 13 : 12,
        fontWeight: FontWeight.w900,
        height: 1.05,
      ),
    ),
    textDirection: TextDirection.rtl,
    maxLines: 1,
  )..layout(maxWidth: 96);

  final width = (textPainter.width + 18).clamp(48.0, 112.0).toDouble();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(renderScale);
  final rect = Rect.fromLTWH(3, 3, width - 6, height - 6);
  final rrect = RRect.fromRectAndRadius(rect, Radius.circular(height / 2));

  canvas.drawRRect(
    rrect.shift(const Offset(0, 1.5)),
    Paint()
      ..color = const Color(0x26000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
  );
  canvas.drawRRect(rrect, Paint()..color = background);
  canvas.drawRRect(
    rrect,
    Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth,
  );

  final textOffset = Offset(
    (width - textPainter.width) / 2,
    (height - textPainter.height) / 2 - 0.5,
  );
  textPainter.paint(canvas, textOffset);

  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (width * renderScale).ceil(),
    (height * renderScale).ceil(),
  );
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (byteData == null) {
    throw StateError('Unable to encode map price image.');
  }
  return byteData.buffer.asUint8List();
}

class NearbyQuery {
  const NearbyQuery({
    required this.center,
    this.radiusKm = 30,
    this.purpose,
    this.type,
    this.minPrice,
    this.maxPrice,
    this.minBedrooms,
    this.minBathrooms,
    this.minArea,
    this.maxArea,
    this.search,
    this.south,
    this.west,
    this.north,
    this.east,
  });

  final LatLng center;
  final double radiusKm;
  final String? purpose;
  final String? type;
  final double? minPrice;
  final double? maxPrice;
  final int? minBedrooms;
  final int? minBathrooms;
  final double? minArea;
  final double? maxArea;
  final String? search;
  final double? south;
  final double? west;
  final double? north;
  final double? east;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is NearbyQuery &&
            other.center.latitude == center.latitude &&
            other.center.longitude == center.longitude &&
            other.radiusKm == radiusKm &&
            other.purpose == purpose &&
            other.type == type &&
            other.minPrice == minPrice &&
            other.maxPrice == maxPrice &&
            other.minBedrooms == minBedrooms &&
            other.minBathrooms == minBathrooms &&
            other.minArea == minArea &&
            other.maxArea == maxArea &&
            other.search == search &&
            other.south == south &&
            other.west == west &&
            other.north == north &&
            other.east == east;
  }

  @override
  int get hashCode => Object.hashAll([
        center.latitude,
        center.longitude,
        radiusKm,
        purpose,
        type,
        minPrice,
        maxPrice,
        minBedrooms,
        minBathrooms,
        minArea,
        maxArea,
        search,
        south,
        west,
        north,
        east,
      ]);
}

final nearbyPropertiesProvider =
    FutureProvider.autoDispose.family<List<PropertyMarker>, NearbyQuery>(
  (ref, query) {
    ref.watch(propertyDataRevisionProvider);
    return ref.watch(propertyRepositoryProvider).nearby(
          latitude: query.center.latitude,
          longitude: query.center.longitude,
          radiusKm: query.radiusKm,
          purpose: query.purpose,
          type: query.type,
          minPrice: query.minPrice,
          maxPrice: query.maxPrice,
          minBedrooms: query.minBedrooms,
          minBathrooms: query.minBathrooms,
          minArea: query.minArea,
          maxArea: query.maxArea,
          search: query.search,
          south: query.south,
          west: query.west,
          north: query.north,
          east: query.east,
        );
  },
);

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  static const _fallback = LatLng(15.3694, 44.1910);
  static const _openFreeMapStyle =
      'https://tiles.openfreemap.org/styles/liberty';
  static const double _defaultRadiusKm = 30;

  MapLibreMapController? _mapController;
  Timer? _styleLoadTimer;

  LatLng _center = _fallback;
  LatLng? _userLocation;
  PropertyMarker? _selected;

  String? _filterPurpose;
  String? _filterType;
  double? _filterMinPrice;
  double? _filterMaxPrice;
  int? _filterMinBedrooms;
  int? _filterMinBathrooms;
  double? _filterMinArea;
  double? _filterMaxArea;

  LatLngBounds? _selectedAreaBounds;
  MapAreaGeometry? _selectedAreaGeometry;
  Fill? _selectedAreaFill;
  Line? _selectedAreaLine;
  List<Offset> _areaDraftPoints = <Offset>[];
  bool _selectingArea = false;
  bool _listMode = false;
  int _sortMode = 0;

  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';

  bool _styleLoaded = false;
  String? _mapMessage;
  String _lastMarkerSignature = '';
  int _annotationGeneration = 0;
  List<PropertyMarker> _latestMarkerItems = const <PropertyMarker>[];
  final Set<String> _registeredPriceImages = <String>{};

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
  }

  @override
  void dispose() {
    _styleLoadTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;

      final location = LatLng(position.latitude, position.longitude);
      setState(() {
        _center = location;
        _userLocation = location;
        _selected = null;
      });

      final controller = _mapController;
      if (controller != null) {
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(location, 14),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _userLocation = null);
    }
  }

  void _onMapCreated(MapLibreMapController controller) {
    _mapController = controller;
    controller.onSymbolTapped.add(_onPropertySymbolTapped);

    _styleLoadTimer?.cancel();
    _styleLoadTimer = Timer(const Duration(seconds: 20), () {
      if (!mounted || _styleLoaded) return;
      setState(() {
        _mapMessage =
            'تعذر تحميل الخريطة. تحقق من اتصال الهاتف بالإنترنت ثم حاول مرة أخرى.';
      });
    });
  }

  void _onStyleLoaded() {
    _styleLoadTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _styleLoaded = true;
      _mapMessage = null;
      _lastMarkerSignature = '';
      _selectedAreaFill = null;
      _selectedAreaLine = null;
      _registeredPriceImages.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _renderSelectedAreaAnnotations();
    });
  }

  Future<void> _moveToMyLocation() async {
    final controller = _mapController;
    final location = _userLocation;
    if (controller == null || location == null) return;
    await controller.animateCamera(CameraUpdate.newLatLngZoom(location, 14));
  }

  Future<void> _commitCameraCenter() async {
    if (_selectingArea) return;
    final controller = _mapController;
    if (controller == null) return;
    final camera = controller.cameraPosition;
    if (!mounted || camera == null) return;
    final next = camera.target;
    if (_samePoint(_center, next)) {
      _lastMarkerSignature = '';
      _queueMarkerSync(_latestMarkerItems);
      return;
    }
    setState(() {
      _center = next;
      _selected = null;
      _lastMarkerSignature = '';
    });
  }

  bool _samePoint(LatLng a, LatLng b) {
    return (a.latitude - b.latitude).abs() < 0.000001 &&
        (a.longitude - b.longitude).abs() < 0.000001;
  }

  String _markerSignature(List<PropertyMarker> items) {
    final ids = items
        .take(150)
        .map((item) =>
            '${item.id}:${item.price}:${item.purpose}:${item.latitude}:${item.longitude}')
        .join('|');
    return '${_selected?.id ?? 0}|$ids';
  }

  void _queueMarkerSync(List<PropertyMarker> items) {
    _latestMarkerItems = items.take(150).toList(growable: false);
    if (!_styleLoaded || _mapController == null) return;
    final signature = _markerSignature(items);
    if (signature == _lastMarkerSignature) return;
    _lastMarkerSignature = signature;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncPropertyAnnotations(items);
    });
  }

  Future<void> _syncPropertyAnnotations(List<PropertyMarker> items) async {
    final controller = _mapController;
    if (controller == null || !_styleLoaded) return;

    final generation = ++_annotationGeneration;
    final visible = items.take(150).toList(growable: false);

    try {
      // Price markers are native MapLibre symbols. Their label is rendered by
      // Flutter into a PNG first so Arabic remains reliable, while MapLibre
      // owns the geographic position and moves the marker with every camera
      // frame without Flutter overlay lag or post-pan jumping.
      final options = <SymbolOptions>[];
      final data = <Map<String, dynamic>>[];

      for (final property in visible) {
        final selected = property.id == _selected?.id;
        final rent = property.purpose == 'rent';
        final label = mapPropertyPriceLabel(property.price);
        final imageName = mapPropertyPriceImageName(
          label,
          selected: selected,
          rent: rent,
        );
        await _ensureMapPriceImage(
          controller,
          imageName: imageName,
          label: label,
          selected: selected,
          rent: rent,
        );
        if (generation != _annotationGeneration) return;

        options.add(
          SymbolOptions(
            geometry: LatLng(property.latitude, property.longitude),
            iconImage: imageName,
            iconSize: mapPropertyPriceIconSize,
            iconAnchor: 'center',
            zIndex: selected ? 20 : 1,
          ),
        );
        data.add(<String, dynamic>{'property_id': property.id});
      }

      if (generation != _annotationGeneration) return;
      await controller.clearSymbols();
      await controller.clearCircles();
      if (generation != _annotationGeneration) return;

      if (options.isNotEmpty) {
        await controller.addSymbols(options, data);
        if (generation != _annotationGeneration) return;
        await controller.setSymbolIconAllowOverlap(true);
        await controller.setSymbolIconIgnorePlacement(true);
      }

      if (!mounted || generation != _annotationGeneration) return;
      if (_mapMessage == 'تعذر تحديث أسعار العقارات على الخريطة.') {
        setState(() => _mapMessage = null);
      }
    } catch (_) {
      if (!mounted || generation != _annotationGeneration) return;
      _lastMarkerSignature = '';
      setState(() {
        _mapMessage = 'تعذر تحديث أسعار العقارات على الخريطة.';
      });
    }
  }

  Future<void> _ensureMapPriceImage(
    MapLibreMapController controller, {
    required String imageName,
    required String label,
    required bool selected,
    required bool rent,
  }) async {
    if (_registeredPriceImages.contains(imageName)) return;
    final bytes = await renderMapPropertyPriceImage(
      label,
      selected: selected,
      rent: rent,
    );
    await controller.addImage(imageName, bytes);
    _registeredPriceImages.add(imageName);
  }

  void _onPropertySymbolTapped(Symbol symbol) {
    final rawId = symbol.data?['property_id'];
    final propertyId = rawId is int ? rawId : int.tryParse('$rawId');

    PropertyMarker? property;
    if (propertyId != null) {
      for (final item in _latestMarkerItems) {
        if (item.id == propertyId) {
          property = item;
          break;
        }
      }
    }

    final geometry = symbol.options.geometry;
    if (property == null && geometry != null) {
      for (final item in _latestMarkerItems) {
        if ((item.latitude - geometry.latitude).abs() < 0.0000001 &&
            (item.longitude - geometry.longitude).abs() < 0.0000001) {
          property = item;
          break;
        }
      }
    }
    if (property == null || !mounted) return;

    setState(() {
      _selected = property;
      _lastMarkerSignature = '';
    });
  }

  Future<void> _focusProperty(PropertyMarker property) async {
    final controller = _mapController;
    if (controller == null) return;
    final target = LatLng(property.latitude, property.longitude);
    setState(() {
      _listMode = false;
      _selected = property;
      _lastMarkerSignature = '';
    });
    await controller.animateCamera(CameraUpdate.newLatLngZoom(target, 16));
    if (!mounted) return;
    setState(() => _center = target);
  }

  void _openDetails(PropertyMarker property) {
    setState(() => _selected = property);
    context.push('/properties/${property.id}');
  }

  bool _typeUsesRooms(String? type) {
    return type == 'apartment' || type == 'house' || type == 'villa';
  }

  void _setQuickPurpose(String? purpose) {
    setState(() {
      _filterPurpose = _filterPurpose == purpose ? null : purpose;
      _selected = null;
      _lastMarkerSignature = '';
    });
  }

  void _setQuickType(String? type) {
    setState(() {
      _filterType = _filterType == type ? null : type;
      if (!_typeUsesRooms(_filterType)) {
        _filterMinBedrooms = null;
        _filterMinBathrooms = null;
      }
      _selected = null;
      _lastMarkerSignature = '';
    });
  }

  void _resetFilters() {
    setState(() {
      _filterPurpose = null;
      _filterType = null;
      _filterMinPrice = null;
      _filterMaxPrice = null;
      _filterMinBedrooms = null;
      _filterMinBathrooms = null;
      _filterMinArea = null;
      _filterMaxArea = null;
      _selected = null;
      _lastMarkerSignature = '';
    });
  }

  int get _filterCount {
    var count = 0;
    if (_filterPurpose != null) count++;
    if (_filterType != null) count++;
    if (_filterMinPrice != null || _filterMaxPrice != null) count++;
    if (_filterMinBedrooms != null) count++;
    if (_filterMinBathrooms != null) count++;
    if (_filterMinArea != null || _filterMaxArea != null) count++;
    return count;
  }

  Future<void> _showFilters() async {
    final result = await showModalBottomSheet<_FilterResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PropertyFilterSheet(
        initialPurpose: _filterPurpose,
        initialType: _filterType,
        initialMinPrice: _filterMinPrice,
        initialMaxPrice: _filterMaxPrice,
        initialMinBedrooms: _filterMinBedrooms,
        initialMinBathrooms: _filterMinBathrooms,
        initialMinArea: _filterMinArea,
        initialMaxArea: _filterMaxArea,
      ),
    );

    if (!mounted || result == null) return;
    setState(() {
      _filterPurpose = result.purpose;
      _filterType = result.type;
      _filterMinPrice = result.minPrice;
      _filterMaxPrice = result.maxPrice;
      _filterMinBedrooms = result.minBedrooms;
      _filterMinBathrooms = result.minBathrooms;
      _filterMinArea = result.minArea;
      _filterMaxArea = result.maxArea;
      _selected = null;
      _lastMarkerSignature = '';
    });
  }

  Future<void> _showSearchSheet(List<PropertyMarker> items) async {
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _SearchSheet(
        initialValue: _searchController.text,
        suggestions: _searchSuggestions(items),
      ),
    );
    if (!mounted || value == null) return;

    final normalized = value.trim();
    _searchController.text = normalized;
    setState(() {
      _searchText = normalized;
      _selected = null;
      _lastMarkerSignature = '';
    });
  }

  List<String> _searchSuggestions(List<PropertyMarker> items) {
    final seen = <String>{};
    final values = <String>[];
    for (final item in items) {
      for (final candidate in [item.address, item.title]) {
        final text = candidate?.trim();
        if (text != null && text.isNotEmpty && seen.add(text)) {
          values.add(text);
          if (values.length == 8) return values;
        }
      }
    }
    return values;
  }

  void _beginAreaSelection() {
    setState(() {
      _selectingArea = true;
      _areaDraftPoints = <Offset>[];
      _listMode = false;
      _selected = null;
      _mapMessage = null;
    });
  }

  void _cancelAreaSelection() {
    setState(() {
      _selectingArea = false;
      _areaDraftPoints = <Offset>[];
    });
  }

  void _startAreaStroke(DragStartDetails details) {
    setState(() {
      _areaDraftPoints = <Offset>[details.localPosition];
      _mapMessage = null;
    });
  }

  void _updateAreaStroke(DragUpdateDetails details) {
    final next = details.localPosition;
    final points = _areaDraftPoints;
    if (points.isNotEmpty && (points.last - next).distance < 4) return;
    setState(() => _areaDraftPoints = <Offset>[...points, next]);
  }

  Future<void> _finishAreaStroke(DragEndDetails _) async {
    final controller = _mapController;
    final draft = _simplifyAreaStroke(_areaDraftPoints);
    if (controller == null || draft.length < 5) {
      if (mounted) {
        setState(() {
          _areaDraftPoints = <Offset>[];
          _mapMessage = 'ارسم حدود المنطقة بإصبعك بشكل مغلق وواضح.';
        });
      }
      return;
    }

    try {
      final geoPoints = <LatLng>[];
      final pixelRatio = MediaQuery.devicePixelRatioOf(context);
      for (final point in draft) {
        geoPoints.add(
          await controller.toLatLng(
            MapScreenCoordinateSpace.logicalToPlatformPixels(
              point,
              pixelRatio,
            ),
          ),
        );
      }
      final geometry = MapAreaGeometry.fromPoints(geoPoints);
      if (!geometry.isMeaningful) {
        if (mounted) {
          setState(() {
            _areaDraftPoints = <Offset>[];
            _mapMessage = 'المنطقة المرسومة صغيرة جداً. ارسم مساحة أكبر.';
          });
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        _selectedAreaGeometry = geometry;
        _selectedAreaBounds = geometry.bounds;
        _selectingArea = false;
        _areaDraftPoints = <Offset>[];
        _selected = null;
        _lastMarkerSignature = '';
        _center = geometry.center;
        _mapMessage = 'تم اعتماد المنطقة المرسومة وعرض العقارات داخلها فقط.';
      });
      await _renderSelectedAreaAnnotations();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _areaDraftPoints = <Offset>[];
        _mapMessage = 'تعذر تحويل الرسم إلى منطقة على الخريطة. حاول مرة أخرى.';
      });
    }
  }

  List<Offset> _simplifyAreaStroke(List<Offset> input) {
    if (input.length <= 2) return List<Offset>.from(input);
    final result = <Offset>[input.first];
    for (final point in input.skip(1)) {
      if ((point - result.last).distance >= 7) result.add(point);
    }
    if (result.last != input.last) result.add(input.last);
    if (result.length <= 80) return result;

    final sampled = <Offset>[];
    final step = (result.length / 78).ceil();
    for (var index = 0; index < result.length; index += step) {
      sampled.add(result[index]);
    }
    if (sampled.last != result.last) sampled.add(result.last);
    return sampled;
  }

  List<PropertyMarker> _filterToSelectedArea(List<PropertyMarker> items) {
    final geometry = _selectedAreaGeometry;
    if (geometry == null) return items;
    return items
        .where(
          (item) => geometry.contains(item.latitude, item.longitude),
        )
        .toList(growable: false);
  }

  Future<void> _removeAreaAnnotations() async {
    final controller = _mapController;
    if (controller == null || !_styleLoaded) return;
    final fill = _selectedAreaFill;
    final line = _selectedAreaLine;
    _selectedAreaFill = null;
    _selectedAreaLine = null;
    try {
      if (fill != null) await controller.removeFill(fill);
    } catch (_) {}
    try {
      if (line != null) await controller.removeLine(line);
    } catch (_) {}
  }

  Future<void> _renderSelectedAreaAnnotations() async {
    final controller = _mapController;
    final geometry = _selectedAreaGeometry;
    if (controller == null || !_styleLoaded) return;
    await _removeAreaAnnotations();
    if (geometry == null) return;

    try {
      final fill = await controller.addFill(
        FillOptions(
          geometry: <List<LatLng>>[geometry.points],
          fillColor: '#0B8A55',
          fillOpacity: 0.16,
          fillOutlineColor: '#0B8A55',
        ),
      );
      final line = await controller.addLine(
        LineOptions(
          geometry: geometry.points,
          lineColor: '#0B8A55',
          lineWidth: 4,
          lineOpacity: 0.96,
        ),
      );
      if (!mounted) return;
      _selectedAreaFill = fill;
      _selectedAreaLine = line;
    } catch (_) {
      if (mounted) {
        setState(() => _mapMessage =
            'تم تطبيق فلتر المنطقة، لكن تعذر رسم حدودها فوق الخريطة.');
      }
    }
  }

  void _clearSelectedArea() {
    unawaited(_removeAreaAnnotations());
    setState(() {
      _selectedAreaBounds = null;
      _selectedAreaGeometry = null;
      _selected = null;
      _lastMarkerSignature = '';
      _mapMessage = null;
    });
  }

  void _openAddProperty() {
    context.push('/add-property');
  }

  @override
  Widget build(BuildContext context) {
    final bounds = _selectedAreaBounds;
    final query = NearbyQuery(
      center: _center,
      radiusKm: _defaultRadiusKm,
      purpose: _filterPurpose,
      type: _filterType,
      minPrice: _filterMinPrice,
      maxPrice: _filterMaxPrice,
      minBedrooms: _filterMinBedrooms,
      minBathrooms: _filterMinBathrooms,
      minArea: _filterMinArea,
      maxArea: _filterMaxArea,
      search: _searchText,
      south: bounds?.southwest.latitude,
      west: bounds?.southwest.longitude,
      north: bounds?.northeast.latitude,
      east: bounds?.northeast.longitude,
    );
    final rawProperties = ref.watch(nearbyPropertiesProvider(query));
    final properties = rawProperties.whenData(_filterToSelectedArea);

    properties.when(
      data: (items) => _queueMarkerSync(_selectingArea ? const [] : items),
      loading: () {},
      error: (_, __) {},
    );

    if (_listMode) {
      return _buildListMode(properties, query);
    }

    final apiError = properties.asError?.error;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: _buildMap()),
            if (!_selectingArea) _buildTopFilterPanel(properties),
            if (!_selectingArea) _buildMapControls(),
            if (apiError != null)
              PositionedDirectional(
                start: 12,
                end: 12,
                bottom: 78,
                child: _ApiFailureBanner(
                  message: friendlyApiError(apiError),
                  onRetry: () =>
                      ref.invalidate(nearbyPropertiesProvider(query)),
                ),
              ),
            if (_selectedAreaBounds != null && !_selectingArea)
              _buildAreaChip(),
            if (_selectingArea) _buildAreaSelectionOverlay(),
            if (!_selectingArea) _buildMapBottomBar(properties),
            if (!_selectingArea && _selected != null)
              _buildSelectedPreview(_selected!),
            if (_mapMessage != null && !_selectingArea)
              PositionedDirectional(
                start: 14,
                end: 14,
                bottom: 82,
                child: _MessageCard(text: _mapMessage!),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    return MapLibreMap(
      styleString: _openFreeMapStyle,
      initialCameraPosition: CameraPosition(target: _center, zoom: 13.5),
      onMapCreated: _onMapCreated,
      onStyleLoadedCallback: _onStyleLoaded,
      onCameraIdle: _commitCameraCenter,
      trackCameraPosition: true,
      myLocationEnabled: _userLocation != null,
      myLocationTrackingMode: MyLocationTrackingMode.none,
      minMaxZoomPreference: const MinMaxZoomPreference(3, 19),
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      scrollGesturesEnabled: !_selectingArea,
      zoomGesturesEnabled: !_selectingArea,
      doubleClickZoomEnabled: !_selectingArea,
    );
  }

  Widget _buildTopFilterPanel(AsyncValue<List<PropertyMarker>> properties) {
    return PositionedDirectional(
      top: MediaQuery.paddingOf(context).top + 8,
      start: 10,
      end: 10,
      child: _MapQuickFilterPanel(
        purpose: _filterPurpose,
        type: _filterType,
        filterCount: _filterCount,
        searchText: _searchText,
        onPurpose: _setQuickPurpose,
        onType: _setQuickType,
        onSearch: () {
          final items = properties.asData?.value ?? const <PropertyMarker>[];
          _showSearchSheet(items);
        },
        onMore: _showFilters,
      ),
    );
  }

  Widget _buildMapControls() {
    return PositionedDirectional(
      end: 12,
      bottom: 86,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Material(
            elevation: 5,
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              onTap: _beginAreaSelection,
              borderRadius: BorderRadius.circular(18),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.gesture_rounded, color: AppTheme.brand),
                    SizedBox(width: 7),
                    Text(
                      'رسم منطقة',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _MapActionButton(
            tooltip: 'موقعي',
            icon: Icons.my_location,
            onPressed: _userLocation == null ? null : _moveToMyLocation,
          ),
        ],
      ),
    );
  }

  Widget _buildAreaChip() {
    return PositionedDirectional(
      top: MediaQuery.paddingOf(context).top + 154,
      start: 14,
      child: Material(
        elevation: 3,
        borderRadius: BorderRadius.circular(14),
        color: Colors.white,
        child: InputChip(
          avatar: const Icon(Icons.gesture_rounded, size: 18),
          label: const Text('منطقة مرسومة'),
          deleteIcon: const Icon(Icons.close_rounded, size: 18),
          onDeleted: _clearSelectedArea,
        ),
      ),
    );
  }

  Widget _buildAreaSelectionOverlay() {
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: _startAreaStroke,
              onPanUpdate: _updateAreaStroke,
              onPanEnd: _finishAreaStroke,
              child: CustomPaint(
                painter: _AreaStrokePainter(points: _areaDraftPoints),
              ),
            ),
          ),
          PositionedDirectional(
            top: MediaQuery.paddingOf(context).top + 18,
            start: 18,
            end: 18,
            child: IgnorePointer(
              child: Card(
                elevation: 5,
                color: Colors.white.withValues(alpha: 0.96),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.draw_rounded, color: AppTheme.brand),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'ارسم بإصبعك حدود المنطقة المطلوبة مثل القلم. عند رفع إصبعك سيتم عرض العقارات داخل الرسم فقط.',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          PositionedDirectional(
            start: 18,
            end: 18,
            bottom: 20,
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _cancelAreaSelection,
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('إلغاء'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.brand.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.touch_app_rounded, color: Colors.white),
                          SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'اسحب للرسم • ارفع إصبعك للاعتماد',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapBottomBar(AsyncValue<List<PropertyMarker>> properties) {
    return PositionedDirectional(
      start: 12,
      end: 12,
      bottom: 10,
      child: _MapListSwitcherBar(
        countText: properties.when(
          data: (items) => '${items.length} إعلان',
          loading: () => 'جاري التحميل…',
          error: (_, __) => 'تعذر الاتصال',
        ),
        mapMode: true,
        onSwitch: () => setState(() => _listMode = true),
        onAdd: _openAddProperty,
      ),
    );
  }

  Widget _buildSelectedPreview(PropertyMarker property) {
    return PositionedDirectional(
      start: 12,
      end: 12,
      bottom: 78,
      child: _MapSelectionCard(
        property: property,
        onDetails: () => _openDetails(property),
        onClose: () {
          setState(() {
            _selected = null;
            _lastMarkerSignature = '';
          });
        },
      ),
    );
  }

  Widget _buildListMode(
    AsyncValue<List<PropertyMarker>> properties,
    NearbyQuery query,
  ) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('قائمة العقارات'),
          actions: [
            IconButton.filledTonal(
              tooltip: 'بحث وتصفية',
              onPressed: () {
                final items =
                    properties.asData?.value ?? const <PropertyMarker>[];
                _showSearchSheet(items);
              },
              icon: const Icon(Icons.search),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              child: Row(
                children: [
                  Expanded(
                    child: SegmentedButton<int>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 0, label: Text('الأحدث')),
                        ButtonSegment(value: 1, label: Text('السعر')),
                        ButtonSegment(value: 2, label: Text('الأقرب')),
                      ],
                      selected: {_sortMode},
                      onSelectionChanged: (value) {
                        setState(() => _sortMode = value.first);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  _FilterCountButton(
                      count: _filterCount, onPressed: _showFilters),
                ],
              ),
            ),
            if (_searchText.isNotEmpty || _selectedAreaBounds != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    if (_searchText.isNotEmpty)
                      InputChip(
                        avatar: const Icon(Icons.search, size: 18),
                        label: Text(_searchText),
                        onDeleted: () {
                          _searchController.clear();
                          setState(() => _searchText = '');
                        },
                      ),
                    if (_selectedAreaBounds != null)
                      InputChip(
                        avatar: const Icon(Icons.crop_free, size: 18),
                        label: const Text('منطقة محددة'),
                        onDeleted: _clearSelectedArea,
                      ),
                  ],
                ),
              ),
            Expanded(child: _buildListContent(properties, query)),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: _MapListSwitcherBar(
              countText: properties.when(
                data: (items) => '${items.length} إعلان',
                loading: () => 'جاري التحميل…',
                error: (_, __) => 'تعذر الاتصال',
              ),
              mapMode: false,
              onSwitch: () => setState(() => _listMode = false),
              onAdd: _openAddProperty,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildListContent(
    AsyncValue<List<PropertyMarker>> properties,
    NearbyQuery query,
  ) {
    return properties.when(
      loading: () => ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 18),
        itemCount: 4,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, __) => const _LoadingPropertyCard(),
      ),
      error: (error, _) => _ResultsState(
        icon: Icons.cloud_off_outlined,
        title: 'تعذر تحميل العقارات',
        message: friendlyApiError(error),
        buttonLabel: 'إعادة المحاولة',
        onPressed: () => ref.invalidate(nearbyPropertiesProvider(query)),
      ),
      data: (items) {
        if (items.isEmpty) {
          return _ResultsState(
            icon: Icons.search_off_outlined,
            title: 'لا توجد نتائج مطابقة',
            message: 'جرّب تغيير المنطقة أو البحث أو إزالة بعض الفلاتر.',
            buttonLabel: _filterCount > 0 ? 'مسح الفلاتر' : null,
            onPressed: _filterCount > 0 ? _resetFilters : null,
          );
        }

        final sorted = List<PropertyMarker>.of(items);
        if (_sortMode == 1) {
          sorted.sort((a, b) => a.price.compareTo(b.price));
        } else if (_sortMode == 2) {
          sorted.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 18),
          itemCount: sorted.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final property = sorted[index];
            return _PropertyResultCard(
              property: property,
              selected: property.id == _selected?.id,
              onMap: () => _focusProperty(property),
              onDetails: () => _openDetails(property),
            );
          },
        );
      },
    );
  }
}

class _MapQuickFilterPanel extends StatelessWidget {
  const _MapQuickFilterPanel({
    required this.purpose,
    required this.type,
    required this.filterCount,
    required this.searchText,
    required this.onPurpose,
    required this.onType,
    required this.onSearch,
    required this.onMore,
  });

  final String? purpose;
  final String? type;
  final int filterCount;
  final String searchText;
  final ValueChanged<String?> onPurpose;
  final ValueChanged<String?> onType;
  final VoidCallback onSearch;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(22),
      color: Colors.white.withValues(alpha: 0.97),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: _PurposeButton(
                    label: 'للإيجار',
                    icon: Icons.key_outlined,
                    selected: purpose == 'rent',
                    onTap: () => onPurpose('rent'),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: _PurposeButton(
                    label: 'للبيع',
                    icon: Icons.sell_outlined,
                    selected: purpose == 'sale',
                    onTap: () => onPurpose('sale'),
                  ),
                ),
                const SizedBox(width: 7),
                FilledButton.icon(
                  onPressed: onSearch,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  icon: const Icon(Icons.search),
                  label: Text(searchText.isEmpty ? 'بحث' : 'بحث ✓'),
                ),
              ],
            ),
            const SizedBox(height: 9),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _TypeChip(
                      label: 'الكل',
                      selected: type == null,
                      onTap: () => onType(null)),
                  _TypeChip(
                      label: 'شقة',
                      selected: type == 'apartment',
                      onTap: () => onType('apartment')),
                  _TypeChip(
                      label: 'فيلا',
                      selected: type == 'villa',
                      onTap: () => onType('villa')),
                  _TypeChip(
                      label: 'منزل',
                      selected: type == 'house',
                      onTap: () => onType('house')),
                  _TypeChip(
                      label: 'أرض',
                      selected: type == 'land',
                      onTap: () => onType('land')),
                  _TypeChip(
                      label: 'محل',
                      selected: type == 'shop',
                      onTap: () => onType('shop')),
                  _TypeChip(
                      label: 'مكتب',
                      selected: type == 'office',
                      onTap: () => onType('office')),
                  const SizedBox(width: 4),
                  OutlinedButton.icon(
                    onPressed: onMore,
                    icon: const Icon(Icons.tune, size: 17),
                    label: Text(
                        filterCount == 0 ? 'المزيد' : 'المزيد ($filterCount)'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PurposeButton extends StatelessWidget {
  const _PurposeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTheme.brandSoft : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppTheme.brand : AppTheme.outlineSoft,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 19,
                color: selected ? AppTheme.brandStrong : AppTheme.textStrong,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color:
                        selected ? AppTheme.brandStrong : AppTheme.textStrong,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: selected,
        checkmarkColor: AppTheme.brandStrong,
        backgroundColor: Colors.white,
        selectedColor: AppTheme.brandSoft,
        side: BorderSide(
          color: selected ? AppTheme.brand : AppTheme.outlineSoft,
          width: selected ? 1.5 : 1.1,
        ),
        labelStyle: TextStyle(
          color: selected ? AppTheme.brandStrong : AppTheme.textStrong,
          fontWeight: FontWeight.w900,
        ),
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class _MapListSwitcherBar extends StatelessWidget {
  const _MapListSwitcherBar({
    required this.countText,
    required this.mapMode,
    required this.onSwitch,
    required this.onAdd,
  });

  final String countText;
  final bool mapMode;
  final VoidCallback onSwitch;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 58,
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onSwitch,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(mapMode
                        ? Icons.view_list_outlined
                        : Icons.map_outlined),
                    const SizedBox(width: 7),
                    Text(
                      mapMode ? 'قائمة' : 'خريطة',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ),
            const VerticalDivider(),
            Expanded(
              child: Center(
                child: Text(
                  countText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textStrong,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const VerticalDivider(),
            Expanded(
              child: InkWell(
                onTap: onAdd,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_circle, color: AppTheme.brandStrong),
                    SizedBox(width: 7),
                    Text(
                      'إضافة',
                      style: TextStyle(
                        color: AppTheme.brandStrong,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AreaStrokePainter extends CustomPainter {
  const _AreaStrokePainter({required this.points});

  final List<Offset> points;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final shadow = Paint()
      ..color = const Color(0x66000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final stroke = Paint()
      ..color = AppTheme.brand
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = AppTheme.brand.withValues(alpha: 0.10)
      ..style = PaintingStyle.fill;

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, shadow);
    canvas.drawPath(path, stroke);

    if (points.length >= 8) {
      final closed = Path()
        ..addPath(path, Offset.zero)
        ..close();
      canvas.drawPath(closed, fill);
    }
  }

  @override
  bool shouldRepaint(covariant _AreaStrokePainter oldDelegate) {
    if (identical(points, oldDelegate.points)) return false;
    if (points.length != oldDelegate.points.length) return true;
    if (points.isEmpty) return false;
    return points.last != oldDelegate.points.last;
  }
}

class _MapActionButton extends StatelessWidget {
  const _MapActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

class _FilterCountButton extends StatelessWidget {
  const _FilterCountButton({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.tune, size: 18),
      label: Text(count == 0 ? 'تصفية' : '$count'),
    );
  }
}

class _SearchSheet extends StatefulWidget {
  const _SearchSheet({required this.initialValue, required this.suggestions});

  final String initialValue;
  final List<String> suggestions;

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim().toLowerCase();
    final suggestions = widget.suggestions
        .where((value) => query.isEmpty || value.toLowerCase().contains(query))
        .take(6)
        .toList(growable: false);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        12,
        18,
        MediaQuery.viewInsetsOf(context).bottom + 18,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: AppTheme.outlineSoft,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'ابحث عن عقارك',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: 'اسم منطقة، شارع أو عقار',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: suggestions.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.location_on_outlined),
                  title: Text(
                    suggestions[index],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.of(context).pop(suggestions[index]),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(''),
                  child: const Text('مسح البحث'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(_controller.text),
                  icon: const Icon(Icons.search),
                  label: const Text('عرض النتائج'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PropertyResultCard extends StatelessWidget {
  const _PropertyResultCard({
    required this.property,
    required this.selected,
    required this.onMap,
    required this.onDetails,
  });

  final PropertyMarker property;
  final bool selected;
  final VoidCallback onMap;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final imageUrl = property.mainImage;

    return SizedBox(
      height: 164,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onDetails,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? AppTheme.brand : AppTheme.outlineSoft,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 132,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      imageUrl == null
                          ? const _PropertyImageFallback()
                          : Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const _PropertyImageFallback(),
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return const _PropertyImageFallback(
                                    showLoader: true);
                              },
                            ),
                      PositionedDirectional(
                        top: 0,
                        start: 10,
                        child: Container(
                          width: 26,
                          height: 34,
                          decoration: const BoxDecoration(
                            color: AppTheme.warning,
                            borderRadius: BorderRadius.vertical(
                                bottom: Radius.circular(6)),
                          ),
                          child: const Icon(Icons.bookmark_border,
                              size: 18, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (property.purpose != null)
                              _MiniTag(label: _purposeLabel(property.purpose!)),
                            if (property.type != null) ...[
                              const SizedBox(width: 6),
                              _MiniTag(label: _typeLabel(property.type!)),
                            ],
                            const Spacer(),
                            IconButton(
                              tooltip: 'عرض على الخريطة',
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints.tightFor(
                                  width: 32, height: 32),
                              padding: EdgeInsets.zero,
                              onPressed: onMap,
                              icon: const Icon(Icons.location_on_outlined,
                                  size: 19),
                            ),
                          ],
                        ),
                        Text(
                          property.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_formatPrice(property.price)} ${_currencyLabel(property.currency)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: AppTheme.brandStrong,
                                    fontWeight: FontWeight.w900,
                                  ),
                        ),
                        const Spacer(),
                        _PropertyFacts(property: property),
                        const SizedBox(height: 6),
                        Text(
                          property.address ??
                              '${property.distanceKm.toStringAsFixed(1)} كم من مركز البحث',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppTheme.textMuted,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PropertyFacts extends StatelessWidget {
  const _PropertyFacts({required this.property});

  final PropertyMarker property;

  @override
  Widget build(BuildContext context) {
    final facts = <Widget>[];
    if (property.areaM2 != null) {
      facts.add(_Fact(icon: Icons.square_foot, text: '${property.areaM2} م²'));
    }
    if (property.bedrooms != null) {
      facts.add(_Fact(icon: Icons.bed_outlined, text: '${property.bedrooms}'));
    }
    if (property.bathrooms != null) {
      facts.add(
          _Fact(icon: Icons.bathtub_outlined, text: '${property.bathrooms}'));
    }
    if (facts.isEmpty) return const SizedBox(height: 20);
    return Wrap(spacing: 10, runSpacing: 4, children: facts);
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppTheme.textMuted),
        const SizedBox(width: 4),
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.textMuted,
              ),
        ),
      ],
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.brandSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppTheme.brandStrong,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _MapSelectionCard extends StatelessWidget {
  const _MapSelectionCard({
    required this.property,
    required this.onDetails,
    required this.onClose,
  });

  final PropertyMarker property;
  final VoidCallback onDetails;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 8,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onDetails,
        child: SizedBox(
          height: 112,
          child: Row(
            children: [
              SizedBox(
                width: 108,
                height: double.infinity,
                child: property.mainImage == null
                    ? const _PropertyImageFallback()
                    : Image.network(
                        property.mainImage!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const _PropertyImageFallback(),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      property.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${_formatPrice(property.price)} ${_currencyLabel(property.currency)}',
                      style: const TextStyle(
                        color: AppTheme.brandStrong,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      property.address ?? 'اضغط لعرض التفاصيل',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'إغلاق',
                onPressed: onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PropertyImageFallback extends StatelessWidget {
  const _PropertyImageFallback({this.showLoader = false});

  final bool showLoader;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppTheme.brandSoft,
      child: Center(
        child: showLoader
            ? const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
            : const Icon(
                Icons.home_work_outlined,
                color: AppTheme.brandStrong,
                size: 38,
              ),
      ),
    );
  }
}

class _LoadingPropertyCard extends StatelessWidget {
  const _LoadingPropertyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 164,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.outlineSoft),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 118,
            decoration: BoxDecoration(
              color: AppTheme.brandSoft,
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                _LoadingLine(widthFactor: 0.8),
                SizedBox(height: 10),
                _LoadingLine(widthFactor: 0.55),
                SizedBox(height: 16),
                _LoadingLine(widthFactor: 0.68),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingLine extends StatelessWidget {
  const _LoadingLine({required this.widthFactor});

  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        height: 12,
        decoration: BoxDecoration(
          color: const Color(0xFFEAF1F0),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class _ResultsState extends StatelessWidget {
  const _ResultsState({
    required this.icon,
    required this.title,
    required this.message,
    this.buttonLabel,
    this.onPressed,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? buttonLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppTheme.textMuted),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center),
            if (buttonLabel != null && onPressed != null) ...[
              const SizedBox(height: 14),
              FilledButton.tonal(
                onPressed: onPressed,
                child: Text(buttonLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilterResult {
  const _FilterResult({
    this.purpose,
    this.type,
    this.minPrice,
    this.maxPrice,
    this.minBedrooms,
    this.minBathrooms,
    this.minArea,
    this.maxArea,
  });

  final String? purpose;
  final String? type;
  final double? minPrice;
  final double? maxPrice;
  final int? minBedrooms;
  final int? minBathrooms;
  final double? minArea;
  final double? maxArea;
}

class _PropertyFilterSheet extends StatefulWidget {
  const _PropertyFilterSheet({
    this.initialPurpose,
    this.initialType,
    this.initialMinPrice,
    this.initialMaxPrice,
    this.initialMinBedrooms,
    this.initialMinBathrooms,
    this.initialMinArea,
    this.initialMaxArea,
  });

  final String? initialPurpose;
  final String? initialType;
  final double? initialMinPrice;
  final double? initialMaxPrice;
  final int? initialMinBedrooms;
  final int? initialMinBathrooms;
  final double? initialMinArea;
  final double? initialMaxArea;

  @override
  State<_PropertyFilterSheet> createState() => _PropertyFilterSheetState();
}

class _PropertyFilterSheetState extends State<_PropertyFilterSheet> {
  late String? _purpose;
  late String? _type;
  late int? _minBedrooms;
  late int? _minBathrooms;
  late final TextEditingController _minPriceController;
  late final TextEditingController _maxPriceController;
  late final TextEditingController _minAreaController;
  late final TextEditingController _maxAreaController;

  String? _error;
  bool _submitting = false;
  bool _showMore = false;

  bool get _showRoomFilters =>
      _type == 'apartment' || _type == 'house' || _type == 'villa';

  @override
  void initState() {
    super.initState();
    _purpose = widget.initialPurpose;
    _type = widget.initialType;
    _minBedrooms = widget.initialMinBedrooms;
    _minBathrooms = widget.initialMinBathrooms;
    _minPriceController = TextEditingController(
      text: widget.initialMinPrice?.toStringAsFixed(0) ?? '',
    );
    _maxPriceController = TextEditingController(
      text: widget.initialMaxPrice?.toStringAsFixed(0) ?? '',
    );
    _minAreaController = TextEditingController(
      text: widget.initialMinArea?.toStringAsFixed(0) ?? '',
    );
    _maxAreaController = TextEditingController(
      text: widget.initialMaxArea?.toStringAsFixed(0) ?? '',
    );
    _showMore = widget.initialMinPrice != null ||
        widget.initialMaxPrice != null ||
        widget.initialMinBedrooms != null ||
        widget.initialMinBathrooms != null ||
        widget.initialMinArea != null ||
        widget.initialMaxArea != null;
  }

  @override
  void dispose() {
    _minPriceController.dispose();
    _maxPriceController.dispose();
    _minAreaController.dispose();
    _maxAreaController.dispose();
    super.dispose();
  }

  void _setType(String? value) {
    setState(() {
      _type = value;
      if (!_showRoomFilters) {
        _minBedrooms = null;
        _minBathrooms = null;
      }
    });
  }

  void _reset() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _purpose = null;
      _type = null;
      _minBedrooms = null;
      _minBathrooms = null;
      _minPriceController.clear();
      _maxPriceController.clear();
      _minAreaController.clear();
      _maxAreaController.clear();
      _error = null;
      _showMore = false;
    });
  }

  double? _parseOptionalDouble(TextEditingController controller) {
    final value = controller.text.trim();
    if (value.isEmpty) return null;
    return double.tryParse(value);
  }

  void _apply() {
    if (_submitting) return;
    FocusManager.instance.primaryFocus?.unfocus();

    final minPriceText = _minPriceController.text.trim();
    final maxPriceText = _maxPriceController.text.trim();
    final minAreaText = _minAreaController.text.trim();
    final maxAreaText = _maxAreaController.text.trim();

    final minPrice = _parseOptionalDouble(_minPriceController);
    final maxPrice = _parseOptionalDouble(_maxPriceController);
    final minArea = _parseOptionalDouble(_minAreaController);
    final maxArea = _parseOptionalDouble(_maxAreaController);

    final invalidNumber = (minPriceText.isNotEmpty && minPrice == null) ||
        (maxPriceText.isNotEmpty && maxPrice == null) ||
        (minAreaText.isNotEmpty && minArea == null) ||
        (maxAreaText.isNotEmpty && maxArea == null);
    if (invalidNumber) {
      setState(() => _error = 'تأكد من كتابة الأرقام بشكل صحيح.');
      return;
    }

    final hasNegative = (minPrice != null && minPrice < 0) ||
        (maxPrice != null && maxPrice < 0) ||
        (minArea != null && minArea < 0) ||
        (maxArea != null && maxArea < 0);
    if (hasNegative) {
      setState(() => _error = 'القيم لا يمكن أن تكون سالبة.');
      return;
    }

    if (minPrice != null && maxPrice != null && maxPrice < minPrice) {
      setState(() => _error = 'أعلى سعر يجب أن يكون أكبر من أقل سعر.');
      return;
    }

    if (minArea != null && maxArea != null && maxArea < minArea) {
      setState(() => _error = 'أكبر مساحة يجب أن تكون أكبر من أقل مساحة.');
      return;
    }

    setState(() {
      _error = null;
      _submitting = true;
    });

    Navigator.of(context).pop(
      _FilterResult(
        purpose: _purpose,
        type: _type,
        minPrice: minPrice,
        maxPrice: maxPrice,
        minBedrooms: _showRoomFilters ? _minBedrooms : null,
        minBathrooms: _showRoomFilters ? _minBathrooms : null,
        minArea: minArea,
        maxArea: maxArea,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.92),
      decoration: const BoxDecoration(
        color: AppTheme.page,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: AppTheme.outlineSoft,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'تصفية العقارات',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'الفلاتر الأساسية أمامك، واضغط المزيد للخيارات التفصيلية.',
                        style: TextStyle(color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _submitting ? null : _reset,
                  child: const Text('مسح'),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                MediaQuery.viewInsetsOf(context).bottom + 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _FilterSectionTitle('الغرض'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _choice('الكل', _purpose == null,
                          () => setState(() => _purpose = null)),
                      _choice('للبيع', _purpose == 'sale',
                          () => setState(() => _purpose = 'sale')),
                      _choice('للإيجار', _purpose == 'rent',
                          () => setState(() => _purpose = 'rent')),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const _FilterSectionTitle('نوع العقار'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _choice('الكل', _type == null, () => _setType(null)),
                      _choice('شقة', _type == 'apartment',
                          () => _setType('apartment')),
                      _choice(
                          'منزل', _type == 'house', () => _setType('house')),
                      _choice(
                          'فيلا', _type == 'villa', () => _setType('villa')),
                      _choice('أرض', _type == 'land', () => _setType('land')),
                      _choice('محل', _type == 'shop', () => _setType('shop')),
                      _choice(
                          'مكتب', _type == 'office', () => _setType('office')),
                      _choice('مزرعة', _type == 'farm', () => _setType('farm')),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => setState(() => _showMore = !_showMore),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            const Icon(Icons.tune, color: AppTheme.accent),
                            const SizedBox(width: 9),
                            const Expanded(
                              child: Text(
                                'المزيد من الفلاتر',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                            Icon(_showMore
                                ? Icons.expand_less
                                : Icons.expand_more),
                          ],
                        ),
                      ),
                    ),
                  ),
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 180),
                    crossFadeState: _showMore
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    firstChild: const SizedBox.shrink(),
                    secondChild: Padding(
                      padding: const EdgeInsets.only(top: 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_showRoomFilters) ...[
                            const _FilterSectionTitle('غرف النوم'),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final number in [1, 2, 3, 4, 5])
                                  _numberChoice(
                                    label: '$number+',
                                    value: _minBedrooms,
                                    number: number,
                                    onChanged: (value) =>
                                        setState(() => _minBedrooms = value),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const _FilterSectionTitle('الحمامات'),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final number in [1, 2, 3, 4])
                                  _numberChoice(
                                    label: '$number+',
                                    value: _minBathrooms,
                                    number: number,
                                    onChanged: (value) =>
                                        setState(() => _minBathrooms = value),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 18),
                          ],
                          const _FilterSectionTitle('المساحة (م²)'),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _minAreaController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration:
                                      const InputDecoration(labelText: 'من'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: _maxAreaController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration:
                                      const InputDecoration(labelText: 'إلى'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          const _FilterSectionTitle('السعر'),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _minPriceController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: const InputDecoration(
                                      labelText: 'أقل سعر'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: _maxPriceController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: const InputDecoration(
                                      labelText: 'أعلى سعر'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    _MessageCard(text: _error!, error: true),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _submitting ? null : _apply,
                icon: const Icon(Icons.search),
                label: const Text('عرض العقارات'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _choice(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: _submitting ? null : (_) => onTap(),
    );
  }

  Widget _numberChoice({
    required String label,
    required int? value,
    required int number,
    required ValueChanged<int?> onChanged,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: value == number,
      onSelected: _submitting
          ? null
          : (_) => onChanged(value == number ? null : number),
    );
  }
}

class _FilterSectionTitle extends StatelessWidget {
  const _FilterSectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
          ),
    );
  }
}

class _ApiFailureBanner extends StatelessWidget {
  const _ApiFailureBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFF7F4),
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE5A497), width: 1.2),
        ),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_outlined, color: Color(0xFF9B3D2B)),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF6D2D21),
                  fontWeight: FontWeight.w800,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('إعادة'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.text, this.error = false});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: error ? const Color(0xFFFFECEC) : Colors.white,
      elevation: error ? 0 : 4,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              error ? Icons.error_outline : Icons.info_outline,
              color: error ? Colors.red.shade700 : AppTheme.accent,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

String _purposeLabel(String value) {
  switch (value) {
    case 'sale':
      return 'للبيع';
    case 'rent':
      return 'للإيجار';
    default:
      return value;
  }
}

String _typeLabel(String value) {
  switch (value) {
    case 'apartment':
      return 'شقة';
    case 'house':
      return 'منزل';
    case 'villa':
      return 'فيلا';
    case 'land':
      return 'أرض';
    case 'shop':
      return 'محل';
    case 'office':
      return 'مكتب';
    case 'farm':
      return 'مزرعة';
    default:
      return value;
  }
}

String _currencyLabel(String value) {
  switch (value.toUpperCase()) {
    case 'YER':
      return 'ريال';
    case 'SAR':
      return 'ريال سعودي';
    case 'USD':
      return 'دولار';
    default:
      return value;
  }
}

String _formatPrice(double value) {
  if (value >= 1000000000) {
    final scaled = value / 1000000000;
    return '${scaled.toStringAsFixed(scaled >= 10 ? 0 : 1)} مليار';
  }
  if (value >= 1000000) {
    final scaled = value / 1000000;
    return '${scaled.toStringAsFixed(scaled >= 10 ? 0 : 1)} مليون';
  }
  if (value >= 1000) {
    final scaled = value / 1000;
    return '${scaled.toStringAsFixed(scaled >= 10 ? 0 : 1)} ألف';
  }
  return value.toStringAsFixed(0);
}

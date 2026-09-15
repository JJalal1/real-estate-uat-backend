import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/design/app_design.dart';
import 'discovery_filter_panel.dart';
import 'discovery_map_dock.dart';
import 'discovery_search_sheet.dart';
import 'discovery_filter_sheet.dart';
import 'discovery_results_layout.dart';
import '../domain/map_area_geometry.dart';
import '../domain/map_screen_coordinate_space.dart';
import '../data/property_discovery_history_store.dart';
import '../../account/data/auth_controller.dart';
import '../../account/data/auth_return_intent.dart';
import '../../properties/data/favorites_repository.dart';
import '../../properties/data/property_repository.dart';
import '../../properties/domain/property_marker.dart';
import '../../properties/presentation/saved_search_builder_screen.dart';

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
  bool _changingFavorite = false;
  int _sortMode = 0;

  final TextEditingController _searchController = TextEditingController();
  final PropertyDiscoveryHistoryStore _historyStore = const PropertyDiscoveryHistoryStore();
  String _searchText = '';
  List<String> _recentSearches = const <String>[];

  bool _styleLoaded = false;
  String? _mapMessage;
  String _lastMarkerSignature = '';
  int _annotationGeneration = 0;
  List<PropertyMarker> _latestMarkerItems = const <PropertyMarker>[];
  final Set<String> _registeredPriceImages = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_restoreDiscoveryHistory());
    _loadCurrentLocation();
  }

  @override
  void dispose() {
    _styleLoadTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _restoreDiscoveryHistory() async {
    final history = await _historyStore.load();
    if (!mounted) return;
    final filters = history.lastFilters;
    final search = filters['search']?.toString().trim() ?? '';
    setState(() {
      _recentSearches = history.recentSearches;
      _filterPurpose = _historyString(filters['purpose']);
      _filterType = _historyString(filters['type']);
      _filterMinPrice = _historyDouble(filters['min_price']);
      _filterMaxPrice = _historyDouble(filters['max_price']);
      _filterMinBedrooms = _historyInt(filters['min_bedrooms']);
      _filterMinBathrooms = _historyInt(filters['min_bathrooms']);
      _filterMinArea = _historyDouble(filters['min_area_m2']);
      _filterMaxArea = _historyDouble(filters['max_area_m2']);
      _searchText = search;
      _searchController.text = search;
    });
  }

  String? _historyString(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  double? _historyDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  int? _historyInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  Map<String, dynamic> _discoveryHistorySnapshot() => <String, dynamic>{
        if (_filterPurpose != null) 'purpose': _filterPurpose,
        if (_filterType != null) 'type': _filterType,
        if (_filterMinPrice != null) 'min_price': _filterMinPrice,
        if (_filterMaxPrice != null) 'max_price': _filterMaxPrice,
        if (_filterMinBedrooms != null) 'min_bedrooms': _filterMinBedrooms,
        if (_filterMinBathrooms != null) 'min_bathrooms': _filterMinBathrooms,
        if (_filterMinArea != null) 'min_area_m2': _filterMinArea,
        if (_filterMaxArea != null) 'max_area_m2': _filterMaxArea,
        if (_searchText.trim().isNotEmpty) 'search': _searchText.trim(),
      };

  void _persistDiscoveryHistory() {
    unawaited(
      _historyStore.record(
        query: _searchText,
        filters: _discoveryHistorySnapshot(),
      ),
    );
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

  Future<void> _toggleFavorite(
    int propertyId, {
    required bool currentlyFavorite,
  }) async {
    final user = ref.read(authControllerProvider).asData?.value;
    if (user == null) {
      ref.read(pendingFavoriteAfterAuthProvider.notifier).state = propertyId;
      setAuthReturnLocation(ref, '/properties/$propertyId');
      await context.push('/auth');
      if (!mounted) return;
      if (ref.read(authControllerProvider).asData?.value == null) {
        if (ref.read(pendingFavoriteAfterAuthProvider) == propertyId) {
          ref.read(pendingFavoriteAfterAuthProvider.notifier).state = null;
        }
        takeAuthReturnLocation(ref);
      }
      return;
    }

    if (!user.isActive) {
      ref.read(pendingFavoriteAfterAuthProvider.notifier).state = propertyId;
      setAuthReturnLocation(ref, '/properties/$propertyId');
      await context.push('/verify-phone');
      return;
    }
    if (_changingFavorite) return;

    setState(() => _changingFavorite = true);
    try {
      final repository = ref.read(favoritesRepositoryProvider);
      if (currentlyFavorite) {
        await repository.remove(propertyId);
      } else {
        await repository.add(propertyId);
      }
      ref.read(favoriteDataRevisionProvider.notifier).state++;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            currentlyFavorite
                ? 'تمت إزالة العقار من المفضلة.'
                : 'تم حفظ العقار في المفضلة.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyApiError(error))),
      );
    } finally {
      if (mounted) setState(() => _changingFavorite = false);
    }
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
    _persistDiscoveryHistory();
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
    _persistDiscoveryHistory();
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
    _persistDiscoveryHistory();
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
    final result = await showModalBottomSheet<DiscoveryFilterResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => DiscoveryFilterSheet(
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
    _persistDiscoveryHistory();
  }

  Future<void> _showSearchSheet(List<PropertyMarker> items) async {
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => DiscoverySearchSheet(
        initialValue: _searchController.text,
        suggestions: _searchSuggestions(items),
        recentSearches: _recentSearches,
      ),
    );
    if (!mounted || value == null) return;

    final normalized = value.trim();
    _searchController.text = normalized;
    setState(() {
      _searchText = normalized;
      if (normalized.isNotEmpty) {
        _recentSearches = <String>[
          normalized,
          ..._recentSearches.where(
            (value) => value.toLowerCase() != normalized.toLowerCase(),
          ),
        ].take(5).toList(growable: false);
      }
      _selected = null;
      _lastMarkerSignature = '';
    });
    _persistDiscoveryHistory();
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


  Map<String, dynamic> _currentSavedSearchFilters() {
    final bounds = _selectedAreaBounds;
    final filters = <String, dynamic>{
      if (_filterPurpose != null) 'purpose': _filterPurpose,
      if (_filterType != null) 'type': _filterType,
      if (_filterMinPrice != null) 'min_price': _filterMinPrice,
      if (_filterMaxPrice != null) 'max_price': _filterMaxPrice,
      if (_filterMinBedrooms != null) 'min_bedrooms': _filterMinBedrooms,
      if (_filterMinBathrooms != null) 'min_bathrooms': _filterMinBathrooms,
      if (_filterMinArea != null) 'min_area_m2': _filterMinArea,
      if (_filterMaxArea != null) 'max_area_m2': _filterMaxArea,
      if (_searchText.trim().isNotEmpty) 'search': _searchText.trim(),
    };
    if (bounds != null) {
      filters.addAll({
        'south': bounds.southwest.latitude,
        'west': bounds.southwest.longitude,
        'north': bounds.northeast.latitude,
        'east': bounds.northeast.longitude,
      });
    } else {
      filters.addAll({
        'latitude': _center.latitude,
        'longitude': _center.longitude,
        'radius_km': _defaultRadiusKm,
      });
    }
    return filters;
  }

  Future<void> _saveCurrentSearch() async {
    final user = ref.read(authControllerProvider).asData?.value;
    if (user == null) {
      setAuthReturnLocation(ref, '/');
      await context.push('/auth');
      if (!mounted || ref.read(authControllerProvider).asData?.value == null) {
        return;
      }
    }
    final currentUser = ref.read(authControllerProvider).asData?.value;
    if (currentUser == null) return;
    if (!currentUser.isActive) {
      setAuthReturnLocation(ref, '/');
      await context.push('/verify-phone');
      if (!mounted || ref.read(authControllerProvider).asData?.value?.isActive != true) {
        return;
      }
    }
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => SavedSearchBuilderScreen(
          initialFilters: _currentSavedSearchFilters(),
        ),
      ),
    );
    if (!mounted || saved != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم حفظ البحث وسيصلك تنبيه عند ظهور عقار مطابق.'),
      ),
    );
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
    final user = ref.watch(authControllerProvider).asData?.value;
    final favoriteIds = user == null
        ? const <int>{}
        : ref.watch(favoritePropertyIdsProvider).maybeWhen(
              data: (value) => value,
              orElse: () => const <int>{},
            );

    properties.when(
      data: (items) => _queueMarkerSync(_selectingArea ? const [] : items),
      loading: () {},
      error: (_, __) {},
    );

    if (_listMode) {
      return _buildListMode(properties, query, favoriteIds);
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
            if (_selectingArea) _buildAreaSelectionOverlay(),
            if (!_selectingArea)
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) => Align(
                    alignment: Alignment.bottomCenter,
                    child: SafeArea(
                      top: false,
                      minimum: const EdgeInsets.fromLTRB(
                        AppLayout.compactPageGutter, 0,
                        AppLayout.compactPageGutter, AppSpacing.s8,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: (constraints.maxHeight - MediaQuery.paddingOf(context).vertical) *
                              AppLayout.mapDockMaxHeightFraction,
                        ),
                        child: DiscoveryMapDock(
                          controls: _buildMapControls(),
                          error: apiError == null ? null : _ApiFailureBanner(
                            message: friendlyApiError(apiError),
                            onRetry: () => ref.invalidate(nearbyPropertiesProvider(query)),
                          ),
                          preview: _selected == null ? null : _buildSelectedPreview(
                            _selected!,
                            favorite: favoriteIds.contains(_selected!.id),
                          ),
                          message: _mapMessage == null ? null : _MessageCard(text: _mapMessage!),
                          modeBar: _buildMapBottomBar(properties),
                        ),
                      ),
                    ),
                  ),
                ),
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
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) => Align(
          alignment: Alignment.topCenter,
          child: SafeArea(
            bottom: false,
            minimum: const EdgeInsets.fromLTRB(
              AppLayout.compactPageGutter, AppSpacing.s8,
              AppLayout.compactPageGutter, 0,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: (constraints.maxHeight - MediaQuery.paddingOf(context).vertical) *
                    AppLayout.mapFilterMaxHeightFraction,
              ),
              child: SingleChildScrollView(
                primary: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DiscoveryFilterPanel(
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
                    if (_selectedAreaBounds != null) ...[
                      const SizedBox(height: AppSpacing.s8),
                      _buildAreaChip(),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMapControls() => AppSurface(
        padding: const EdgeInsetsDirectional.all(AppSpacing.s8),
        child: Wrap(
          alignment: WrapAlignment.start,
          spacing: AppSpacing.s8,
          runSpacing: AppSpacing.s8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AppButton(
              label: 'حفظ البحث',
              icon: Icons.notifications_active_outlined,
              style: AppButtonStyle.text,
              onPressed: _saveCurrentSearch,
            ),
            AppButton(
              label: 'رسم منطقة',
              icon: Icons.gesture_rounded,
              style: AppButtonStyle.text,
              onPressed: _beginAreaSelection,
            ),
            AppIconButton(
              tooltip: 'موقعي',
              icon: Icons.my_location,
              onPressed: _userLocation == null ? null : _moveToMyLocation,
            ),
          ],
        ),
      );

  Widget _buildAreaChip() {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Material(
        elevation: AppElevation.floating,
        borderRadius: BorderRadius.circular(AppRadii.control),
        color: Theme.of(context).colorScheme.surface,
        child: InputChip(
          avatar: const Icon(Icons.gesture_rounded),
          label: const Text('منطقة مرسومة'),
          deleteIcon: const Icon(Icons.close_rounded),
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
    return DiscoveryModeBar(
      countText: properties.when(
        data: (items) => '${items.length} نتيجة',
        loading: () => 'جاري التحميل…',
        error: (_, __) => 'تعذر الاتصال',
      ),
      mapMode: true,
      onSwitch: () => setState(() => _listMode = true),
      onAdd: _openAddProperty,
    );
  }

  Widget _buildSelectedPreview(
    PropertyMarker property, {
    required bool favorite,
  }) {
    return _MapSelectionCard(
      property: property,
      favorite: favorite,
      onFavorite: _changingFavorite
          ? null
          : () => _toggleFavorite(
                property.id,
                currentlyFavorite: favorite,
              ),
      onDetails: () => _openDetails(property),
      onClose: () {
        setState(() {
          _selected = null;
          _lastMarkerSignature = '';
        });
      },
    );
  }

  Widget _buildListMode(
    AsyncValue<List<PropertyMarker>> properties,
    NearbyQuery query,
    Set<int> favoriteIds,
  ) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('قائمة العقارات'),
          actions: [
            IconButton.filledTonal(
              tooltip: 'حفظ البحث الحالي',
              onPressed: _saveCurrentSearch,
              icon: const Icon(Icons.notifications_active_outlined),
            ),
            const SizedBox(width: 8),
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
        body: DiscoveryResultsLayout(
          header: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppLayout.compactPageGutter, AppSpacing.s8,
                  AppLayout.compactPageGutter, AppSpacing.s12,
                ),
                child: DiscoverySortBar(
                  sortMode: _sortMode,
                  filterCount: _filterCount,
                  onSort: (value) => setState(() => _sortMode = value),
                  onFilters: _showFilters,
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
                            _persistDiscoveryHistory();
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
            ],
          ),
          results: _buildListContent(properties, query, favoriteIds),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: DiscoveryModeBar(
              countText: properties.when(
                data: (items) => '${items.length} نتيجة',
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
    Set<int> favoriteIds,
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
        if (_sortMode == 0) {
          sorted.sort((a, b) => b.id.compareTo(a.id));
        } else if (_sortMode == 1) {
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
            final favorite = favoriteIds.contains(property.id);
            return _PropertyResultCard(
              property: property,
              selected: property.id == _selected?.id,
              favorite: favorite,
              onFavorite: _changingFavorite
                  ? null
                  : () => _toggleFavorite(
                        property.id,
                        currentlyFavorite: favorite,
                      ),
              onMap: () => _focusProperty(property),
              onDetails: () => _openDetails(property),
            );
          },
        );
      },
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

class _PropertyResultCard extends StatelessWidget {
  const _PropertyResultCard({
    required this.property,
    required this.selected,
    required this.favorite,
    required this.onFavorite,
    required this.onMap,
    required this.onDetails,
  });

  final PropertyMarker property;
  final bool selected;
  final bool favorite;
  final VoidCallback? onFavorite;
  final VoidCallback onMap;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    return AppPropertyCard(
      title: property.title,
      price: _formatPrice(property.price),
      currency: _currencyLabel(property.currency),
      imageUrl: property.mainImage,
      location: property.address ??
          '${property.distanceKm.toStringAsFixed(1)} كم من مركز البحث',
      purposeLabel: property.purpose == null ? null : _purposeLabel(property.purpose!),
      categoryLabel: property.type == null ? null : _typeLabel(property.type!),
      selected: selected,
      facts: [
        if (property.areaM2 != null)
          AppPropertyFact(icon: Icons.square_foot, label: '${property.areaM2} م²'),
        if (property.bedrooms != null)
          AppPropertyFact(icon: Icons.bed_outlined, label: '${property.bedrooms}'),
        if (property.bathrooms != null)
          AppPropertyFact(icon: Icons.bathtub_outlined, label: '${property.bathrooms}'),
      ],
      trailing: IconButton.filledTonal(
        tooltip: favorite ? 'إزالة من المفضلة' : 'حفظ في المفضلة',
        onPressed: onFavorite,
        icon: Icon(favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded),
      ),
      footer: AppButton(
        label: 'عرض على الخريطة',
        icon: Icons.location_on_outlined,
        style: AppButtonStyle.text,
        expand: true,
        onPressed: onMap,
      ),
      onTap: onDetails,
    );
  }
}

class _MapSelectionCard extends StatelessWidget {
  const _MapSelectionCard({
    required this.property,
    required this.favorite,
    required this.onFavorite,
    required this.onDetails,
    required this.onClose,
  });

  final PropertyMarker property;
  final bool favorite;
  final VoidCallback? onFavorite;
  final VoidCallback onDetails;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => DiscoveryPropertyPreview(
        title: property.title,
        price: _formatPrice(property.price),
        currency: _currencyLabel(property.currency),
        imageUrl: property.mainImage,
        location: property.address ?? 'اضغط لعرض التفاصيل',
        favorite: favorite,
        onFavorite: onFavorite,
        onDetails: onDetails,
        onClose: onClose,
      );
}

class _LoadingPropertyCard extends StatelessWidget {
  const _LoadingPropertyCard();

  @override
  Widget build(BuildContext context) => const AppPropertyCardSkeleton();
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
  Widget build(BuildContext context) => AppEmptyState(
        icon: icon,
        title: title,
        message: message,
        actionLabel: buttonLabel,
        onAction: onPressed,
      );
}

class _ApiFailureBanner extends StatelessWidget {
  const _ApiFailureBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => AppSurface(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppInlineMessage(message: message, tone: AppStatusTone.error, icon: Icons.cloud_off_outlined),
            const SizedBox(height: AppSpacing.s8),
            AppButton(label: 'إعادة', icon: Icons.refresh, onPressed: onRetry, style: AppButtonStyle.tonal),
          ],
        ),
      );
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => AppInlineMessage(
        message: text,
        tone: AppStatusTone.info,
        icon: Icons.info_outline,
      );
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

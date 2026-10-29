import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';

import 'package:flutter/material.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../../../core/widgets/ebroker_property_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/ebroker_design.dart';
import '../domain/map_area_geometry.dart';
import '../domain/map_screen_coordinate_space.dart';
import '../domain/property_marker_cluster.dart';
import '../data/property_discovery_history_store.dart';
import '../../account/data/auth_controller.dart';
import '../../account/data/auth_return_intent.dart';
import '../../properties/data/favorites_repository.dart';
import '../../properties/data/property_repository.dart';
import '../../properties/domain/property_marker.dart';
import '../../properties/domain/property_details.dart';
import '../../properties/domain/property_coordinates.dart';
import '../../../core/widgets/app_components.dart';
import '../../discovery/presentation/smart_search_filter_editor.dart';
import '../../discovery/data/discovery_suggestions.dart';
import 'property_map_results_sheet.dart';
import '../../properties/presentation/property_compare_actions.dart';
import '../../discovery/data/smart_search_session.dart';
import '../../discovery/data/marketplace_repository.dart';
import '../../discovery/domain/smart_search_filters.dart';
import '../../discovery/presentation/smart_search_assistant.dart';

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
        fontWeight: FontWeight.w600,
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

String mapPropertyClusterImageName(int count) => 're_cluster_${count.clamp(2, 999)}';

Future<Uint8List> renderMapPropertyClusterImage(int count) async {
  const renderScale = 2.0;
  final label = count > 999 ? '999+' : count.toString();
  final diameter = count >= 100 ? 44.0 : 40.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(renderScale);
  final center = Offset(diameter / 2, diameter / 2);

  canvas.drawCircle(
    center + const Offset(0, 1.5),
    diameter / 2 - 2,
    Paint()
      ..color = const Color(0x26000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
  );
  canvas.drawCircle(center, diameter / 2 - 2, Paint()..color = const Color(0xFF0B8A55));
  canvas.drawCircle(
    center,
    diameter / 2 - 3,
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2,
  );

  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        height: 1,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(
    canvas,
    Offset(
      (diameter - painter.width) / 2,
      (diameter - painter.height) / 2,
    ),
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (diameter * renderScale).ceil(),
    (diameter * renderScale).ceil(),
  );
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (byteData == null) throw StateError('Unable to encode map cluster image.');
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
    this.extraFilters = const {},
  });

  final Map<String, dynamic> extraFilters;
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
            other.east == east && other.extraFilters.length == extraFilters.length &&
            extraFilters.entries.every((entry) => other.extraFilters[entry.key] == entry.value);
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
        Object.hashAllUnordered(extraFilters.entries.map((entry) => Object.hash(entry.key, entry.value))),
      ]);
}

final nearbyPropertiesProvider =
    FutureProvider.autoDispose.family<List<PropertyMarker>, NearbyQuery>(
  (ref, query) {
    ref.watch(propertyDataRevisionProvider);
    final transfer = CancelToken();
    ref.onDispose(() => transfer.cancel('Map viewport superseded'));
    if (query.extraFilters.isNotEmpty) {
      return ref.watch(propertyRepositoryProvider).nearbyFiltered({
      ...query.extraFilters, 'latitude': query.center.latitude, 'longitude': query.center.longitude, 'radius_km': query.radiusKm,
      if (query.purpose != null) 'purpose': query.purpose, if (query.type != null) 'type': query.type,
      if (query.minPrice != null) (query.purpose == 'rent' ? 'min_monthly_rent' : 'min_price'): query.minPrice,
      if (query.maxPrice != null) (query.purpose == 'rent' ? 'max_monthly_rent' : 'max_price'): query.maxPrice,
      if (query.minBedrooms != null) 'min_bedrooms': query.minBedrooms, if (query.minBathrooms != null) 'min_bathrooms': query.minBathrooms,
      if (query.minArea != null) 'min_area_m2': query.minArea, if (query.maxArea != null) 'max_area_m2': query.maxArea,
      if (query.search?.isNotEmpty == true) 'search': query.search,
      if (query.south != null) 'south': query.south, if (query.west != null) 'west': query.west,
      if (query.north != null) 'north': query.north, if (query.east != null) 'east': query.east,
    }, cancelToken: transfer);
    }
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
          cancelToken: transfer,
        );
  },
);

typedef SharedSearchMapBuilder = Widget Function(BuildContext context, List<PropertyMarker> markers,
  ValueChanged<int> onSelect, void Function(double south,double west,double north,double east) onViewport);
// Native MapLibre is the default. Tests replace only the canvas, retaining the real journey/controller.
final sharedSearchMapBuilderProvider = Provider<SharedSearchMapBuilder?>((ref)=>null);

typedef SharedSearchMapProjector = Future<LatLng> Function(math.Point<num> pixels);
final sharedSearchMapProjectorProvider = Provider<SharedSearchMapProjector?>((ref) => null);

class MapSearchActions {
  const MapSearchActions({required this.onDrawArea, required this.onClearArea,
    required this.onSmartSearch, required this.hasDrawnArea});
  final VoidCallback onDrawArea, onClearArea, onSmartSearch;
  final bool hasDrawnArea;
}

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({this.initialLatitude, this.initialLongitude, this.initialType, this.initialFilters, this.sharedSearchJourney=false, this.searchToolbar, this.onShowList,
    this.searchSessionProvider, this.enforceViewport = false, this.resultsMaxExtent = .84,
    this.collapseResults = false, this.onMapInteraction, this.searchToolbarBuilder, this.onSmartSearch, super.key});
  final double? initialLatitude, initialLongitude;
  final String? initialType;
  final SmartSearchFilters? initialFilters;
  final bool sharedSearchJourney;
  final Widget? searchToolbar;
  final Widget Function(BuildContext, MapSearchActions)? searchToolbarBuilder;
  final Future<void> Function()? onSmartSearch;
  final VoidCallback? onShowList;
  final StateNotifierProvider<SmartSearchSession, SmartSearchState>? searchSessionProvider;
  final bool enforceViewport, collapseResults;
  final double resultsMaxExtent;
  final VoidCallback? onMapInteraction;
  bool get hasInitialLocation => initialLatitude != null && initialLongitude != null &&
      initialLatitude!.isFinite && initialLongitude!.isFinite &&
      initialLatitude!.abs() <= 90 && initialLongitude!.abs() <= 180;

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  StateNotifierProvider<SmartSearchSession, SmartSearchState> get _searchSession => widget.searchSessionProvider ?? smartSearchSessionProvider;
  static const _fallback = LatLng(15.3694, 44.1910);
  static const _openFreeMapStyle =
      'https://tiles.openfreemap.org/styles/liberty';
  static const double _defaultRadiusKm = 30;

  MapLibreMapController? _mapController;
  Timer? _styleLoadTimer, _viewportTimer;
  bool _fittingShared = false;
  String _lastSharedViewport = '';
  LatLngBounds? _cameraBounds;
  int _viewportGeneration = 0;
  List<PropertyMarker> _lastGoodItems = const [];
  String _lastGoodCriteria = '';
  final _mapSymbols = <String, Symbol>{};
  final _symbolSignatures = <String, String>{};
  bool _syncingAnnotations = false;
  List<PropertyMarker>? _pendingMarkerItems;

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
  int _areaSelectionGeneration = 0;
  bool _convertingArea = false;
  int _areaAnnotationGeneration = 0;
  bool _listMode = false;
  bool _changingFavorite = false;
  int _sortMode = 0;

  final TextEditingController _searchController = TextEditingController();
  final PropertyDiscoveryHistoryStore _historyStore = const PropertyDiscoveryHistoryStore();
  String _searchText = '';
  double _radiusKm = _defaultRadiusKm;
  Map<String, dynamic> _extraFilters = const {};
  bool _sharedSessionLinked = false;
  List<String> _recentSearches = const <String>[];

  bool _styleLoaded = false;
  String? _mapMessage;
  String _lastMarkerSignature = '';
  int _annotationGeneration = 0, _styleGeneration = 0;
  List<PropertyMarker> _latestMarkerItems = const <PropertyMarker>[];
  final Set<String> _registeredPriceImages = <String>{};

  @override
  void initState() {
    super.initState();
    if (widget.hasInitialLocation) _center = LatLng(widget.initialLatitude!, widget.initialLongitude!);
    if (const ['apartment', 'house', 'villa', 'building', 'land', 'shop', 'office', 'farm'].contains(widget.initialType)) _filterType = widget.initialType;
    if (widget.initialFilters != null) { _sharedSessionLinked = true; _applySharedFilters(widget.initialFilters!); }
    if (widget.sharedSearchJourney) {
      _applySharedFilters(ref.read(_searchSession).filters);
      final rows=ref.read(_searchSession).rows;
      if(rows.isNotEmpty && !ref.read(_searchSession).filters.hasMapArea) _center=LatLng(rows.first.latitude,rows.first.longitude);
    } else {
      if (!widget.hasInitialLocation && widget.initialFilters == null) {
        _applySharedFilters(SmartSearchFilters.fromMap({...ref.read(homeLocationProvider).searchContext,
          if (widget.initialType != null) 'type':widget.initialType}));
      }
      unawaited(_restoreDiscoveryHistory());
    }
  }

  @override
  void dispose() {
    _areaSelectionGeneration++;
    _areaAnnotationGeneration++;
    _viewportGeneration++;
    _styleLoadTimer?.cancel(); _viewportTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _restoreDiscoveryHistory() async {
    final history = await _historyStore.load();
    if (!mounted) return;
    if (widget.hasInitialLocation || widget.initialType != null || widget.initialFilters != null ||
        ref.read(homeLocationProvider).manual || ref.read(homeLocationProvider).device) {
      setState(() => _recentSearches = history.recentSearches);
      return;
    }
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
    if (widget.sharedSearchJourney) return;
    unawaited(
      _historyStore.record(
        query: _searchText,
        filters: _discoveryHistorySnapshot(),
      ),
    );
  }

  void _applySharedFilters(SmartSearchFilters filters) {
    final values = filters.values;
    _filterPurpose = _historyString(values['purpose']); _filterType = _historyString(values['type']);
    _filterMinPrice = _historyDouble(values['min_price']); _filterMaxPrice = _historyDouble(values['max_price']);
    _filterMinBedrooms = _historyInt(values['min_bedrooms']); _filterMinBathrooms = _historyInt(values['min_bathrooms']);
    _filterMinArea = _historyDouble(values['min_area_m2']); _filterMaxArea = _historyDouble(values['max_area_m2']);
    _searchText = _historyString(values['search']) ?? ''; _searchController.text = _searchText;
    _radiusKm = _historyDouble(values['radius_km']) ?? _defaultRadiusKm;
    final lat = _historyDouble(values['latitude']), lon = _historyDouble(values['longitude']);
    if (lat != null && lon != null) _center = LatLng(lat, lon);
    _selectedAreaGeometry = null; _selectedAreaBounds = null;
    if (values['area_polygon'] is String) {
      try { _selectedAreaGeometry = MapAreaGeometry.fromEncodedRing(values['area_polygon'] as String); } catch (_) { /* Server validation remains authoritative. */ }
      _selectedAreaBounds = _selectedAreaGeometry?.bounds;
      if (lat == null && _selectedAreaGeometry != null) _center = _selectedAreaGeometry!.center;
    } else if (values['south'] is num && values['west'] is num && values['north'] is num && values['east'] is num) {
      _selectedAreaBounds = LatLngBounds(southwest: LatLng((values['south'] as num).toDouble(), (values['west'] as num).toDouble()),
        northeast: LatLng((values['north'] as num).toDouble(), (values['east'] as num).toDouble()));
      if (lat == null) _center = LatLng(((values['south'] as num) + (values['north'] as num)) / 2, ((values['west'] as num) + (values['east'] as num)) / 2);
    }
    _extraFilters = Map.unmodifiable(Map<String, dynamic>.from(values)..removeWhere((key, _) => const {
      'purpose','type','min_price','max_price','min_bedrooms','min_bathrooms','min_area_m2','max_area_m2','search',
      'latitude','longitude','radius_km','south','west','north','east','area_polygon'}.contains(key)));
    _selected = null; _lastMarkerSignature = '';
  }

  SmartSearchFilters _currentSmartFilters() => SmartSearchFilters.fromMap({
    ..._extraFilters, ..._discoveryHistorySnapshot(), 'latitude': _center.latitude, 'longitude': _center.longitude, 'radius_km': _radiusKm,
    if (_selectedAreaGeometry != null) 'area_polygon': _selectedAreaGeometry!.encodedRing,
    if (_selectedAreaBounds != null) ...{
      'south': _selectedAreaBounds!.southwest.latitude, 'west': _selectedAreaBounds!.southwest.longitude,
      'north': _selectedAreaBounds!.northeast.latitude, 'east': _selectedAreaBounds!.northeast.longitude,
    },
  });

  Future<void> _openSmartSearch() async {
    if (widget.onSmartSearch != null) { await widget.onSmartSearch!(); return; }
    _sharedSessionLinked = true;
    ref.read(_searchSession.notifier).replaceManually(_currentSmartFilters());
    if (widget.initialFilters != null) { Navigator.of(context).pop(); return; }
    await context.push('/smart-search');
    if (!mounted) return;
    setState(() => _applySharedFilters(ref.read(_searchSession).filters));
    _persistDiscoveryHistory();
    await _renderSelectedAreaAnnotations();
  }

  Widget _withSharedSession(Widget child) => PopScope(
    onPopInvokedWithResult: (didPop, _) {
      if (didPop && _sharedSessionLinked) {
        final filters = _currentSmartFilters(), current = ref.read(_searchSession).filters.values;
        if (current.length != filters.values.length || !filters.values.entries.every((entry) => current[entry.key] == entry.value)) ref.read(_searchSession.notifier).replaceManually(filters);
      }
    }, child: child,
  );

  void _showLocationGuidance(
    String message, {
    Future<bool> Function()? openSettings,
  }) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(message),
      action: openSettings == null
          ? null
          : SnackBarAction(
              label: 'الإعدادات',
              onPressed: () { unawaited(openSettings()); },
            ),
    ));
  }

  Future<void> _loadCurrentLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        _showLocationGuidance(
          'خدمة الموقع مغلقة. يمكنك تشغيلها من إعدادات الهاتف.',
          openSettings: Geolocator.openLocationSettings,
        );
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        _showLocationGuidance(
          'تم منع إذن الموقع نهائيًا. يمكنك السماح به من إعدادات التطبيق.',
          openSettings: Geolocator.openAppSettings,
        );
        return;
      }
      if (permission == LocationPermission.denied) {
        _showLocationGuidance('لم يتم السماح بالموقع. يمكنك البحث بالخريطة دون تفعيل الموقع.');
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
      _mapSymbols.clear(); _symbolSignatures.clear(); _annotationGeneration++; _styleGeneration++;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.sharedSearchJourney) {
        if (widget.enforceViewport) {
          unawaited(_fitSharedRows().whenComplete(() {
            if (mounted) { _lastSharedViewport = ''; return _sharedViewport(); }
          }));
        } else if (ref.read(_searchSession).started) { _fitSharedRows(); } else { _sharedViewport(); }
      } else if (mounted) { _renderSelectedAreaAnnotations(); _commitCameraCenter(); }
    });
  }

  Future<void> _moveToMyLocation() async {
    final controller = _mapController;
    final location = _userLocation;
    if (controller == null || location == null) return;
    await controller.animateCamera(CameraUpdate.newLatLngZoom(location, 14));
  }

  Future<void> _commitCameraCenter() async {
    if (_selectingArea || _fittingShared) return;
    final generation = ++_viewportGeneration;
    _viewportTimer?.cancel();
    _viewportTimer = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted || generation != _viewportGeneration) return;
      if (widget.sharedSearchJourney) { await _sharedViewport(generation); return; }
      final controller = _mapController;
      if (controller == null || !_styleLoaded) return;
      try {
        final bounds = await controller.getVisibleRegion();
        if (!mounted || generation != _viewportGeneration) return;
        _applyCameraViewport(bounds);
      } catch (_) {
        if (mounted && generation == _viewportGeneration) setState(() => _mapMessage = 'تعذر تحديد النطاق. حرّك الخريطة للمحاولة مجددًا.');
      }
    });
  }

  void _applyCameraViewport(LatLngBounds bounds) {
    if (_cameraBounds != null && _viewportSignature(_cameraBounds!) == _viewportSignature(bounds)) {
      _queueMarkerSync(_latestMarkerItems); return;
    }
    setState(() {
      _cameraBounds = bounds;
      _center = LatLng((bounds.southwest.latitude + bounds.northeast.latitude) / 2,
        (bounds.southwest.longitude + bounds.northeast.longitude) / 2);
      // The camera owns the viewport after a pan; a Home city must not pin it.
      _extraFilters = Map<String, dynamic>.from(_extraFilters)..remove('governorate');
      if (_selected != null && !_insideBounds(_selected!, bounds)) _selected = null;
    });
  }

  bool _insideBounds(PropertyMarker row, LatLngBounds bounds) =>
    row.latitude >= bounds.southwest.latitude && row.latitude <= bounds.northeast.latitude &&
    (bounds.southwest.longitude <= bounds.northeast.longitude
      ? row.longitude >= bounds.southwest.longitude && row.longitude <= bounds.northeast.longitude
      : row.longitude >= bounds.southwest.longitude || row.longitude <= bounds.northeast.longitude);

  List<PropertyMarker> _currentVisibleItems(List<PropertyMarker> rows) {
    final bounds = _cameraBounds;
    return _filterToSelectedArea(rows).where((row) =>
      hasValidPropertyCoordinates(row.latitude, row.longitude) &&
      (bounds == null || _insideBounds(row, bounds)) &&
      (_filterPurpose == null || row.purpose == _filterPurpose) &&
      (_filterType == null || row.type == _filterType ||
        (_filterType == 'apartment' && row.type == 'floor'))).toList(growable: false);
  }

  String _markerSignature(List<PropertyMarker> items) {
    final ids = items
        .take(250)
        .map((item) =>
            '${item.id}:${item.price}:${item.purpose}:${item.latitude}:${item.longitude}')
        .join('|');
    return '${_selected?.id ?? 0}|${((_mapController?.cameraPosition?.zoom ?? 13.5) * 2).floor()}|$ids';
  }

  void _queueMarkerSync(List<PropertyMarker> items) {
    _latestMarkerItems = items.take(250).toList(growable: false);
    if (!_styleLoaded || _mapController == null) return;
    final signature = _markerSignature(items);
    if (signature == _lastMarkerSignature) return;
    _lastMarkerSignature = signature;
    _annotationGeneration++;
    _pendingMarkerItems = _latestMarkerItems;
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _drainMarkerUpdates(); });
  }

  Future<void> _drainMarkerUpdates() async {
    if (_syncingAnnotations) return;
    _syncingAnnotations = true;
    try {
      while (mounted && _pendingMarkerItems != null) {
        final rows = _pendingMarkerItems!; _pendingMarkerItems = null;
        await _syncPropertyAnnotations(rows);
      }
    } finally { _syncingAnnotations = false; }
  }

  Future<void> _syncPropertyAnnotations(List<PropertyMarker> items) async {
    final controller = _mapController;
    if (controller == null || !_styleLoaded) return;

    final generation = _annotationGeneration, style = _styleGeneration;
    final visible = items.take(250).toList(growable: false);
    final zoom = controller.cameraPosition?.zoom ?? 13.5;
    final clusters = clusterPropertyMarkers(
      visible,
      zoom: zoom,
      selectedPropertyId: _selected?.id,
    );

    try {
      final options = <SymbolOptions>[];
      final data = <Map<String, dynamic>>[];
      final keys = <String>[];

      for (final cluster in clusters) {
        if (cluster.isCluster) {
          final ids = cluster.items.map((row) => row.id).toList()..sort();
          keys.add('cluster:${ids.join(',')}');
          final imageName = mapPropertyClusterImageName(cluster.items.length);
          await _ensureMapClusterImage(
            controller,
            imageName: imageName,
            count: cluster.items.length,
          );
          if (generation != _annotationGeneration) return;
          options.add(
            SymbolOptions(
              geometry: LatLng(cluster.latitude, cluster.longitude),
              iconImage: imageName,
              iconSize: 1,
              iconAnchor: 'center',
              zIndex: 10,
            ),
          );
          data.add(<String, dynamic>{
            'cluster_count': cluster.items.length,
            'cluster_lat': cluster.latitude,
            'cluster_lon': cluster.longitude,
          });
          continue;
        }

        final property = cluster.first;
        keys.add('property:${property.id}');
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
      // Keep unchanged native annotations. Add/update before removal so a
      // refresh never clears the entire map between two platform messages.
      final desired = keys.toSet(), addedKeys = <String>[];
      final additions = <SymbolOptions>[], additionData = <Map<String, dynamic>>[];
      for (var index = 0; index < keys.length; index++) {
        final key = keys[index], option = options[index], existing = _mapSymbols[key];
        final signature = '${option.iconImage}:${option.geometry?.latitude}:${option.geometry?.longitude}:${option.zIndex}';
        if (existing == null) {
          addedKeys.add(key); additions.add(option); additionData.add(data[index]);
        } else if (_symbolSignatures[key] != signature) {
          await controller.updateSymbol(existing, option);
          _symbolSignatures[key] = signature;
          if (!mounted || generation != _annotationGeneration) return;
        }
      }
      if (additions.isNotEmpty) {
        final symbols = await controller.addSymbols(additions, additionData);
        if (!mounted || style != _styleGeneration) return;
        for (var index = 0; index < symbols.length; index++) {
          final key = addedKeys[index], option = additions[index];
          _mapSymbols[key] = symbols[index];
          _symbolSignatures[key] = '${option.iconImage}:${option.geometry?.latitude}:${option.geometry?.longitude}:${option.zIndex}';
        }
        if (!mounted || generation != _annotationGeneration) return;
        await controller.setSymbolIconAllowOverlap(true);
        await controller.setSymbolIconIgnorePlacement(true);
      }
      final removed = _mapSymbols.keys.where((key) => !desired.contains(key)).toList();
      if (removed.isNotEmpty) {
        await controller.removeSymbols(removed.map((key) => _mapSymbols[key]!));
        for (final key in removed) { _mapSymbols.remove(key); _symbolSignatures.remove(key); }
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

  Future<void> _ensureMapClusterImage(
    MapLibreMapController controller, {
    required String imageName,
    required int count,
  }) async {
    if (_registeredPriceImages.contains(imageName)) return;
    final bytes = await renderMapPropertyClusterImage(count);
    await controller.addImage(imageName, bytes);
    _registeredPriceImages.add(imageName);
  }

  void _onPropertySymbolTapped(Symbol symbol) {
    final clusterCountRaw = symbol.data?['cluster_count'];
    final clusterCount = clusterCountRaw is int
        ? clusterCountRaw
        : int.tryParse('$clusterCountRaw');
    if (clusterCount != null && clusterCount > 1) {
      final geometry = symbol.options.geometry;
      if (geometry != null) unawaited(_zoomIntoCluster(geometry));
      return;
    }

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

  Future<void> _zoomIntoCluster(LatLng center) async {
    final controller = _mapController;
    if (controller == null) return;
    final currentZoom = controller.cameraPosition?.zoom ?? 13.5;
    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(center, (currentZoom + 2).clamp(3, 17).toDouble()),
    );
    if (!mounted) return;
    setState(() {
      _selected = null;
      _lastMarkerSignature = '';
    });
  }

  Future<void> _focusProperty(PropertyMarker property) async {
    final controller = _mapController;
    final target = LatLng(property.latitude, property.longitude);
    setState(() {
      _listMode = false;
      _selected = property;
      _lastMarkerSignature = '';
    });
    if (controller == null) return;
    await controller.animateCamera(CameraUpdate.newLatLngZoom(target, 16));
    if (!mounted) return;
    // onCameraIdle commits center and bounds together after the animation.
  }

  Future<void> _openDetails(PropertyMarker property) async {
    setState(() => _selected = property);
    await context.push('/properties/${property.id}', extra: PropertySummary(id: property.id, title: property.title,
      purpose: property.purpose ?? '', type: property.type ?? '', price: property.price, currency: property.currency,
      latitude: property.latitude, longitude: property.longitude, monthlyRent: property.monthlyRent,
      mainImage: property.mainImage, imageUrls: property.imageUrls));
    if (mounted && widget.enforceViewport) await ref.read(_searchSession.notifier).search();
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
    return type == 'apartment' || type == 'floor' || type == 'house' || type == 'villa';
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
      _extraFilters = const {};
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
    var count = _extraFilters.length;
    if (_filterPurpose != null) count++;
    if (_filterType != null) count++;
    if (_filterMinPrice != null || _filterMaxPrice != null) count++;
    if (_filterMinBedrooms != null) count++;
    if (_filterMinBathrooms != null) count++;
    if (_filterMinArea != null || _filterMaxArea != null) count++;
    return count;
  }

  Future<void> _showFilters({String? focus}) async {
    final value=await AppBottomSheet.show<SmartSearchFilters>(context,builder:(_)=>SmartSearchFilterEditor(initial:_currentSmartFilters(), focus: focus));
    if(value!=null && mounted) setState(()=>_applySharedFilters(value));
  }

  Future<void> _showSearchSheet(List<PropertyMarker> items) async {
    final value = await showModalBottomSheet<DiscoverySearchChoice>(
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

    final normalized = value.text.trim(), suggestion = value.suggestion;
    _searchController.text = normalized;
    setState(() {
      _searchText = normalized;
      if (suggestion?.type != null) {
        _filterType = suggestion!.type;
        if (!_typeUsesRooms(_filterType)) { _filterMinBedrooms = null; _filterMinBathrooms = null; }
      }
      if (suggestion?.location case final HomeLocation location) {
        _center = LatLng(location.latitude, location.longitude);
        _cameraBounds = null;
        _selectedAreaBounds = null; _selectedAreaGeometry = null;
        _extraFilters = Map<String, dynamic>.from(_extraFilters)..remove('governorate');
      }
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
    if (suggestion?.location != null && _mapController != null) {
      await _mapController!.animateCamera(CameraUpdate.newLatLngZoom(_center, 13.5));
    }
  }

  List<String> _searchSuggestions(List<PropertyMarker> items) {
    final seen = <String>{};
    final values = <String>[];
    for (final item in items) {
      for (final candidate in [item.address]) {
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
    _areaSelectionGeneration++;
    _viewportGeneration++;
    widget.onMapInteraction?.call();
    setState(() {
      _convertingArea = false;
      _selectingArea = true;
      _areaDraftPoints = <Offset>[];
      _listMode = false;
      _selected = null;
      _mapMessage = null;
    });
  }

  void _cancelAreaSelection() {
    _areaSelectionGeneration++;
    setState(() {
      _convertingArea = false;
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
    final projector = ref.read(sharedSearchMapProjectorProvider);
    final draft = _simplifyAreaStroke(_areaDraftPoints);
    if ((controller == null && projector == null) || draft.length < 5) {
      if (mounted) {
        setState(() {
          _areaDraftPoints = <Offset>[];
          _mapMessage = 'ارسم حدود المنطقة بإصبعك بشكل مغلق وواضح.';
        });
      }
      return;
    }
    final generation = ++_areaSelectionGeneration;
    setState(() => _convertingArea = true);
    try {
      final geoPoints = <LatLng>[];
      final pixelRatio = MediaQuery.devicePixelRatioOf(context);
      for (final point in draft) {
        final pixels = MapScreenCoordinateSpace.logicalToPlatformPixels(point, pixelRatio);
        geoPoints.add(await (projector != null ? projector(pixels) : controller!.toLatLng(pixels)));
        if (!mounted || generation != _areaSelectionGeneration || !_selectingArea) return;
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
        _mapMessage = widget.sharedSearchJourney ? null : 'تم اعتماد المنطقة المرسومة وعرض العقارات داخلها فقط.';
      });
      Future<void>? sharedSearch;
      if (widget.sharedSearchJourney) {
        final current = ref.read(_searchSession).filters.values;
        const bounds = ['south', 'west', 'north', 'east'];
        final hasViewport = bounds.every((key) => current[key] is num);
        final values = Map<String, dynamic>.from(current)
          ..removeWhere((key, _) => SmartSearchFilters.mapFields.contains(key) || key == 'governorate');
        values.addAll({'area_polygon': geometry.encodedRing,
          if (hasViewport) ...{for (final key in bounds) key: current[key]}
          else ...{'south': geometry.bounds.southwest.latitude, 'west': geometry.bounds.southwest.longitude,
            'north': geometry.bounds.northeast.latitude, 'east': geometry.bounds.northeast.longitude}});
        sharedSearch = ref.read(_searchSession.notifier).replaceManually(SmartSearchFilters.fromMap(values));
      }
      await _renderSelectedAreaAnnotations();
      if (sharedSearch != null) await sharedSearch;
    } catch (_) {
      if (!mounted || generation != _areaSelectionGeneration) return;
      setState(() {
        _areaDraftPoints = <Offset>[];
        _mapMessage = 'تعذر تحويل الرسم إلى منطقة على الخريطة. حاول مرة أخرى.';
      });
    } finally {
      if (mounted && generation == _areaSelectionGeneration) setState(() => _convertingArea = false);
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
    final generation = ++_areaAnnotationGeneration;
    final controller = _mapController;
    final geometry = _selectedAreaGeometry;
    if (controller == null || !_styleLoaded) return;
    await _removeAreaAnnotations();
    if (!mounted || generation != _areaAnnotationGeneration) return;
    if (geometry == null) return;

    Fill? fill;
    Line? line;
    try {
      fill = await controller.addFill(
        FillOptions(
          geometry: <List<LatLng>>[geometry.points],
          fillColor: '#0B8A55',
          fillOpacity: 0.16,
          fillOutlineColor: '#0B8A55',
        ),
      );
      line = await controller.addLine(
        LineOptions(
          geometry: geometry.points,
          lineColor: '#0B8A55',
          lineWidth: 4,
          lineOpacity: 0.96,
        ),
      );
      if (!mounted || generation != _areaAnnotationGeneration) {
        try { await controller.removeFill(fill); } catch (_) {}
        try { await controller.removeLine(line); } catch (_) {}
        return;
      }
      _selectedAreaFill = fill;
      _selectedAreaLine = line;
    } catch (_) {
      try { if (fill != null) await controller.removeFill(fill); } catch (_) {}
      try { if (line != null) await controller.removeLine(line); } catch (_) {}
      if (mounted && generation == _areaAnnotationGeneration) {
        setState(() => _mapMessage =
            'تم تطبيق فلتر المنطقة، لكن تعذر رسم حدودها فوق الخريطة.');
      }
    }
  }

  void _clearSelectedArea() {
    _areaSelectionGeneration++;
    _areaAnnotationGeneration++;
    unawaited(_removeAreaAnnotations());
    setState(() {
      _selectedAreaBounds = null;
      _selectedAreaGeometry = null;
      _selected = null;
      _lastMarkerSignature = '';
      _mapMessage = null;
    });
    if (widget.sharedSearchJourney) {
      unawaited(ref.read(_searchSession.notifier).replaceManually(
        ref.read(_searchSession).filters.without('area_polygon')));
    }
  }


  void _openAddProperty() {
    context.push('/add-property');
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sharedSearchJourney) return _sharedJourney();
    final bounds = _selectedAreaBounds ?? _cameraBounds;
    final effective = Map<String, dynamic>.from(_currentSmartFilters().apiFilters)..removeWhere((key, _) => const {
      'purpose','type','min_price','max_price','min_monthly_rent','max_monthly_rent','min_bedrooms','min_bathrooms','min_area_m2','max_area_m2','search',
      'latitude','longitude','radius_km','south','west','north','east'}.contains(key));
    if (bounds != null) effective['viewport'] = 1;
    final query = NearbyQuery(
      center: _center,
      radiusKm: _radiusKm,
      extraFilters: effective,
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
    final criterionValues = Map<String, dynamic>.from(_currentSmartFilters().apiFilters)
      ..removeWhere((key, _) => const ['latitude','longitude','radius_km','south','west','north','east','governorate'].contains(key));
    final criterionKeys = criterionValues.keys.toList()..sort();
    final criteria = [for (final key in criterionKeys) '$key:${criterionValues[key]}'].join('|');
    if (rawProperties.asData != null) { _lastGoodItems = rawProperties.asData!.value; _lastGoodCriteria = criteria; }
    final displayed = _currentVisibleItems(rawProperties.asData?.value ?? (criteria == _lastGoodCriteria ? _lastGoodItems : const []));
    final properties = rawProperties.whenData(_currentVisibleItems);
    _queueMarkerSync(_selectingArea ? const [] : displayed);
    if (_selected != null && !displayed.any((row) => row.id == _selected!.id)) _selected = null;
    final user = ref.watch(authControllerProvider).asData?.value;
    final favoriteIds = user == null
        ? const <int>{}
        : ref.watch(favoritePropertyIdsProvider).maybeWhen(
              data: (value) => value,
              orElse: () => const <int>{},
            );

    final apiError = properties.asError?.error;
    final canvas = ref.watch(sharedSearchMapBuilderProvider);

    return _withSharedSession(Stack(fit: StackFit.expand, children: [Offstage(offstage: _listMode, child: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SmartSearchAssistantLayer(enabled: !_selectingArea, showComparisonTray: false, bottom: MediaQuery.sizeOf(context).height * .29 + 24, onPressed: _openSmartSearch, child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: canvas != null
              ? canvas(context, displayed, (id) { for (final row in displayed) { if (row.id == id) setState(() => _selected = row); } },
                (south, west, north, east) => _applyCameraViewport(LatLngBounds(southwest: LatLng(south, west), northeast: LatLng(north, east))))
              : _buildMap()),
            if (!_selectingArea) _buildTopFilterPanel(properties),
            if (!_selectingArea) _buildMapControls(),
            if (_selectedAreaBounds != null && !_selectingArea)
              _buildAreaChip(),
            if (_selectingArea) _buildAreaSelectionOverlay(),
            if (!_selectingArea) PropertyMapResultsSheet(items: displayed, selectedId: _selected?.id,
              loading: rawProperties.isLoading, error: apiError == null ? null : friendlyApiError(apiError),
              onRetry: () => ref.invalidate(nearbyPropertiesProvider(query)),
              onShowList: () => setState(() => _listMode = true),
              itemBuilder: (row) => PropertyMapResultCard(property: row,
                favorite: favoriteIds.contains(row.id), onFavorite: _changingFavorite ? null : () => _toggleFavorite(row.id,
                  currentlyFavorite: favoriteIds.contains(row.id)), onMap: () => _focusProperty(row), onDetails: () => _openDetails(row))),
            if (_mapMessage != null && !_selectingArea)
              PositionedDirectional(
                start: 14,
                end: 14,
                bottom: MediaQuery.sizeOf(context).height * .29 + 14,
                child: _MessageCard(text: _mapMessage!),
              ),
          ],
        )),
      ),
    )),
      if (_listMode) _buildListMode(properties, query, favoriteIds),
    ]));
  }

  String _viewportSignature(LatLngBounds bounds) => '${bounds.southwest.latitude.toStringAsFixed(5)}:${bounds.southwest.longitude.toStringAsFixed(5)}:${bounds.northeast.latitude.toStringAsFixed(5)}:${bounds.northeast.longitude.toStringAsFixed(5)}';

  Future<void> _sharedViewport([int? generation]) async {
    final controller=_mapController;
    if(controller==null || !mounted || _fittingShared || _selectingArea)return;
    try {
      final bounds=await controller.getVisibleRegion();
      if(!mounted || _fittingShared || (generation != null && generation != _viewportGeneration))return;
      final signature=_viewportSignature(bounds);
      if(signature==_lastSharedViewport)return;
      _lastSharedViewport=signature;
      ref.read(_searchSession.notifier).updateViewport(south:bounds.southwest.latitude,west:bounds.southwest.longitude,north:bounds.northeast.latitude,east:bounds.northeast.longitude);
    } catch(_) { if(mounted)setState(()=>_mapMessage='تعذر تحديد النطاق. حرّك الخريطة للمحاولة مجددًا.'); }
  }

  Future<void> _fitSharedRows() async {
    final search=ref.read(_searchSession), controller=_mapController;
    if(controller==null || !mounted)return;
    final values=search.filters.values;
    if(widget.enforceViewport && const ['south','west','north','east'].every((key)=>values[key] is num)) {
      // Reopening the same map restores its actual bounds, including an empty
      // result viewport, rather than fitting only its remaining listing pins.
      final bounds=LatLngBounds(southwest:LatLng((values['south'] as num).toDouble(),(values['west'] as num).toDouble()),
        northeast:LatLng((values['north'] as num).toDouble(),(values['east'] as num).toDouble()));
      _fittingShared=true;
      try {
        await controller.moveCamera(CameraUpdate.newLatLngBounds(bounds,left:0,top:0,right:0,bottom:0));
        _lastSharedViewport=_viewportSignature(await controller.getVisibleRegion());
      } catch(_) { /* Keep the canonical viewport when the native camera is unavailable. */ }
      finally { _fittingShared=false; }
      return;
    }
    final rows=search.rows;
    if(rows.isEmpty)return;
    final points=rows.where((p)=>p.latitude.isFinite && p.longitude.isFinite && p.latitude.abs()<=90 && p.longitude.abs()<=180).toList();
    if(points.isEmpty)return;
    double south=points.first.latitude,north=south,west=points.first.longitude,east=west;
    for(final p in points){if(p.latitude<south)south=p.latitude;if(p.latitude>north)north=p.latitude;if(p.longitude<west)west=p.longitude;if(p.longitude>east)east=p.longitude;}
    _fittingShared=true;
    try {
      if(south==north && west==east) { await controller.moveCamera(CameraUpdate.newLatLngZoom(LatLng(south,west),14)); }
      else { await controller.moveCamera(CameraUpdate.newLatLngBounds(LatLngBounds(southwest:LatLng(south,west),northeast:LatLng(north,east)),left:32,top:150,right:32,bottom:180)); }
      _lastSharedViewport=_viewportSignature(await controller.getVisibleRegion());
    } catch(_) { /* Retain the user's existing search when camera fitting is unavailable. */ }
    finally { _fittingShared=false; }
  }

  Widget _sharedJourney() {
    final state=ref.watch(_searchSession);
    ref.listen<SmartSearchState>(_searchSession, (before, after) {
      if (before?.filters.values['area_polygon'] == after.filters.values['area_polygon']) return;
      final encoded = after.filters.values['area_polygon'];
      MapAreaGeometry? geometry;
      if (encoded is String) {
        try { geometry = MapAreaGeometry.fromEncodedRing(encoded); } catch (_) { /* Invalid areas are rejected by the API. */ }
      }
      setState(() { _selectedAreaGeometry = geometry; _selectedAreaBounds = geometry?.bounds; });
      unawaited(_renderSelectedAreaAnnotations());
    });
    final rows=state.rows.where((p)=>hasValidPropertyCoordinates(p.latitude, p.longitude)).map((p)=>PropertyMarker(
      id:p.id,title:p.title,price:p.monthlyRent??p.price,currency:p.currency,latitude:p.latitude,longitude:p.longitude,distanceKm:0,
      purpose:p.purpose,type:p.type,areaM2:p.areaM2,bedrooms:p.bedrooms,bathrooms:p.bathrooms,address:p.address,
      mainImage:p.mainImage,imageUrls:p.imageUrls,isSpotlight:p.isSpotlight,monthlyRent:p.monthlyRent)).toList(growable:false);
    if(_selected!=null && !rows.any((p)=>p.id==_selected!.id))_selected=null;
    _queueMarkerSync(rows);
    final user = ref.watch(authControllerProvider).asData?.value;
    final favoriteIds = user == null ? const <int>{} : ref.watch(favoritePropertyIdsProvider).asData?.value ?? const <int>{};
    final canvas=ref.watch(sharedSearchMapBuilderProvider);
    void select(int id){for(final p in rows){if(p.id==id){setState(()=>_selected=p);break;}}}
    final toolbar = widget.searchToolbarBuilder?.call(context, MapSearchActions(
      onDrawArea: _beginAreaSelection, onClearArea: _clearSelectedArea,
      onSmartSearch: _openSmartSearch, hasDrawnArea: state.filters.values.containsKey('area_polygon'))) ?? widget.searchToolbar;
    return PopScope(canPop: !_selectingArea, onPopInvokedWithResult: (didPop, _) {
      if (!didPop && _selectingArea) _cancelAreaSelection();
    }, child: Stack(fit:StackFit.expand,children:[
      Positioned.fill(child:Listener(onPointerDown: (_) => widget.onMapInteraction?.call(),
        child:canvas==null ? _buildMap() : canvas(context,rows,select,(south,west,north,east)
        { if (!_selectingArea) ref.read(_searchSession.notifier).updateViewport(south:south,west:west,north:north,east:east); }))),
      if (!_selectingArea && toolbar != null) PositionedDirectional(start:12,end:12,top:10,child:toolbar),
      if (!_selectingArea) PropertyMapResultsSheet(items: rows, selectedId: _selected?.id, loading: state.loading,
        maxExtent: widget.resultsMaxExtent, collapsed: widget.collapseResults,
        error: state.resultsError ?? _mapMessage, onRetry: () => ref.read(_searchSession.notifier).retryResults(),
        more: state.more, onMore: () => ref.read(_searchSession.notifier).search(more: true),
        onShowList: widget.onShowList,
        itemBuilder: (row) => PropertyMapResultCard(property: row, compact: widget.enforceViewport,
          favorite: favoriteIds.contains(row.id), onFavorite: _changingFavorite ? null : () => _toggleFavorite(row.id,
            currentlyFavorite: favoriteIds.contains(row.id)), onMap: () => _focusProperty(row), onDetails: () => _openDetails(row))),
      if (_selectingArea) _buildAreaSelectionOverlay(),
    ]));
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
        onMore: () => _showFilters(),
        onRooms: () => _showFilters(focus: 'min_bedrooms'),
      ),
    );
  }

  Widget _buildMapControls() {
    return PositionedDirectional(
      start: 12,
      bottom: MediaQuery.sizeOf(context).height * .29 + 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Material(elevation: 3, color: Colors.white, borderRadius: BorderRadius.circular(16), child: TextButton.icon(
            key: const ValueKey('map-smart-search'), onPressed: _openSmartSearch, icon: const SmartSearchRobotIcon(), label: const Text('بحث ذكي'))),
          const SizedBox(height: 8),
          Material(
            elevation: 5,
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: _beginAreaSelection,
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    EbrokerIcon(Icons.gesture_rounded, color: AppTheme.brand),
                    SizedBox(width: 7),
                    Text(
                      'رسم منطقة',
                      style: TextStyle(fontWeight: FontWeight.w600),
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
            onPressed: _userLocation == null
                ? _loadCurrentLocation
                : _moveToMyLocation,
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
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
        child: InputChip(
          avatar: const EbrokerIcon(Icons.gesture_rounded, size: 18),
          label: const Text('منطقة مرسومة'),
          deleteIcon: const EbrokerIcon(Icons.close_rounded, size: 18),
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
              key: const ValueKey('map-area-drawing'),
              behavior: HitTestBehavior.opaque,
              onPanStart: _convertingArea ? null : _startAreaStroke,
              onPanUpdate: _convertingArea ? null : _updateAreaStroke,
              onPanEnd: _convertingArea ? null : _finishAreaStroke,
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
                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      const EbrokerIcon(Icons.draw_rounded, color: AppTheme.brand),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _convertingArea ? 'جارٍ تحديد حدود المنطقة…' :
                            _mapMessage ?? 'ارسم بإصبعك حدود المنطقة المطلوبة مثل القلم. عند رفع إصبعك سيتم عرض العقارات داخل الرسم فقط.',
                          style: const TextStyle(fontWeight: FontWeight.w600),
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
                    child: EbrokerOutlinedButton.icon(
                      onPressed: _cancelAreaSelection,
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      icon: const EbrokerIcon(Icons.close_rounded),
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
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          EbrokerIcon(Icons.touch_app_rounded, color: Colors.white),
                          SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'اسحب للرسم • ارفع إصبعك للاعتماد',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
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
              tooltip: 'بحث وتصفية',
              onPressed: () {
                final items =
                    properties.asData?.value ?? const <PropertyMarker>[];
                _showSearchSheet(items);
              },
              icon: const EbrokerIcon(Icons.search),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SmartSearchAssistantLayer(onPressed: _openSmartSearch, child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              child: Row(
                children: [
                  Expanded(
                    child: EbrokerSegmentedButton<int>(
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
                        avatar: const EbrokerIcon(Icons.search, size: 18),
                        label: Text(_searchText),
                        onDeleted: () {
                          _searchController.clear();
                          setState(() => _searchText = '');
                          _persistDiscoveryHistory();
                        },
                      ),
                    if (_selectedAreaBounds != null)
                      InputChip(
                        avatar: const EbrokerIcon(Icons.crop_free, size: 18),
                        label: const Text('منطقة محددة'),
                        onDeleted: _clearSelectedArea,
                      ),
                  ],
                ),
              ),
            Expanded(
              child: _buildListContent(properties, query, favoriteIds),
            ),
          ],
        )),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: _MapListSwitcherBar(
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
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 110),
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

class _MapQuickFilterPanel extends StatelessWidget {
  const _MapQuickFilterPanel({required this.purpose, required this.type, required this.filterCount,
    required this.searchText, required this.onPurpose, required this.onType, required this.onSearch,
    required this.onMore, required this.onRooms});
  final String? purpose, type;
  final int filterCount;
  final String searchText;
  final ValueChanged<String?> onPurpose, onType;
  final VoidCallback onSearch, onMore, onRooms;
  @override
  Widget build(BuildContext context) => Material(elevation: 3,
    color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(12),
    child: Padding(padding: const EdgeInsets.all(8), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [Expanded(child: TextFormField(key: ValueKey('map-search-field-$searchText'),
        initialValue: searchText, readOnly: true, onTap: onSearch,
        decoration: const InputDecoration(isDense: true, hintText: 'ابحث عن عقار أو منطقة…', prefixIcon: Icon(Icons.search)))),
        IconButton(key: const ValueKey('map-more-filters'), tooltip: filterCount == 0 ? 'المزيد من الفلاتر' : 'الفلاتر ($filterCount)',
          onPressed: onMore, icon: const Icon(Icons.tune)),
      ]),
      const SizedBox(height: 6),
      SizedBox(height: 44 + (MediaQuery.textScalerOf(context).scale(12) - 12).clamp(0, 26).toDouble(),
        child: ListView(scrollDirection: Axis.horizontal, children: [
          _TypeChip(label: 'للإيجار', selected: purpose == 'rent', onTap: () => onPurpose('rent')),
          _TypeChip(label: 'للبيع', selected: purpose == 'sale', onTap: () => onPurpose('sale')),
          _TypeChip(label: 'كل الأنواع', selected: type == null, onTap: () => onType(null)),
          for (final entry in SmartSearchFilters.types.entries)
            _TypeChip(label: entry.value, selected: type == entry.key, onTap: () => onType(entry.key)),
          if (const ['apartment','house','villa'].contains(type)) ActionChip(label: const Text('الغرف'), onPressed: onRooms),
        ])),
    ])));
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
      child: EbrokerChoiceChip(
        label: Text(label),
        selected: selected,
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
      borderRadius: BorderRadius.circular(8),
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
                    EbrokerIcon(mapMode
                        ? Icons.view_list_outlined
                        : Icons.map_outlined),
                    const SizedBox(width: 7),
                    Text(
                      mapMode ? 'قائمة' : 'خريطة',
                      style: const TextStyle(fontWeight: FontWeight.w600),
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
                    color: EbrokerDesign.text,
                    fontWeight: FontWeight.w600,
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
                    EbrokerIcon(Icons.add_circle, color: AppTheme.brandStrong),
                    SizedBox(width: 7),
                    Text(
                      'إضافة',
                      style: TextStyle(
                        color: AppTheme.brandStrong,
                        fontWeight: FontWeight.w600,
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
        icon: EbrokerIcon(icon),
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
    return EbrokerOutlinedButton.icon(
      onPressed: onPressed,
      icon: const EbrokerIcon(Icons.tune, size: 18),
      label: Text(count == 0 ? 'تصفية' : '$count'),
    );
  }
}

class DiscoverySearchSheet extends ConsumerStatefulWidget {
  const DiscoverySearchSheet({required this.initialValue, this.suggestions = const [], this.recentSearches = const [], super.key});
  final String initialValue;
  final List<String> suggestions, recentSearches;
  @override
  ConsumerState<DiscoverySearchSheet> createState() => _DiscoverySearchSheetState();
}

class _DiscoverySearchSheetState extends ConsumerState<DiscoverySearchSheet> {
  late final _controller = TextEditingController(text: widget.initialValue);
  bool _submitted = false;
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  void _submit(String text, {DiscoverySuggestion? suggestion}) {
    if (_submitted) return;
    _submitted = true;
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(DiscoverySearchChoice(text.trim(), suggestion: suggestion));
  }
  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim(), normal = normalizeDiscoveryText(query);
    final remote = ref.watch(discoverySuggestionsProvider(query));
    final seen = <String>{};
    final rows = <DiscoverySuggestion>[
      ...?remote.asData?.value,
      if (query.length >= 2) for (final entry in SmartSearchFilters.types.entries)
        if (normalizeDiscoveryText(entry.value).contains(normal)) DiscoverySuggestion(label: entry.value, kind: 'نوع العقار', type: entry.key),
      if (query.length >= 2) for (final text in widget.suggestions)
        if (normalizeDiscoveryText(text).contains(normal)) DiscoverySuggestion(label: text, kind: 'منطقة من إعلان منشور'),
    ].where((row) => seen.add('${row.kind}:${row.label}')).take(8).toList();
    return Directionality(textDirection: TextDirection.rtl, child: Padding(
      padding: EdgeInsets.fromLTRB(18, 16, 18, MediaQuery.viewInsetsOf(context).bottom + 18),
      child: ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .8),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('ابحث عن عقارك', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 12),
          TextField(key: const ValueKey('discovery-search-input'), controller: _controller, autofocus: true,
            maxLength: 120, textInputAction: TextInputAction.search,
            decoration: const InputDecoration(hintText: 'اسم منطقة أو نوع العقار', prefixIcon: Icon(Icons.search), counterText: ''),
            onChanged: (_) => setState(() {}), onSubmitted: (text) => _submit(text)),
          if (remote.isLoading && query.length >= 2) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
          if (query.isEmpty && widget.recentSearches.isNotEmpty) ...[
            const SizedBox(height: 12), const Text('بحثت مؤخراً'),
            Wrap(spacing: 8, children: [for (final text in widget.recentSearches)
              ActionChip(label: Text(text), avatar: const Icon(Icons.history, size: 16), onPressed: () => _submit(text))]),
          ],
          for (final row in rows) ListTile(key: ValueKey('search-suggestion-${row.kind}-${row.label}'),
            leading: Icon(row.type == null ? Icons.location_on_outlined : Icons.home_work_outlined),
            title: Text(row.label), subtitle: Text(row.kind), onTap: () => _submit(row.label, suggestion: row)),
          const SizedBox(height: 12),
          Row(children: [Expanded(child: OutlinedButton(onPressed: () => _submit(''), child: const Text('مسح البحث'))),
            const SizedBox(width: 10), Expanded(flex: 2, child: FilledButton.icon(key: const ValueKey('discovery-search-submit'),
              onPressed: () => _submit(_controller.text), icon: const Icon(Icons.search), label: const Text('عرض النتائج')))]),
        ])))));
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
    final scheme = Theme.of(context).colorScheme;
    return Container(decoration: BoxDecoration(color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: selected ? scheme.primary : EbrokerDesign.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        EbrokerPropertyHorizontalCard(embedded: true, title: property.title,
          price: _formatPrice(property.purpose == 'rent' ? property.monthlyRent ?? property.price : property.price), currency: _currencyLabel(property.currency),
          priceSuffix: property.purpose == 'rent' && property.monthlyRent != null ? 'شهريًا' : null,
          imageUrl: property.mainImage, imageUrls: property.imageUrls, isSpotlight: property.isSpotlight,
          location: property.address ?? '${property.distanceKm.toStringAsFixed(1)} كم من مركز البحث',
          categoryLabel: _typeLabel(property.type ?? ''),
          purposeLabel: property.purpose == 'rent' ? 'للإيجار' : 'للبيع',
          onTap: onDetails,
          action: PropertyCompareAction(propertyId: property.id),
          trailing:
            IconButton(tooltip: favorite ? 'إزالة من المفضلة' : 'حفظ في المفضلة', onPressed: onFavorite,
              style: IconButton.styleFrom(backgroundColor: Colors.white, minimumSize: const Size(44,44), shape: const CircleBorder()),
              icon: Icon(favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, size: 19, color: scheme.secondary))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: _PropertyFacts(property: property)),
        TextButton.icon(onPressed: onMap,
          icon: EbrokerImage('location', size: 18, color: scheme.primary),
          label: const Text('عرض على الخريطة')),
      ]));
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
        EbrokerIcon(icon, size: 16, color: EbrokerDesign.textLight),
        const SizedBox(width: 4),
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: EbrokerDesign.textLight,
              ),
        ),
      ],
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
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EbrokerDesign.border),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 118,
            decoration: BoxDecoration(
              color: AppTheme.brandSoft,
              borderRadius: BorderRadius.circular(8),
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
            EbrokerIcon(icon, size: 48, color: EbrokerDesign.textLight),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center),
            if (buttonLabel != null && onPressed != null) ...[
              const SizedBox(height: 14),
              EbrokerFilledButton.tonal(
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


class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 4,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            EbrokerIcon(
              Icons.info_outline,
              color: AppTheme.accent,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

String _typeLabel(String value) {
  switch (value) {
    case 'floor':
      return 'دور كامل';
    case 'building':
      return 'عمارة كاملة';
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

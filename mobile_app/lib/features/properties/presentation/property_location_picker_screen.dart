import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/platform/app_permission_settings.dart';
import '../../map/domain/map_screen_coordinate_space.dart';
import '../domain/property_location_address.dart';
import '../domain/property_coordinates.dart';
import '../data/property_repository.dart';

typedef PropertyLocationPicker = Future<PropertyLocationSelection?> Function(
  BuildContext context, {double? initialLatitude, double? initialLongitude});

final propertyLocationPickerProvider = Provider<PropertyLocationPicker>((ref) =>
  (context, {initialLatitude, initialLongitude}) => Navigator.of(context).push<PropertyLocationSelection>(
    MaterialPageRoute<PropertyLocationSelection>(builder: (_) => PropertyLocationPickerScreen(
      initialLatitude: initialLatitude, initialLongitude: initialLongitude,
      reverseLookup: (latitude, longitude) => ref.read(propertyRepositoryProvider)
        .resolveLocationAddress(latitude: latitude, longitude: longitude)))));

typedef PropertyCurrentLocation = Future<PropertyLocationSelection> Function();
final propertyCurrentLocationProvider = Provider<PropertyCurrentLocation>((ref) => () async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw PlatformException(code: 'LOCATION_DISABLED', message: 'فعّل خدمة الموقع أو حدد النقطة على الخريطة.');
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied || permission == LocationPermission.unableToDetermine) {
    permission = await Geolocator.requestPermission();
  }
  if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) {
    throw PlatformException(code: permission==LocationPermission.deniedForever ? 'LOCATION_DENIED_FOREVER':'LOCATION_DENIED',
      message: permission==LocationPermission.deniedForever ? 'إذن الموقع مرفوض نهائيًا. افتح الإعدادات أو اختر النقطة يدويًا على الخريطة.' : 'لم يُمنح إذن الموقع. يمكنك تحديد النقطة على الخريطة.');
  }
  final position = await Geolocator.getCurrentPosition(locationSettings:
    const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 12)));
  if (!hasValidPropertyCoordinates(position.latitude, position.longitude)) {
    throw PlatformException(code: 'LOCATION_UNAVAILABLE', message: 'تعذر تحديد نقطة صالحة. اختر موقع العقار يدويًا.');
  }
  return PropertyLocationSelection(latitude: position.latitude, longitude: position.longitude);
});

class PropertyLocationSelection {
  const PropertyLocationSelection({
    required this.latitude,
    required this.longitude,
    this.address = const PropertyLocationAddress(),
  });

  final double latitude;
  final double longitude;
  final PropertyLocationAddress address;
}

class PropertyLocationPickerScreen extends ConsumerStatefulWidget {
  const PropertyLocationPickerScreen({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    this.reverseLookup,
    this.title = 'تحديد موقع العقار',
  });

  final double? initialLatitude;
  final double? initialLongitude;
  final String title;
  final Future<PropertyLocationAddress> Function(
    double latitude,
    double longitude,
  )? reverseLookup;

  @override
  ConsumerState<PropertyLocationPickerScreen> createState() =>
      _PropertyLocationPickerScreenState();
}

class _PropertyLocationPickerScreenState
    extends ConsumerState<PropertyLocationPickerScreen> {
  static const _fallback = LatLng(15.3694, 44.1910);
  static const _mapStyle = 'https://tiles.openfreemap.org/styles/liberty';

  final GlobalKey _mapStackKey = GlobalKey();
  MapLibreMapController? _controller;
  late LatLng _selection;
  Offset? _pinOffset;
  bool _styleLoaded = false;
  bool _draggingPin = false;
  bool _resolving = false;
  bool _styleFailed = false, _needsSettings = false, _locationDisabled = false, _locating = false;
  int _mapAttempt = 0;
  Timer? _mapTimeout;
  String? _message;

  @override
  void initState() {
    super.initState();
    final latitude = widget.initialLatitude;
    final longitude = widget.initialLongitude;
    _selection = hasValidPropertyCoordinates(latitude, longitude)
        ? LatLng(latitude!, longitude!)
        : _fallback;
    _startMapTimeout();
  }

  void _startMapTimeout() {
    _mapTimeout?.cancel();
    _mapTimeout=Timer(const Duration(seconds:25),() {
      if(mounted && !_styleLoaded) setState(()=>_styleFailed=true);
    });
  }
  void _retryMap() {
    setState(() { _mapAttempt++;_styleLoaded=false;_styleFailed=false;_controller=null; });
    _startMapTimeout();
  }
  @override
  void dispose() { _mapTimeout?.cancel();super.dispose(); }

  void _onMapCreated(MapLibreMapController controller) {
    _controller = controller;
  }

  void _onStyleLoaded() {
    if (!mounted) return;
    _mapTimeout?.cancel();
    setState(() {
      _styleLoaded = true;
      _styleFailed = false;
      _message = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncPinToSelection());
  }

  Future<void> _syncPinToSelection() async {
    final controller = _controller;
    final box = _mapStackKey.currentContext?.findRenderObject();
    if (!_styleLoaded || controller == null || box is! RenderBox) return;
    try {
      final point = await controller.toScreenLocation(_selection);
      if (!mounted) return;
      final size = box.size;
      final logicalPoint = MapScreenCoordinateSpace.platformPixelsToLogical(
        point,
        MediaQuery.devicePixelRatioOf(context),
      );
      setState(() {
        _pinOffset = Offset(
          logicalPoint.dx.clamp(30.0, size.width - 30.0).toDouble(),
          logicalPoint.dy.clamp(64.0, size.height - 132.0).toDouble(),
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _pinOffset = null);
    }
  }

  void _onCameraIdle() {
    if (_draggingPin) return;
    final camera = _controller?.cameraPosition;
    if (!mounted || camera == null) return;
    setState(() {
      _selection = camera.target;
      _pinOffset = null;
    });
  }

  Offset _pinForSize(Size size) {
    return _pinOffset ?? Offset(size.width / 2, size.height / 2);
  }

  void _moveDraggedPin(DragUpdateDetails details, Size size) {
    final box = _mapStackKey.currentContext?.findRenderObject();
    if (box is! RenderBox) return;
    final local = box.globalToLocal(details.globalPosition);
    setState(() {
      _draggingPin = true;
      _pinOffset = Offset(
        local.dx.clamp(30.0, size.width - 30.0).toDouble(),
        local.dy.clamp(64.0, size.height - 132.0).toDouble(),
      );
    });
  }

  Future<void> _commitDraggedPin(Size size) async {
    final controller = _controller;
    final pin = _pinForSize(size);
    if (controller == null) return;
    try {
      final location = await controller.toLatLng(
        MapScreenCoordinateSpace.logicalToPlatformPixels(
          pin,
          MediaQuery.devicePixelRatioOf(context),
        ),
      );
      if (!mounted) return;
      setState(() {
        _selection = location;
        _draggingPin = false;
        _message = 'تم نقل الدبوس. يمكنك سحبه مرة أخرى أو تحريك الخريطة.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _draggingPin = false;
        _message = 'تعذر تثبيت الدبوس في هذا الموضع. حاول مرة أخرى.';
      });
    }
  }

  Future<void> _moveToCurrentLocation() async {
    if (_locating) return;
    setState(() { _locating=true;_needsSettings=false;_locationDisabled=false; });
    try {
      final position = await ref.read(propertyCurrentLocationProvider)();
      final location = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() {
        _selection = location;
        _pinOffset = null;
        _message = 'تم الانتقال إلى موقعك الحالي.';
      });
      await _controller
          ?.animateCamera(CameraUpdate.newLatLngZoom(location, 16));
    } on PlatformException catch (error) {
      if (mounted) setState(() {
        _needsSettings = error.code == 'LOCATION_DENIED_FOREVER';
        _locationDisabled = error.code == 'LOCATION_DISABLED';
        _message = error.message ?? 'تعذر تحديد الموقع. يمكنك اختيار النقطة يدويًا.';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'تعذر الحصول على موقع الهاتف الآن.');
      }
    } finally { if(mounted)setState(()=>_locating=false); }
  }

  Future<void> _confirm() async {
    if (_resolving) return;
    final selection = _selection;
    setState(() {
      _resolving = true;
      _message = 'جارٍ قراءة المحافظة والحي والشارع…';
    });

    var address = const PropertyLocationAddress();
    final lookup = widget.reverseLookup;
    if (lookup != null) {
      try {
        address = await lookup(selection.latitude, selection.longitude)
          .timeout(const Duration(seconds: 4));
      } catch (_) {
        address = const PropertyLocationAddress();
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop(
      PropertyLocationSelection(
        latitude: selection.latitude,
        longitude: selection.longitude,
        address: address,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          centerTitle: true,
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            final pin = _pinForSize(size);
            return Stack(
              key: _mapStackKey,
              children: [
                Positioned.fill(
                  child: MapLibreMap(
                    key:ValueKey(_mapAttempt),
                    styleString: _mapStyle,
                    initialCameraPosition:
                        CameraPosition(target: _selection, zoom: 15),
                    onMapCreated: _onMapCreated,
                    onStyleLoadedCallback: _onStyleLoaded,
                    onCameraIdle: _onCameraIdle,
                    trackCameraPosition: true,
                    minMaxZoomPreference: const MinMaxZoomPreference(3, 19),
                    rotateGesturesEnabled: false,
                    tiltGesturesEnabled: false,
                  ),
                ),
                PositionedDirectional(
                  start: 14,
                  end: 14,
                  top: 14,
                  child: IgnorePointer(
                    child: Card(
                      elevation: 3,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            const EbrokerIcon(Icons.location_on_rounded,
                                color: AppTheme.brand),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _styleLoaded
                                    ? 'اسحب الدبوس إلى العقار، أو حرّك الخريطة ليعود الدبوس إلى المنتصف.'
                                    : _styleFailed ? 'تعذر تحميل الخريطة. أعد المحاولة عند توفر الشبكة.' : 'جارٍ تحميل الخريطة…',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (_styleFailed) Positioned.fill(child:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(24),
                  child:Card(child:Padding(padding:const EdgeInsets.all(20),child:Column(mainAxisSize:MainAxisSize.min,children:[
                    const Text('لن يتغير موقع العقار حتى تؤكد اختيارك. يمكنك الرجوع أو إعادة تحميل الخريطة.'),
                    TextButton.icon(onPressed:_retryMap,icon:const Icon(Icons.refresh),label:const Text('إعادة تحميل الخريطة')),
                  ])))))),
                if (_styleLoaded) ...[
                  Positioned(
                    left: pin.dx - 24,
                    top: pin.dy - 24,
                    child: IgnorePointer(
                      child: EbrokerIcon(
                        Icons.center_focus_strong,
                        size: 48,
                        color: AppTheme.brand.withValues(alpha: 0.38),
                      ),
                    ),
                  ),
                  Positioned(
                    left: pin.dx - 31,
                    top: pin.dy - 62,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (_) => setState(() => _draggingPin = true),
                      onPanUpdate: (details) => _moveDraggedPin(details, size),
                      onPanEnd: (_) => _commitDraggedPin(size),
                      child: Container(
                        width: 62,
                        height: 68,
                        alignment: Alignment.topCenter,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.96),
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(
                              blurRadius: 10,
                              offset: Offset(0, 4),
                              color: Color(0x33000000),
                            ),
                          ],
                        ),
                        child: const Padding(
                          padding: EdgeInsets.only(top: 5),
                          child: EbrokerIcon(
                            Icons.location_on_rounded,
                            size: 52,
                            color: Color(0xFFD84332),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                PositionedDirectional(
                  end: 14,
                  bottom: 150,
                  child: FloatingActionButton.small(
                    heroTag: 'property-picker-current-location',
                    tooltip: 'موقعي الحالي',
                    onPressed: _styleLoaded && !_locating ? _moveToCurrentLocation : null,
                    child: const EbrokerIcon(Icons.my_location_rounded),
                  ),
                ),
                PositionedDirectional(
                  start: 14,
                  end: 14,
                  bottom: 18,
                  child: SafeArea(
                    top: false,
                    child: Card(
                      elevation: 5,
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_needsSettings) TextButton(onPressed: () => ref.read(appPermissionSettingsProvider)(), child: const Text('فتح إعدادات الإذن')),
                            if (_locationDisabled) TextButton(onPressed: () => ref.read(locationServiceSettingsProvider)(), child: const Text('تفعيل خدمة الموقع')),
                            if (_message != null) ...[
                              Text(
                                _message!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                            ] else
                              const Text(
                                'بعد التأكيد سنحاول تعبئة المحافظة والحي والشارع تلقائياً، ويمكنك تعديلها.',
                                textAlign: TextAlign.center,
                              ),
                            EbrokerFilledButton.icon(
                              onPressed:
                                  _styleLoaded && !_resolving ? _confirm : null,
                              icon: _resolving
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const EbrokerIcon(Icons.check_circle_outline),
                              label: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                child: Text(
                                  _resolving
                                      ? 'جارٍ قراءة العنوان…'
                                      : 'تأكيد هذا الموقع',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}


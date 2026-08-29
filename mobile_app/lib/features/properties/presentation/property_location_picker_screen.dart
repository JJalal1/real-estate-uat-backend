import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/theme/app_theme.dart';
import '../../map/domain/map_screen_coordinate_space.dart';
import '../domain/property_location_address.dart';

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

class PropertyLocationPickerScreen extends StatefulWidget {
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
  State<PropertyLocationPickerScreen> createState() =>
      _PropertyLocationPickerScreenState();
}

class _PropertyLocationPickerScreenState
    extends State<PropertyLocationPickerScreen> {
  static const _fallback = LatLng(15.3694, 44.1910);
  static const _mapStyle = 'https://tiles.openfreemap.org/styles/liberty';

  final GlobalKey _mapStackKey = GlobalKey();
  MapLibreMapController? _controller;
  late LatLng _selection;
  Offset? _pinOffset;
  bool _styleLoaded = false;
  bool _draggingPin = false;
  bool _resolving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    final latitude = widget.initialLatitude;
    final longitude = widget.initialLongitude;
    _selection = latitude != null && longitude != null
        ? LatLng(latitude, longitude)
        : _fallback;
  }

  void _onMapCreated(MapLibreMapController controller) {
    _controller = controller;
  }

  void _onStyleLoaded() {
    if (!mounted) return;
    setState(() {
      _styleLoaded = true;
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
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (mounted) {
          setState(() => _message = 'فعّل خدمة الموقع أو اختر المكان يدوياً.');
        }
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(
              () => _message = 'لم يتم منح إذن الموقع. حرّك الدبوس يدوياً.');
        }
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      final location = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() {
        _selection = location;
        _pinOffset = null;
        _message = 'تم الانتقال إلى موقعك الحالي.';
      });
      await _controller
          ?.animateCamera(CameraUpdate.newLatLngZoom(location, 16));
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'تعذر الحصول على موقع الهاتف الآن.');
      }
    }
  }

  Future<void> _confirm() async {
    if (_resolving) return;
    setState(() {
      _resolving = true;
      _message = 'جارٍ قراءة المحافظة والحي والشارع…';
    });

    var address = const PropertyLocationAddress();
    final lookup = widget.reverseLookup;
    if (lookup != null) {
      try {
        address = await lookup(_selection.latitude, _selection.longitude);
      } catch (_) {
        address = const PropertyLocationAddress();
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop(
      PropertyLocationSelection(
        latitude: _selection.latitude,
        longitude: _selection.longitude,
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
                            const Icon(Icons.location_on_rounded,
                                color: AppTheme.brand),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _styleLoaded
                                    ? 'اسحب الدبوس إلى العقار، أو حرّك الخريطة ليعود الدبوس إلى المنتصف.'
                                    : 'جارٍ تحميل الخريطة…',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (_styleLoaded) ...[
                  Positioned(
                    left: pin.dx - 24,
                    top: pin.dy - 24,
                    child: IgnorePointer(
                      child: Icon(
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
                          child: Icon(
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
                    onPressed: _styleLoaded ? _moveToCurrentLocation : null,
                    child: const Icon(Icons.my_location_rounded),
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
                            FilledButton.icon(
                              onPressed:
                                  _styleLoaded && !_resolving ? _confirm : null,
                              icon: _resolving
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.check_circle_outline),
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

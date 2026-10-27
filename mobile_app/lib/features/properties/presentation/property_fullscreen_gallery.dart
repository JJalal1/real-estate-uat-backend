import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/adaptive_image_policy.dart';
import '../../account/data/auth_controller.dart';
import '../../account/presentation/actor_scoped_page.dart';
import '../domain/property_details.dart';
import 'adaptive_property_photo.dart';

final _galleryGuidanceSeenProvider = StateProvider.family<bool, int?>((ref, actor) => false);

/// Uses the existing private-media and adaptive-resolution pipeline.
class PropertyFullscreenGallery extends ConsumerStatefulWidget {
  const PropertyFullscreenGallery({required this.images, required this.initialIndex,
    this.privateImages = false, super.key});

  final List<PropertyImageItem> images;
  final int initialIndex;
  final bool privateImages;

  @override
  ConsumerState<PropertyFullscreenGallery> createState() => _PropertyFullscreenGalleryState();
}

class _PropertyFullscreenGalleryState extends ConsumerState<PropertyFullscreenGallery> {
  late final PageController _pages;
  late final int? _actor;
  late int _index;
  final _highResolution = <int>{};
  Timer? _hintTimer;
  bool _showHints = false;

  @override
  void initState() {
    super.initState();
    _actor = ref.read(authControllerProvider).asData?.value?.id;
    _index = widget.images.isEmpty ? 0 : widget.initialIndex.clamp(0, widget.images.length - 1).toInt();
    _pages = PageController(initialPage: _index);
    _showHints = !ref.read(_galleryGuidanceSeenProvider(_actor));
    if (_showHints) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(_galleryGuidanceSeenProvider(_actor).notifier).state = true;
      });
      _hintTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _showHints = false);
      });
    }
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky).catchError((Object _) {}));
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _pages.dispose();
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge).catchError((Object _) {}));
    super.dispose();
  }

  void _page(int value) {
    if (!_pages.hasClients || value < 0 || value >= widget.images.length || value == _index) return;
    unawaited(_pages.animateToPage(value, duration: const Duration(milliseconds: 230), curve: Curves.easeOutCubic));
  }

  void _upgrade(int index) {
    if (mounted && index == _index && !_highResolution.contains(index)) {
      setState(() => _highResolution.add(index));
    }
  }

  @override
  Widget build(BuildContext context) {
    final gallery = Directionality(textDirection: TextDirection.rtl, child: Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        if (widget.images.isEmpty)
          const Center(child: Text('لا توجد صور', style: TextStyle(color: Colors.white)))
        else
          PageView.builder(key: const ValueKey('fullscreen-gallery-pages'), controller: _pages,
            // InteractiveViewer owns the gesture. Base-scale one-finger swipes
            // page explicitly; a pinch or zoomed pan never reaches the pager.
            physics: const NeverScrollableScrollPhysics(), itemCount: widget.images.length,
            onPageChanged: (value) => setState(() => _index = value),
            itemBuilder: (context, index) => _GalleryZoomSurface(
              key: ValueKey(widget.images[index].id), active: index == _index,
              onZoom: () => _upgrade(index), onSwipe: (forward) => _page(_index + (forward ? 1 : -1)),
              child: Semantics(image: true, label: 'صورة العقار ${index + 1} من ${widget.images.length}',
                child: SizedBox.expand(child: AdaptivePropertyPhoto(key: ValueKey('gallery-photo-${widget.images[index].id}'),
                  url: widget.images[index].zoomUrl, authenticated: widget.privateImages, fit: BoxFit.contain,
                  use: _highResolution.contains(index) ? PropertyImageUse.zoom : PropertyImageUse.fullscreen))),
            )),
        Positioned(top: 0, left: 0, right: 0, child: SafeArea(bottom: false,
          child: Padding(padding: const EdgeInsets.all(8), child: Row(children: [
            IconButton.filled(key: const ValueKey('gallery-close'), tooltip: 'إغلاق الصور',
              onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
            Expanded(child: Center(child: Semantics(
              label: 'الصورة', value: '${widget.images.isEmpty ? 0 : _index + 1} من ${widget.images.length}',
              increasedValue: _index + 1 < widget.images.length ? '${_index + 2} من ${widget.images.length}' : null,
              decreasedValue: _index > 0 ? '$_index من ${widget.images.length}' : null,
              onIncrease: _index + 1 < widget.images.length ? () => _page(_index + 1) : null,
              onDecrease: _index > 0 ? () => _page(_index - 1) : null,
              child: Container(key: const ValueKey('gallery-counter'),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: .3), borderRadius: BorderRadius.circular(24)),
                child: Text('${widget.images.isEmpty ? 0 : _index + 1}/${widget.images.length}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
            ))),
            IconButton.filledTonal(tooltip: 'تحميل صورة أوضح',
              onPressed: widget.images.isEmpty || _highResolution.contains(_index) ? null : () => _upgrade(_index),
              icon: const Icon(Icons.hd_outlined)),
          ])))),
        Positioned(bottom: 0, left: 16, right: 16, child: SafeArea(top: false,
          child: Padding(padding: const EdgeInsets.only(bottom: 18), child: IgnorePointer(
            child: AnimatedOpacity(opacity: _showHints ? 1 : 0, duration: const Duration(milliseconds: 200),
              child: Center(child: Container(key: const ValueKey('gallery-guidance'),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(28), border: Border.all(color: Colors.white.withValues(alpha: .14))),
                child: LayoutBuilder(builder: (context, bounds) => Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 6,
                  children: [
                    _hint(bounds.maxWidth, Icons.swipe_rounded, 'اسحب للتنقل'),
                    _hint(bounds.maxWidth, Icons.touch_app_outlined, 'اضغط مرتين للتكبير'),
                  ])),
              )),
            ),
          )),
        )),
      ]),
    ));
    if (!widget.privateImages) return gallery;
    if (_actor == null) {
      return Scaffold(appBar: AppBar(title: const Text('صور العقار')),
        body: const Center(child: Text('سجّل الدخول ثم أعد فتح الصور من حسابك.')));
    }
    return ActorBoundPage(title: 'صور العقار', actorId: _actor, builder: (_) => gallery);
  }

  Widget _hint(double width, IconData icon, String text) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: width), child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 17, color: Colors.white70), const SizedBox(width: 5),
      Flexible(child: Text(text, style: const TextStyle(fontSize: 11, color: Colors.white70))),
    ]));
}

class _GalleryZoomSurface extends StatefulWidget {
  const _GalleryZoomSurface({required this.child, required this.active, required this.onZoom, required this.onSwipe, super.key});
  final Widget child;
  final bool active;
  final VoidCallback onZoom;
  final ValueChanged<bool> onSwipe;
  @override
  State<_GalleryZoomSurface> createState() => _GalleryZoomSurfaceState();
}

class _GalleryZoomSurfaceState extends State<_GalleryZoomSurface> with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  late final AnimationController _animation;
  Matrix4Tween? _matrix;
  Offset _tap = Offset.zero, _start = Offset.zero, _last = Offset.zero;
  bool _zoomed = false, _multitouch = false, _startedZoomed = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_transformed);
    _animation = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))
      ..addListener(() { if (_matrix != null) _transform.value = _matrix!.transform(Curves.easeOutCubic.transform(_animation.value)); });
  }

  void _transformed() {
    final scale = _transform.value.getMaxScaleOnAxis();
    final zoomed = scale > 1.015;
    if (zoomed != _zoomed && mounted) setState(() => _zoomed = zoomed);
    if (scale > 1.15 && widget.active) widget.onZoom();
  }

  @override
  void didUpdateWidget(_GalleryZoomSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      _animation.stop();
      _transform.value = Matrix4.identity();
      _multitouch = false;
    }
  }

  void _doubleTap() {
    if (!widget.active) return;
    _animation.stop();
    final scene = _transform.toScene(_tap);
    const scale = 2.5;
    final target = _zoomed ? Matrix4.identity() : (Matrix4.identity()
      ..translate(_tap.dx - scene.dx * scale, _tap.dy - scene.dy * scale)
      ..scale(scale));
    if (MediaQuery.disableAnimationsOf(context)) { _transform.value = target; return; }
    _matrix = Matrix4Tween(begin: _transform.value.clone(), end: target);
    _animation.forward(from: 0);
  }

  void _interactionStarted(ScaleStartDetails details) {
    _animation.stop();
    _start = _last = details.localFocalPoint;
    _startedZoomed = _zoomed;
    _multitouch = details.pointerCount > 1;
  }

  void _interactionUpdated(ScaleUpdateDetails details) {
    _last = details.localFocalPoint;
    if (details.pointerCount > 1 || details.scale > 1.015 || details.scale < .985) _multitouch = true;
  }

  void _interactionEnded(ScaleEndDetails details) {
    if (!widget.active || _multitouch || _startedZoomed || _zoomed) return;
    final delta = _last - _start;
    if (delta.dx.abs() < 48 || delta.dx.abs() < delta.dy.abs() * 1.25) return;
    widget.onSwipe(Directionality.of(context) == TextDirection.rtl ? delta.dx > 0 : delta.dx < 0);
  }

  @override
  void dispose() {
    _animation.dispose();
    _transform.removeListener(_transformed);
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(behavior: HitTestBehavior.opaque,
    onDoubleTapDown: (details) => _tap = details.localPosition,
    onDoubleTap: _doubleTap,
    child: InteractiveViewer(transformationController: _transform, minScale: 1, maxScale: 4,
      panEnabled: _zoomed, onInteractionStart: _interactionStarted,
      onInteractionUpdate: _interactionUpdated, onInteractionEnd: _interactionEnded,
      child: widget.child));
}

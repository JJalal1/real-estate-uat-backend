import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A fixed-size media slot may be laid out in a scroll cache or hidden tab.
/// Mount its network child only while it intersects every ancestor viewport.
/// Completed bytes remain in the existing session cache; unmounting releases
/// the last lease and cancels an unfinished transfer.
class ViewportMedia extends StatefulWidget {
  const ViewportMedia({required this.builder, this.placeholder, super.key});
  final WidgetBuilder builder;
  final Widget? placeholder;

  @override
  State<ViewportMedia> createState() => _ViewportMediaState();
}

class _ViewportMediaState extends State<ViewportMedia> with WidgetsBindingObserver {
  final _positions = <ScrollPosition>{};
  bool _visible = false, _scheduled = false, _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Register inherited dependencies as well as both axes of nested lists.
    TickerMode.of(context);
    ModalRoute.of(context);
    MediaQuery.sizeOf(context);
    Scrollable.maybeOf(context);
    final next = <ScrollPosition>{};
    context.visitAncestorElements((element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        next.add((element.state as ScrollableState).position);
      }
      return true;
    });
    for (final position in _positions.difference(next)) {
      position.removeListener(_schedule);
    }
    for (final position in next.difference(_positions)) {
      position.addListener(_schedule);
    }
    _positions..clear()..addAll(next);
    _schedule();
  }

  @override
  void didUpdateWidget(ViewportMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;
    _schedule();
    WidgetsBinding.instance.scheduleFrame();
  }

  void _schedule() {
    if (_scheduled || !mounted) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final visible = _intersectsViewport();
      if (visible != _visible) setState(() => _visible = visible);
    });
  }

  bool _intersectsViewport() {
    if (!_foreground || !TickerMode.of(context)) return false;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize || box.size.isEmpty) return false;
    final rect = MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);
    var clip = Offset.zero & MediaQuery.sizeOf(context);
    RenderObject child = box;
    RenderObject? parent = box.parent;
    while (parent != null) {
      if (parent is RenderOffstage && parent.offstage) return false;
      if (parent is RenderOpacity && parent.opacity == 0) return false;
      if (parent is RenderIndexedStack) {
        RenderBox? selected = parent.firstChild;
        final index = parent.index;
        if (index == null) return false;
        for (var i = 0; i < index && selected != null; i++) {
          selected = parent.childAfter(selected);
        }
        if (!identical(child, selected)) return false;
      }
      if (parent is RenderAbstractViewport || parent is RenderClipRect || parent is RenderClipRRect) {
        final bounds = MatrixUtils.transformRect(parent.getTransformTo(null), parent.paintBounds);
        clip = clip.intersect(bounds);
      }
      child = parent;
      parent = parent.parent;
    }
    final intersection = rect.intersect(clip);
    return intersection.width > 0 && intersection.height > 0;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final position in _positions) { position.removeListener(_schedule); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _MediaGeometryObserver(onLayout: _schedule,
    child: _visible ? widget.builder(context) : LayoutBuilder(builder: (_, bounds) =>
      widget.placeholder ?? SizedBox(width: bounds.hasBoundedWidth ? bounds.maxWidth : 96,
        height: bounds.hasBoundedHeight ? bounds.maxHeight : 96,
        child: const ExcludeSemantics(child: SizedBox.shrink()))));
}

class _MediaGeometryObserver extends SingleChildRenderObjectWidget {
  const _MediaGeometryObserver({required this.onLayout, required super.child});
  final VoidCallback onLayout;
  @override
  RenderObject createRenderObject(BuildContext context) => _MediaGeometry(onLayout);
  @override
  void updateRenderObject(BuildContext context, _MediaGeometry renderObject) { renderObject.onLayout = onLayout; }
}

class _MediaGeometry extends RenderProxyBox {
  _MediaGeometry(this.onLayout);
  VoidCallback onLayout;
  @override
  void performLayout() { super.performLayout(); onLayout(); }
  @override
  void paint(PaintingContext context, Offset offset) { onLayout(); super.paint(context, offset); }
}

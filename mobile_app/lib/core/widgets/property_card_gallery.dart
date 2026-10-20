import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_components.dart';
import 'ebroker_widgets.dart';

class PropertyCardGallery extends StatefulWidget {
  const PropertyCardGallery({this.imageUrl, this.imageUrls = const [], this.height = 190,
    this.overlay, this.priceBadge, this.isSpotlight = false, this.propertyType, super.key});
  final String? imageUrl;
  final String? propertyType;
  final List<String> imageUrls;
  final double height;
  final Widget? overlay;
  final Widget? priceBadge;
  final bool isSpotlight;
  @override
  State<PropertyCardGallery> createState() => _PropertyCardGalleryState();
}

class _PropertyCardGalleryState extends State<PropertyCardGallery> {
  final _controller = PageController();
  int _index = 0;
  List<String> get _urls => <String>{if (widget.imageUrl?.isNotEmpty == true) widget.imageUrl!,
    ...widget.imageUrls.where((url) => url.isNotEmpty)}.take(12).toList(growable: false);

  @override
  void didUpdateWidget(PropertyCardGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl || !listEquals(oldWidget.imageUrls, widget.imageUrls)) {
      _index = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted && _controller.hasClients) _controller.jumpToPage(0); });
    }
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, size) {
    final urls = _urls;
    final pixels = (size.maxWidth * MediaQuery.devicePixelRatioOf(context)).round().clamp(128, 1080).toInt();
    return SizedBox(height: widget.height, child: Stack(fit: StackFit.expand, children: [
      if (urls.length < 2) AppPropertyMedia(imageUrl: urls.isEmpty ? null : urls.first, height: widget.height, cacheWidth: pixels, propertyType: widget.propertyType)
      else PageView.builder(key: const ValueKey('property-card-gallery'), controller: _controller,
        itemCount: urls.length, allowImplicitScrolling: false,
        onPageChanged: (index) => setState(() => _index = index),
        itemBuilder: (_, index) => Semantics(label: 'صورة العقار ${index + 1} من ${urls.length}', image: true,
          child: AppPropertyMedia(imageUrl: urls[index], height: widget.height, cacheWidth: pixels, propertyType: widget.propertyType))),
      if (urls.length > 1) PositionedDirectional(bottom: widget.priceBadge == null ? 8 : null,
        top: widget.priceBadge == null ? null : 8, start: 8, end: widget.priceBadge == null ? 8 : null, child: IgnorePointer(child: Row(
        mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: .30), borderRadius: BorderRadius.circular(20)),
            child: urls.length <= 6 ? Row(mainAxisSize: MainAxisSize.min, children: [for (var i = 0; i < urls.length; i++)
              Container(key: ValueKey('photo-dot-$i'), margin: const EdgeInsets.symmetric(horizontal: 2.5),
                width: i == _index ? 12 : 5, height: 5,
                decoration: BoxDecoration(color: i == _index ? Colors.white : Colors.white70, borderRadius: BorderRadius.circular(4))),
            ]) : Text('${_index + 1}/${urls.length}', style: const TextStyle(color: Colors.white, fontSize: 11))),
        ]))),
      if (widget.isSpotlight) PositionedDirectional(bottom: 8,
        start: widget.priceBadge != null && Directionality.of(context) == TextDirection.ltr ? 8 : null,
        end: widget.priceBadge == null || Directionality.of(context) == TextDirection.rtl ? 8 : null,
        child: Tooltip(message: 'إعلان مميز', child: Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: .94), borderRadius: BorderRadius.circular(6)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [EbrokerIcon(Icons.auto_awesome_outlined, size: 13, color: Theme.of(context).colorScheme.primary),
            if (size.maxWidth > 180) ...[const SizedBox(width: 3), Text('مميز', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary))],
          ])))),
      if (widget.overlay != null) PositionedDirectional(top: 4, end: 4, child: widget.overlay!),
      if (widget.priceBadge != null) Positioned(bottom: 8, right: 8,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: size.maxWidth - (widget.isSpotlight ? 68 : 16)), child: widget.priceBadge!)),
    ]));
  });
}


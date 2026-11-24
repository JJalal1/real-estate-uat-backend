import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../core/widgets/app_components.dart';
import '../../discovery/domain/smart_search_filters.dart';
import '../../properties/domain/property_marker.dart';
import '../../../core/widgets/ebroker_property_card.dart';
import '../../properties/presentation/property_favorite_status.dart';
import '../../discovery/presentation/search_result_pagination.dart';

const mapRentColor = Color(0xff147d92);
const mapSaleColor = Color(0xff0b8a55);

double compactMapResultsHeaderHeight(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  return math.max(48.0, scaler.scale(15) * 1.6 + 12) + MediaQuery.paddingOf(context).bottom;
}

/// The map and this list receive the same immutable result snapshot. Its
/// controller resizes first, then scrolls, without rebuilding the native map.
class PropertyMapResultsSheet extends StatefulWidget {
  const PropertyMapResultsSheet({required this.items, required this.itemBuilder,
    this.selectedId, this.markerSelection = 0, this.loading = false, this.staleResults = false, this.error, this.onRetry, this.onShowList,
    this.onMarkerDetails, this.onDismissMarker, this.onAdd, this.total, this.hasDrawnArea = false,
    this.more = false, this.onMore, this.maxExtent = .84, this.collapsed = false, this.filterPanel, super.key});
  final Widget? filterPanel;
  final List<PropertyMarker> items;
  final Widget Function(PropertyMarker property) itemBuilder;
  final int? selectedId;
  final int markerSelection;
  final int? total;
  final bool loading, staleResults, more;
  final bool collapsed, hasDrawnArea;
  final ValueChanged<PropertyMarker>? onMarkerDetails;
  final VoidCallback? onDismissMarker, onAdd;
  final double maxExtent;
  final String? error;
  final VoidCallback? onRetry, onShowList, onMore;
  @override
  State<PropertyMapResultsSheet> createState() => _PropertyMapResultsSheetState();
}

class _PropertyMapResultsSheetState extends State<PropertyMapResultsSheet> {
  final _extent = DraggableScrollableController();
  final _filterPanelKey = GlobalKey();
  ScrollController? _scroll;
  double _minimum = .14, _initial = .29, _maximum = .84;
  bool _expanded = true;
  bool _extentUpdateQueued = false;
  bool _keyboardVisible = false;
  @override
  void initState() {
    super.initState();
    _expanded = !widget.collapsed;
    _extent.addListener(_extentChanged);
  }
  void _syncKeyboard(BuildContext context) {
    // Scaffold already removes the bottom MediaQuery inset from its body.
    // LayoutBuilder runs again when its usable height changes; read the View.
    final visible = View.of(context).viewInsets.bottom > 0;
    if (visible && !_keyboardVisible && widget.filterPanel != null) {
      // Opening the keyboard follows an explicit field focus. Make room for
      // that input while keeping the map strip; criteria updates never resize.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _keyboardVisible && _extent.isAttached) {
          _extent.animateTo(_maximum, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
        }
      });
    }
    _keyboardVisible = visible;
  }
  void _extentChanged() {
    if (!mounted || !_extent.isAttached || _extentUpdateQueued) return;
    _extentUpdateQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _extentUpdateQueued = false;
      if (!mounted || !_extent.isAttached) return;
      final expanded = _extent.size > _minimum + .04;
      if (_expanded != expanded) setState(() => _expanded = expanded);
    });
  }
  void _toggleExtent() {
    if (!_extent.isAttached) return;
    FocusScope.of(context).unfocus();
    _extent.animateTo(_expanded ? _minimum : _initial,
      duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
  }
  void _dragHeader(double delta, double height) {
    if (!_extent.isAttached || height <= 0) return;
    FocusScope.of(context).unfocus();
    _extent.jumpTo((_extent.size - delta / height).clamp(_minimum, _maximum).toDouble());
  }
  void _snapHeader(double velocity) {
    if (!_extent.isAttached) return;
    final points = <double>{_minimum, _initial, _maximum}.toList()..sort();
    final target = velocity.abs() > 500 ? (velocity < 0 ? _maximum : _minimum)
      : points.reduce((a, b) => (a - _extent.size).abs() <= (b - _extent.size).abs() ? a : b);
    _extent.animateTo(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
  }
  @override
  void didUpdateWidget(PropertyMapResultsSheet old) {
    super.didUpdateWidget(old);
    if (widget.collapsed != old.collapsed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _extent.isAttached) {
          _extent.animateTo(widget.collapsed ? _minimum : _initial,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic);
        }
      });
    }
    if (widget.onMarkerDetails == null && widget.selectedId != null &&
        (widget.selectedId != old.selectedId || widget.markerSelection != old.markerSelection)) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        if (_extent.isAttached && _extent.size < .5) {
          try {
            await _extent.animateTo(.5.clamp(_minimum, _maximum).toDouble(),
              duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
          } catch (_) { return; }
        }
        if (!mounted || _scroll?.hasClients != true) return;
        final offset = widget.filterPanel == null ? 0.0 : _filterPanelKey.currentContext?.size?.height ?? 0.0;
        _scroll!.jumpTo(offset.clamp(0.0, _scroll!.position.maxScrollExtent).toDouble());
      });
    }
  }
  @override
  void dispose() { _extent.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, bounds) => _sheet(context, bounds.maxHeight));

  Widget _sheet(BuildContext context, double height) {
    _syncKeyboard(context);
    final compact = widget.collapsed && widget.filterPanel == null;
    _maximum = widget.filterPanel == null ? widget.maxExtent
      : (1 - 70 / (height > 0 ? height : 1)).clamp(.14, widget.maxExtent).toDouble();
    final titleStyle = Theme.of(context).textTheme.titleSmall;
    final titleHeight = MediaQuery.textScalerOf(context).scale(titleStyle?.fontSize ?? 16) * (titleStyle?.height ?? 1.4);
    final countHeight = titleHeight * (_keyboardVisible ? 1 : 2);
    final headerHeight = compact ? compactMapResultsHeaderHeight(context) : 40 + math.max(countHeight, 48);
    _minimum = (headerHeight / math.max(height, 1)).clamp(compact ? .0 : .14, _maximum).toDouble();
    final openExtent = compact ? .55 : widget.filterPanel == null ? .29 : .55;
    _initial = openExtent.clamp(_minimum, _maximum).toDouble();
    final selected = widget.items.where((row) => row.id == widget.selectedId);
    final ranked = widget.items.any((row) => row.discoveryMatch != null);
    final rows = ranked ? widget.items : [...selected, ...widget.items.where((row) => row.id != widget.selectedId)];
    final countLabel = compact ? '${arabicDigits('${widget.total ?? rows.length}')} نتيجة'
      : widget.staleResults ? '${rows.length} عقار من آخر تحميل'
      : '${rows.length}${widget.more ? '+' : ''} ${ranked ? 'نتيجة' : 'عقار في النطاق'}';
    final sheet = DraggableScrollableSheet(key: const ValueKey('map-results-sheet'),
      controller: _extent, initialChildSize: widget.collapsed ? _minimum : _initial, minChildSize: _minimum, maxChildSize: _maximum,
      snap: true, snapSizes: [
        for (final size in (compact ? [_initial] : [_initial, widget.filterPanel == null ? .5 : .75]))
          if (size > _minimum && size < _maximum) size,
      ],
      shouldCloseOnMinExtent: false,
      builder: (context, scroll) {
        _scroll = scroll;
        return Material(key: const ValueKey('map-search-panel-surface'), color: Theme.of(context).colorScheme.surface, elevation: compact ? 3 : 8,
          shadowColor: Theme.of(context).shadowColor.withValues(alpha: .18),
          borderRadius: BorderRadius.vertical(top: Radius.circular(compact ? 13 : 20)), clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: EdgeInsets.only(bottom: compact ? MediaQuery.paddingOf(context).bottom : 0),
            child: Column(children: [
            GestureDetector(behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (details) => _dragHeader(details.primaryDelta ?? 0, height),
              onVerticalDragEnd: (details) => _snapHeader(details.primaryVelocity ?? 0),
              child: compact ? _compactHeader(context, countLabel) :
                Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 0), child: Column(children: [
                Semantics(label: widget.filterPanel == null
                  ? 'اسحب لتوسيع العقارات أو تصغيرها'
                  : 'اسحب لتوسيع الفلاتر والعقارات أو تصغيرها',
                  child: SizedBox(key: const ValueKey('map-results-handle'), height: 24, width: double.infinity,
                    child: Center(child: Container(width: 42, height: 4,
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.outlineVariant, borderRadius: BorderRadius.circular(4)))))),
                Row(children: [Expanded(child: Semantics(liveRegion: widget.staleResults, child: Text(countLabel,
                  key: const ValueKey('map-results-count'), maxLines: _keyboardVisible ? 1 : 2, overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall))),
                  if (widget.loading) const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  if (widget.onShowList != null) IconButton(tooltip: 'عرض القائمة', onPressed: widget.onShowList, icon: const Icon(Icons.view_list_outlined)),
                  if (widget.filterPanel != null) IconButton(key: const ValueKey('map-filter-panel-toggle'),
                    tooltip: _expanded ? 'تصغير الفلاتر' : 'فتح الفلاتر', onPressed: _toggleExtent,
                    icon: Icon(_expanded ? Icons.keyboard_arrow_down : Icons.tune)),
                ]),
              ]))),
            Expanded(child: SearchResultPagination(
              onLoadMore: (ranked || widget.hasDrawnArea) && widget.more && !widget.loading && widget.error == null ? widget.onMore : null,
              child: ListView.builder(key: const ValueKey('map-results-list'), controller: scroll,
              padding: EdgeInsets.fromLTRB(12, 0, 12, 24 + (compact ? 0 : MediaQuery.paddingOf(context).bottom)), cacheExtent: 0,
              itemCount: rows.length + 2,
              itemBuilder: (context, index) {
              if (index == 0) { return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (widget.filterPanel != null) Padding(padding: const EdgeInsets.only(bottom: 12),
                  child: SizedBox(key: _filterPanelKey, child: widget.filterPanel)),
                if (!compact) const Wrap(spacing: 16, runSpacing: 4, children: [
                  _Legend(label: 'للإيجار', color: mapRentColor), _Legend(label: 'للبيع', color: mapSaleColor),
                ]),
                if (widget.loading) const Padding(padding: EdgeInsets.only(top: 8),
                  child: Text('جارٍ تحديث النطاق… النتائج الظاهرة من آخر تحميل متاح.')),
                if (widget.error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [Text(widget.error!),
                    if (rows.isNotEmpty) const Text('هذه آخر نتائج متاحة داخل النطاق؛ أعد المحاولة لتحديثها.'),
                    TextButton(onPressed: widget.onRetry, child: const Text('إعادة المحاولة'))])),
                if (rows.isEmpty && !widget.loading && widget.error == null)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Text(widget.hasDrawnArea
                    ? 'لا توجد إعلانات داخل المنطقة المحددة' : 'لا توجد عقارات مطابقة في هذا النطاق. حرّك الخريطة أو عدّل الفلاتر.')),
                const SizedBox(height: 12),
              ]); }
              if (index > rows.length) { return widget.more && !widget.staleResults ? TextButton(onPressed: widget.loading ? null : widget.onMore,
                child: const Text('المزيد من العقارات')) : const SizedBox.shrink(); }
              final row = rows[index - 1];
              return Semantics(selected: row.id == widget.selectedId, child: Padding(
                key: ValueKey('map-result-${row.id}'), padding: const EdgeInsets.only(bottom: 12),
                child: DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.circular(10),
                  border: Border.all(width: row.id == widget.selectedId ? 2 : 1,
                    color: row.id == widget.selectedId ? Theme.of(context).colorScheme.primary
                      : row.purpose == 'rent' ? mapRentColor : mapSaleColor)),
                  child: widget.itemBuilder(row))));
            }))),
          ])));
      });
    final showPreview = selected.isNotEmpty && widget.onMarkerDetails != null;
    return Stack(fit: StackFit.expand, children: [
      Offstage(offstage: showPreview, child: sheet),
      if (showPreview) Positioned(left: 10, right: 10, bottom: MediaQuery.paddingOf(context).bottom + 8,
        child: ConstrainedBox(constraints: BoxConstraints(maxHeight: height),
          child: SingleChildScrollView(child: _MapMarkerPreview(property: selected.first,
            onTap: () => widget.onMarkerDetails!(selected.first), onDismiss: widget.onDismissMarker)))),
    ]);
  }

  Widget _compactHeader(BuildContext context, String count) {
    final theme = Theme.of(context);
    final showCollapse = widget.onShowList == null && _expanded;
    final toggle = widget.onShowList ?? _toggleExtent;
    final height = compactMapResultsHeaderHeight(context) - MediaQuery.paddingOf(context).bottom;
    return SizedBox(key: const ValueKey('map-results-handle'), height: height,
      child: Row(textDirection: TextDirection.rtl, children: [
        Expanded(child: TextButton.icon(
          key: widget.onShowList == null ? const ValueKey('map-show-list') : const ValueKey('smart-search-list'),
          onPressed: toggle, icon: Icon(showCollapse ? Icons.keyboard_arrow_down : Icons.view_list_outlined, size: 18),
          label: Text(showCollapse ? 'تصغير' : 'قائمة', maxLines: 1),
          style: TextButton.styleFrom(foregroundColor: theme.colorScheme.onSurface, padding: EdgeInsets.zero))),
        const VerticalDivider(width: 1, indent: 9, endIndent: 9),
        Expanded(flex: 2, child: InkWell(onTap: toggle, child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (widget.loading && widget.items.isEmpty)
            const Padding(padding: EdgeInsetsDirectional.only(end: 5), child: SizedBox.square(dimension: 13,
              child: CircularProgressIndicator(strokeWidth: 1.5))),
          Flexible(child: Semantics(liveRegion: true, label: widget.staleResults ? '$count من آخر تحميل' : count,
            excludeSemantics: true, child: Text(count, key: const ValueKey('map-results-count'),
              maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge))),
        ])))),
        if (widget.onAdd != null) const VerticalDivider(width: 1, indent: 9, endIndent: 9),
        Expanded(child: widget.onAdd == null ? const SizedBox.shrink() : TextButton.icon(
          key: const ValueKey('map-broker-add'), onPressed: widget.onAdd, icon: const Icon(Icons.add_circle, size: 18),
          label: const Text('إضافة'), style: TextButton.styleFrom(padding: EdgeInsets.zero))),
      ]));
  }
}

class _MapMarkerPreview extends StatelessWidget {
  const _MapMarkerPreview({required this.property, required this.onTap, this.onDismiss});
  final PropertyMarker property;
  final VoidCallback onTap;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final p = property;
    final theme = Theme.of(context);
    final monthly = p.purpose == 'rent' && p.monthlyRent != null;
    final facts = [
      if (p.areaM2 != null) '${p.areaM2} م²',
      if (p.bedrooms != null) '${p.bedrooms} غرف',
      if (p.bathrooms != null) '${p.bathrooms} حمامات',
    ].join('  ·  ');
    final image = p.mainImage?.isNotEmpty == true ? p.mainImage : p.imageUrls.firstOrNull;
    return Material(key: ValueKey('map-marker-preview-${p.id}'), color: theme.colorScheme.surface,
      elevation: 4, borderRadius: BorderRadius.circular(8), clipBehavior: Clip.antiAlias,
      child: Semantics(button: true, onDismiss: onDismiss, child: InkWell(onTap: onTap,
        child: LayoutBuilder(builder: (context, bounds) {
          final photoWidth = (bounds.maxWidth * .34).clamp(72.0, 145.0).toDouble();
          return Row(textDirection: TextDirection.rtl, children: [
            Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                AppPropertyPrice(price: (monthly ? p.monthlyRent! : p.price).toString(), currency: p.currency,
                  suffix: monthly ? 'شهريًا' : null),
                if (facts.isNotEmpty) Text(arabicDigits(facts), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                if (p.address?.isNotEmpty == true) Text(p.address!, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ]))),
            SizedBox(width: photoWidth, child: AppPropertyMedia(imageUrl: image, propertyType: p.type,
              height: photoWidth, cacheWidth: (MediaQuery.devicePixelRatioOf(context) * photoWidth).round())),
          ]);
        }))));
  }
}

/// Compact public result; it uses the same adaptive media and financial display
/// amount as discovery cards. Larger text grows vertically without hiding actions.
class PropertyMapResultCard extends StatelessWidget {
  const PropertyMapResultCard({required this.property, required this.favorite,
    required this.onFavorite, required this.onMap, required this.onDetails, this.favoriteStatus, super.key});
  final PropertyMarker property;
  final bool favorite;
  final PropertyFavoriteStatus? favoriteStatus;
  final VoidCallback? onFavorite;
  final VoidCallback onMap, onDetails;
  @override
  Widget build(BuildContext context) {
    final p = property;
    final rent = p.purpose == 'rent';
    final monthly = rent && p.monthlyRent != null;
    final status = favoriteStatus ?? PropertyFavoriteStatus.ready(favorite);
    return EbrokerPropertyHorizontalCard(
      title: p.title,
      price: (monthly ? p.monthlyRent! : p.price).toString(),
      currency: p.currency,
      priceSuffix: monthly ? 'شهريًا' : null,
      categoryLabel: SmartSearchFilters.types[p.type] ?? 'عقار',
      purposeLabel: rent ? 'للإيجار' : 'للبيع',
      propertyType: p.type,
      location: p.address,
      imageUrl: p.mainImage,
      imageUrls: p.imageUrls,
      isSpotlight: p.isSpotlight,
      embedded: true,
      onTap: onDetails,
      trailing: Column(mainAxisSize: MainAxisSize.min, children: [
        IconButton(key: ValueKey('map-card-favorite-${p.id}'), tooltip: status.tooltip,
          onPressed: status.loading ? null : onFavorite, icon: Icon(status.icon, color: status.iconColor)),
        IconButton(key: ValueKey('map-card-focus-${p.id}'), tooltip: 'إظهار الموقع',
          onPressed: onMap, icon: const Icon(Icons.location_on_outlined)),
      ]),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 5), Text(label, style: Theme.of(context).textTheme.labelMedium),
  ]);
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/formatters/money.dart';
import '../../discovery/domain/smart_search_filters.dart';
import '../../properties/domain/property_marker.dart';
import '../../../core/widgets/ebroker_property_card.dart';
import '../../properties/presentation/property_favorite_status.dart';
import '../../discovery/presentation/search_result_pagination.dart';

const mapRentColor = AppPalette.sand;
const mapSaleColor = AppPalette.petrol;

double compactMapResultsHeaderHeight(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  return 16 + math.max(41.0, scaler.scale(19) * 1.3) + MediaQuery.paddingOf(context).bottom;
}

/// The map and this list receive the same immutable result snapshot. Its
/// controller resizes first, then scrolls, without rebuilding the native map.
class PropertyMapResultsSheet extends StatefulWidget {
  const PropertyMapResultsSheet({required this.items, required this.itemBuilder,
    this.selectedId, this.markerSelection = 0, this.loading = false, this.staleResults = false, this.error, this.onRetry, this.onShowList,
    this.more = false, this.onMore, this.maxExtent = .84, this.collapsed = false, this.filterPanel, super.key});
  final Widget? filterPanel;
  final List<PropertyMarker> items;
  final Widget Function(PropertyMarker property) itemBuilder;
  final int? selectedId;
  final int markerSelection;
  final bool loading, staleResults, more;
  final bool collapsed;
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
    if (widget.selectedId != null &&
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
    final countLabel = compact ? '${arabicDigits('${rows.length}')} نتيجة'
      : widget.staleResults ? '${rows.length} عقار من آخر تحميل'
      : '${rows.length}${widget.more ? '+' : ''} ${ranked ? 'نتيجة' : 'عقار في النطاق'}';
    return DraggableScrollableSheet(key: const ValueKey('map-results-sheet'),
      controller: _extent, initialChildSize: widget.collapsed ? _minimum : _initial, minChildSize: _minimum, maxChildSize: _maximum,
      snap: true, snapSizes: [
        for (final size in (compact ? [_initial] : [_initial, widget.filterPanel == null ? .5 : .75]))
          if (size > _minimum && size < _maximum) size,
      ],
      shouldCloseOnMinExtent: false,
      builder: (context, scroll) {
        _scroll = scroll;
        return Material(key: const ValueKey('map-search-panel-surface'), color: Theme.of(context).colorScheme.surface, elevation: compact ? 3 : 8,
          shadowColor: AppPalette.charcoal.withValues(alpha: .18),
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
              onLoadMore: ranked && widget.more && !widget.loading && widget.error == null ? widget.onMore : null,
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
                  const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('لا توجد عقارات مطابقة في هذا النطاق. حرّك الخريطة أو عدّل الفلاتر.')),
                const SizedBox(height: 12),
              ]); }
              if (index > rows.length) { return widget.more && !widget.staleResults ? TextButton(onPressed: widget.loading ? null : widget.onMore,
                child: const Text('المزيد من العقارات')) : const SizedBox.shrink(); }
              final row = rows[index - 1];
              return Semantics(selected: row.id == widget.selectedId, child: Padding(
                key: ValueKey('map-result-${row.id}'), padding: const EdgeInsets.only(bottom: 12),
                child: DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.circular(10),
                  border: Border.all(width: row.id == widget.selectedId ? 2 : 1,
                    color: row.id == widget.selectedId ? Theme.of(context).colorScheme.secondary
                      : Theme.of(context).colorScheme.outlineVariant)),
                  child: widget.itemBuilder(row))));
            }))),
          ])));
      });
  }

  Widget _compactHeader(BuildContext context, String count) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final height = compactMapResultsHeaderHeight(context) - MediaQuery.paddingOf(context).bottom - 16;
    final showCollapse = widget.onShowList == null && _expanded;
    return Padding(
      padding: const EdgeInsets.fromLTRB(11, 0, 11, 4),
      child: Column(children: [
        Semantics(
          label: 'اسحب لتوسيع النتائج أو تصغيرها',
          child: SizedBox(key: const ValueKey('map-results-handle'), height: 12, width: double.infinity,
            child: Center(child: Container(width: 32, height: 3, decoration: BoxDecoration(
              color: scheme.outlineVariant, borderRadius: BorderRadius.circular(3),
            ))),
          ),
        ),
        SizedBox(height: height, child: Row(children: [
          Expanded(child: Semantics(
            liveRegion: true,
            label: widget.staleResults ? '$count من آخر تحميل' : count,
            excludeSemantics: true,
            child: Text(count, key: const ValueKey('map-results-count'), maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(fontSize: 19, height: 1.3,
                fontWeight: FontWeight.w700, color: scheme.primary)),
          )),
          if (widget.loading) Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          OutlinedButton.icon(
            key: widget.onShowList == null ? const ValueKey('map-show-list') : const ValueKey('smart-search-list'),
            onPressed: widget.onShowList ?? _toggleExtent,
            icon: Icon(showCollapse ? Icons.keyboard_arrow_down : Icons.view_list_outlined, size: 22),
            label: Text(showCollapse ? 'تصغير' : 'القائمة', maxLines: 1),
            style: OutlinedButton.styleFrom(
              minimumSize: Size(0, height), tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              foregroundColor: scheme.primary, side: BorderSide(color: scheme.primary),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
              textStyle: theme.textTheme.labelMedium,
            ),
          ),
        ])),
      ]),
    );
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
          onPressed: status.loading ? null : onFavorite, icon: Icon(status.icon)),
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

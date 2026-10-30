import 'package:flutter/material.dart';
import '../../../core/widgets/app_components.dart';
import '../../discovery/domain/smart_search_filters.dart';
import '../../properties/domain/property_marker.dart';
import '../../properties/presentation/adaptive_property_photo.dart';

const mapRentColor = Color(0xff147d92);
const mapSaleColor = Color(0xff0b8a55);

/// The map and this list receive the same immutable result snapshot. Its
/// controller resizes first, then scrolls, without rebuilding the native map.
class PropertyMapResultsSheet extends StatefulWidget {
  const PropertyMapResultsSheet({required this.items, required this.itemBuilder,
    this.selectedId, this.loading = false, this.error, this.onRetry, this.onShowList,
    this.more = false, this.onMore, this.maxExtent = .84, this.collapsed = false, this.filterPanel, super.key});
  final Widget? filterPanel;
  final List<PropertyMarker> items;
  final Widget Function(PropertyMarker property) itemBuilder;
  final int? selectedId;
  final bool loading, more;
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
  @override
  void initState() { super.initState(); _extent.addListener(_extentChanged); }
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
    if (!widget.collapsed && widget.selectedId != null && widget.selectedId != old.selectedId) {
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
    _maximum = widget.filterPanel == null ? widget.maxExtent
      : (1 - 70 / (height > 0 ? height : 1)).clamp(.14, widget.maxExtent).toDouble();
    final titleStyle = Theme.of(context).textTheme.titleSmall;
    final titleHeight = MediaQuery.textScalerOf(context).scale(titleStyle?.fontSize ?? 16) * (titleStyle?.height ?? 1.4);
    _minimum = widget.filterPanel == null ? .14 : ((40 + (titleHeight * 2 > 48 ? titleHeight * 2 : 48)) /
      (height > 0 ? height : 1)).clamp(.14, _maximum).toDouble();
    _initial = (widget.filterPanel == null ? .29 : .55).clamp(_minimum, _maximum).toDouble();
    final selected = widget.items.where((row) => row.id == widget.selectedId);
    final rows = [...selected, ...widget.items.where((row) => row.id != widget.selectedId)];
    return DraggableScrollableSheet(key: const ValueKey('map-results-sheet'),
      controller: _extent, initialChildSize: _initial, minChildSize: _minimum, maxChildSize: _maximum,
      snap: true, snapSizes: [for (final size in [_initial, widget.filterPanel == null ? .5 : .75]) if (size > _minimum && size < _maximum) size],
      shouldCloseOnMinExtent: false,
      builder: (context, scroll) {
        _scroll = scroll;
        return Material(key: const ValueKey('map-search-panel-surface'), color: Theme.of(context).colorScheme.surface, elevation: 8,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)), clipBehavior: Clip.antiAlias,
          child: ListView.builder(key: const ValueKey('map-results-list'), controller: scroll,
            padding: EdgeInsets.fromLTRB(12, 8, 12, 24 + MediaQuery.paddingOf(context).bottom), cacheExtent: 0,
            itemCount: rows.length + 2,
            itemBuilder: (context, index) {
              if (index == 0) { return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Semantics(label: 'اسحب لتوسيع الفلاتر والعقارات أو تصغيرها', child: Listener(
                  key: const ValueKey('map-results-handle'), behavior: HitTestBehavior.opaque,
                  child: SizedBox(height: 24, child: Center(child: Container(width: 42, height: 4,
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.outlineVariant, borderRadius: BorderRadius.circular(4))))))),
                Row(children: [Expanded(child: Text('${rows.length}${widget.more ? '+' : ''} عقار في النطاق',
                  key: const ValueKey('map-results-count'), maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall)),
                  if (widget.loading) const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  if (widget.onShowList != null) IconButton(tooltip: 'عرض القائمة', onPressed: widget.onShowList, icon: const Icon(Icons.view_list_outlined)),
                  if (widget.filterPanel != null) IconButton(key: const ValueKey('map-filter-panel-toggle'),
                    tooltip: _expanded ? 'تصغير الفلاتر' : 'فتح الفلاتر', onPressed: _toggleExtent,
                    icon: Icon(_expanded ? Icons.keyboard_arrow_down : Icons.tune)),
                ]),
                if (widget.filterPanel != null) Padding(padding: const EdgeInsets.only(bottom: 12),
                  child: SizedBox(key: _filterPanelKey, child: widget.filterPanel)),
                const Wrap(spacing: 16, runSpacing: 4, children: [
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
              if (index > rows.length) { return widget.more ? TextButton(onPressed: widget.loading ? null : widget.onMore,
                child: const Text('المزيد من العقارات')) : const SizedBox.shrink(); }
              final row = rows[index - 1];
              return Semantics(selected: row.id == widget.selectedId, child: Padding(
                key: ValueKey('map-result-${row.id}'), padding: const EdgeInsets.only(bottom: 12),
                child: DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.circular(10),
                  border: Border.all(width: row.id == widget.selectedId ? 2 : 1,
                    color: row.id == widget.selectedId ? Theme.of(context).colorScheme.primary
                      : row.purpose == 'rent' ? mapRentColor : mapSaleColor)),
                  child: widget.itemBuilder(row))));
            }));
      });
  }
}

/// Compact public result; it uses the same adaptive media and financial display
/// amount as discovery cards. Larger text grows vertically without hiding actions.
class PropertyMapResultCard extends StatelessWidget {
  const PropertyMapResultCard({required this.property, required this.favorite,
    required this.onFavorite, required this.onMap, required this.onDetails, this.compact = false, super.key});
  final PropertyMarker property;
  final bool favorite, compact;
  final VoidCallback? onFavorite;
  final VoidCallback onMap, onDetails;
  @override
  Widget build(BuildContext context) {
    final p = property, rent = p.purpose == 'rent', scheme = Theme.of(context).colorScheme;
    final photo = p.mainImage ?? (p.imageUrls.isEmpty ? null : p.imageUrls.first);
    if (compact && MediaQuery.textScalerOf(context).scale(14) <= 24) {
      return InkWell(onTap: onDetails, borderRadius: BorderRadius.circular(10),
        child: Padding(padding: const EdgeInsets.all(8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 64, height: 88,
            child: photo == null ? ColoredBox(color: scheme.surfaceContainerHighest,
              child: const Icon(Icons.home_outlined)) : AdaptivePropertyPhoto(url: photo))),
          const SizedBox(width: 8), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
            Text('${SmartSearchFilters.types[p.type] ?? 'عقار'} · ${rent ? 'للإيجار' : 'للبيع'}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: rent ? mapRentColor : mapSaleColor)),
            if (p.address?.isNotEmpty == true) Text(p.address!, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart,
              child: AppPropertyPrice(price: (rent ? p.monthlyRent ?? p.price : p.price).toString(), currency: p.currency,
                suffix: rent && p.monthlyRent != null ? 'شهريًا' : null)),
          ])),
          Column(mainAxisSize: MainAxisSize.min, children: [
            IconButton(key: ValueKey('map-card-favorite-${p.id}'), tooltip: favorite ? 'إزالة من المفضلة' : 'حفظ في المفضلة',
              onPressed: onFavorite, icon: Icon(favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded)),
            IconButton(key: ValueKey('map-card-focus-${p.id}'), tooltip: 'عرض على الخريطة',
              onPressed: onMap, icon: const Icon(Icons.location_on_outlined)),
          ]),
        ])));
    }
    return InkWell(onTap: onDetails, borderRadius: BorderRadius.circular(10),
      child: Padding(padding: const EdgeInsets.all(8), child: Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 88, height: 104,
            child: photo == null ? ColoredBox(color: scheme.surfaceContainerHighest,
              child: const Icon(Icons.home_outlined)) : AdaptivePropertyPhoto(url: photo))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(SmartSearchFilters.types[p.type] ?? 'عقار', style: Theme.of(context).textTheme.labelMedium),
            if (p.address?.isNotEmpty == true) Text(p.address!, maxLines: 2,
              overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
          ])),
        ]),
        Padding(padding: const EdgeInsets.only(top: 8), child: Align(alignment: AlignmentDirectional.centerStart,
          child: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart,
            child: AppPropertyPrice(price: (rent ? p.monthlyRent ?? p.price : p.price).toString(), currency: p.currency,
              suffix: rent && p.monthlyRent != null ? 'شهريًا' : null)))),
        Row(children: [Expanded(child: Text(rent ? 'للإيجار' : 'للبيع',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(color: rent ? mapRentColor : mapSaleColor))),
          IconButton(key: ValueKey('map-card-favorite-${p.id}'), tooltip: favorite ? 'إزالة من المفضلة' : 'حفظ في المفضلة',
            onPressed: onFavorite, icon: Icon(favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded)),
          IconButton(key: ValueKey('map-card-focus-${p.id}'), tooltip: 'عرض على الخريطة',
            onPressed: onMap, icon: const Icon(Icons.location_on_outlined)),
        ]),
      ])));
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

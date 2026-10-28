import 'package:flutter/material.dart';
import '../../properties/domain/property_marker.dart';

const mapRentColor = Color(0xff147d92);
const mapSaleColor = Color(0xff0b8a55);

/// The map and this list receive the same immutable result snapshot. Its
/// controller resizes first, then scrolls, without rebuilding the native map.
class PropertyMapResultsSheet extends StatefulWidget {
  const PropertyMapResultsSheet({required this.items, required this.itemBuilder,
    this.selectedId, this.loading = false, this.error, this.onRetry, this.onShowList,
    this.more = false, this.onMore, super.key});
  final List<PropertyMarker> items;
  final Widget Function(PropertyMarker property) itemBuilder;
  final int? selectedId;
  final bool loading, more;
  final String? error;
  final VoidCallback? onRetry, onShowList, onMore;
  @override
  State<PropertyMapResultsSheet> createState() => _PropertyMapResultsSheetState();
}

class _PropertyMapResultsSheetState extends State<PropertyMapResultsSheet> {
  final _extent = DraggableScrollableController();
  ScrollController? _scroll;
  @override
  void didUpdateWidget(PropertyMapResultsSheet old) {
    super.didUpdateWidget(old);
    if (widget.selectedId != null && widget.selectedId != old.selectedId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_scroll?.hasClients == true) _scroll!.jumpTo(0);
        if (_extent.isAttached && _extent.size < .5) {
          _extent.animateTo(.5, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
        }
      });
    }
  }
  @override
  void dispose() { _extent.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final selected = widget.items.where((row) => row.id == widget.selectedId);
    final rows = [...selected, ...widget.items.where((row) => row.id != widget.selectedId)];
    return DraggableScrollableSheet(key: const ValueKey('map-results-sheet'),
      controller: _extent, initialChildSize: .29, minChildSize: .14, maxChildSize: .84,
      snap: true, snapSizes: const [.29, .5], shouldCloseOnMinExtent: false,
      builder: (context, scroll) {
        _scroll = scroll;
        return Material(color: Theme.of(context).colorScheme.surface, elevation: 8,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)), clipBehavior: Clip.antiAlias,
          child: ListView.builder(key: const PageStorageKey('map-results-list'), controller: scroll,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), cacheExtent: 0,
            itemCount: rows.length + 2,
            itemBuilder: (context, index) {
              if (index == 0) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Center(child: Container(width: 42, height: 4, margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.outlineVariant, borderRadius: BorderRadius.circular(4)))),
                Row(children: [Expanded(child: Text('${rows.length}${widget.more ? '+' : ''} عقار في النطاق',
                  key: const ValueKey('map-results-count'), style: Theme.of(context).textTheme.titleSmall)),
                  if (widget.loading) const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  if (widget.onShowList != null) IconButton(tooltip: 'عرض القائمة', onPressed: widget.onShowList, icon: const Icon(Icons.view_list_outlined)),
                ]),
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
              ]);
              if (index > rows.length) return widget.more ? TextButton(onPressed: widget.loading ? null : widget.onMore,
                child: const Text('المزيد من العقارات')) : const SizedBox.shrink();
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

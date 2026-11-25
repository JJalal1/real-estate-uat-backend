import 'package:flutter/material.dart';

import '../../../core/widgets/app_components.dart';
import '../../discovery/domain/smart_search_filters.dart';
import '../../discovery/presentation/search_result_pagination.dart';
import '../../properties/domain/property_marker.dart';
import 'property_map_results_sheet.dart';

/// Reads the map's current result order and pages without moving the camera.
class PropertyMapResultsPage extends StatelessWidget {
  const PropertyMapResultsPage({
    required this.filters,
    required this.items,
    required this.itemBuilder,
    required this.loading,
    required this.more,
    required this.onRetry,
    this.total,
    this.error,
    this.onMore,
    super.key,
  });

  final SmartSearchFilters filters;
  final List<PropertyMarker> items;
  final Widget Function(PropertyMarker) itemBuilder;
  final bool loading, more;
  final int? total;
  final String? error;
  final VoidCallback onRetry;
  final VoidCallback? onMore;

  bool get _drawn => filters.values.containsKey('area_polygon');

  String get _countLabel {
    if (items.isEmpty && loading) return 'جارٍ تحميل النتائج…';
    if (items.isEmpty && error != null) return 'تعذر تحميل النتائج';
    return switch (total ?? items.length) {
      0 when !more => 'لا توجد نتائج',
      1 when !more || total != null => 'نتيجة واحدة',
      2 when !more || total != null => 'نتيجتان',
      final count =>
        '${arabicDigits('$count')}${more && total == null ? '+' : ''} نتيجة',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final chips = filters.chips;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: const AppAppBar(title: 'قائمة العقارات'),
        body: SearchResultPagination(
          onLoadMore: onMore,
          child: CustomScrollView(
            key: const ValueKey('map-full-results-list'),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (chips.isNotEmpty)
                        Wrap(
                          key: const ValueKey('map-full-results-filters'),
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            for (final (key, label) in chips)
                              Chip(
                                avatar: Icon(Icons.check,
                                    size: 16, color: colors.onPrimaryContainer),
                                label: Text(key == 'map_area' && _drawn
                                    ? 'داخل المنطقة المرسومة'
                                    : label),
                                backgroundColor: colors.primaryContainer,
                                side: BorderSide.none,
                                labelStyle: theme.textTheme.labelMedium
                                    ?.copyWith(
                                        color: colors.onPrimaryContainer),
                                visualDensity: VisualDensity.compact,
                              ),
                          ],
                        ),
                      Semantics(
                        liveRegion: true,
                        child: Text(_countLabel,
                            key: const ValueKey('map-full-results-count'),
                            style: theme.textTheme.titleSmall),
                      ),
                      if (loading || error != null)
                        AppRefreshStatus(
                            loading: loading, error: error, onRetry: onRetry),
                    ],
                  ),
                ),
              ),
              if (items.isEmpty && !loading && error == null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: AppEmptyState(
                    icon: Icons.search_off_outlined,
                    title: 'لا توجد عقارات مطابقة',
                    message: _drawn
                        ? 'لا توجد إعلانات داخل المنطقة المحددة.'
                        : 'يمكنك العودة إلى الخريطة لتعديل الفلاتر أو النطاق.',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  sliver: SliverList.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final property = items[index];
                      return Padding(
                        key: ValueKey('map-full-result-${property.id}'),
                        padding: const EdgeInsets.only(bottom: 10),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: property.purpose == 'rent'
                                    ? mapRentColor
                                    : mapSaleColor),
                          ),
                          child: itemBuilder(property),
                        ),
                      );
                    },
                  ),
                ),
              if (more && error == null)
                SliverToBoxAdapter(
                  child: TextButton(
                    onPressed: onMore,
                    child: const Text('المزيد من العقارات'),
                  ),
                ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          child: AppButton(
            key: const ValueKey('map-full-list-return'),
            label: 'الخريطة',
            icon: Icons.map_outlined,
            expand: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }
}

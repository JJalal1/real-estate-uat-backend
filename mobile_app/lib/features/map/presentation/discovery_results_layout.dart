import 'package:flutter/material.dart';

import '../../../core/design/app_design.dart';

/// Header controls can leave the viewport without eagerly building results.
class DiscoveryResultsLayout extends StatelessWidget {
  const DiscoveryResultsLayout({required this.header, required this.results, super.key});

  final Widget header;
  final Widget results;

  @override
  Widget build(BuildContext context) => NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverToBoxAdapter(child: header),
        ],
        body: results,
      );
}

class DiscoverySortBar extends StatelessWidget {
  const DiscoverySortBar({
    required this.sortMode,
    required this.filterCount,
    required this.onSort,
    required this.onFilters,
    super.key,
  });

  final int sortMode;
  final int filterCount;
  final ValueChanged<int> onSort;
  final VoidCallback onFilters;

  @override
  Widget build(BuildContext context) => AppSurface(
        padding: const EdgeInsetsDirectional.all(AppSpacing.s12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSectionHeader(
              title: 'ترتيب النتائج',
              actionLabel: filterCount == 0 ? 'تصفية' : 'تصفية ($filterCount)',
              onAction: onFilters,
            ),
            const SizedBox(height: AppSpacing.s8),
            Wrap(
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.s8,
              children: [
                for (final option in const [(0, 'الأحدث'), (1, 'السعر'), (2, 'الأقرب')])
                  AppFilterChip(
                    label: option.$2,
                    selected: sortMode == option.$1,
                    onSelected: (_) {
                      if (sortMode != option.$1) onSort(option.$1);
                    },
                  ),
              ],
            ),
          ],
        ),
      );
}

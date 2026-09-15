import 'package:flutter/material.dart';

import '../../../core/design/app_design.dart';

/// Presentation for the existing quick filters. The screen owns toggling,
/// persistence, room-filter compatibility and API parameters.
class DiscoveryFilterPanel extends StatelessWidget {
  const DiscoveryFilterPanel({
    required this.purpose,
    required this.type,
    required this.filterCount,
    required this.searchText,
    required this.onPurpose,
    required this.onType,
    required this.onSearch,
    required this.onMore,
    super.key,
  });

  final String? purpose;
  final String? type;
  final int filterCount;
  final String searchText;
  final ValueChanged<String?> onPurpose;
  final ValueChanged<String?> onType;
  final VoidCallback onSearch;
  final VoidCallback onMore;

  // Same quick-filter options and order as the stable discovery panel. Farm
  // remains available in the existing detailed filter sheet.
  static const _types = <(String?, String)>[
    (null, 'الكل'),
    ('apartment', 'شقة'),
    ('villa', 'فيلا'),
    ('house', 'منزل'),
    ('land', 'أرض'),
    ('shop', 'محل'),
    ('office', 'مكتب'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: AppElevation.floating,
      borderRadius: BorderRadius.circular(AppRadii.modal),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(AppSpacing.s12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSearchEntry(
              label: searchText.isEmpty ? 'ابحث عن منطقة أو عقار' : searchText,
              onTap: onSearch,
              onFilter: onMore,
              filterLabel: filterCount == 0
                  ? 'المزيد من الفلاتر'
                  : 'المزيد من الفلاتر ($filterCount)',
            ),
            const SizedBox(height: AppSpacing.s12),
            Row(
              children: [
                Expanded(
                  child: _PurposeChoice(
                    label: 'للإيجار',
                    icon: Icons.key_outlined,
                    selected: purpose == 'rent',
                    onTap: () => onPurpose('rent'),
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: _PurposeChoice(
                    label: 'للبيع',
                    icon: Icons.sell_outlined,
                    selected: purpose == 'sale',
                    onTap: () => onPurpose('sale'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final option in _types)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: AppSpacing.s8),
                      child: AppFilterChip(
                        label: option.$2,
                        selected: type == option.$1,
                        onSelected: (_) => onType(option.$1),
                      ),
                    ),
                  AppButton(
                    label: filterCount == 0 ? 'المزيد' : 'المزيد ($filterCount)',
                    icon: Icons.tune,
                    style: AppButtonStyle.text,
                    onPressed: onMore,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PurposeChoice extends StatelessWidget {
  const _PurposeChoice({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        child: AppButton(
          label: label,
          icon: icon,
          expand: true,
          onPressed: onTap,
          style: selected ? AppButtonStyle.tonal : AppButtonStyle.outlined,
        ),
      );
}

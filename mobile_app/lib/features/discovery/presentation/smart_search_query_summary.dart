import 'package:flutter/material.dart';

import '../domain/smart_search_filters.dart';

/// Renders accepted search criteria, never an interpretation of partial speech.
class SmartSearchQuerySummary extends StatelessWidget {
  const SmartSearchQuerySummary({
    required this.filters,
    required this.onEdit,
    required this.onRemove,
    this.interpreting = false,
    super.key,
  });

  final SmartSearchFilters filters;
  final ValueChanged<String> onEdit;
  final ValueChanged<String> onRemove;
  final bool interpreting;

  static const _order = [
    'type', 'purpose', 'governorate', 'search', 'map_area', 'budget', 'currency',
    'min_bedrooms', 'min_bathrooms', 'min_area_m2', 'max_area_m2',
    'floor_number', 'has_parking', 'has_elevator', 'building_facade',
    'unit_occupies_entire_floor', 'advertiser_id', 'spotlight',
  ];

  String _money(dynamic value) {
    final number = value is num ? value : num.tryParse(value.toString());
    if (number != null) {
      for (final unit in [(1000000000, 'مليار'), (1000000, 'مليون'), (1000, 'ألف')]) {
        if (number >= unit.$1 && number % unit.$1 == 0) {
          return '${(number / unit.$1).toStringAsFixed(0)} ${unit.$2}';
        }
      }
    }
    final parts = value.toString().split('.');
    final whole = parts.first.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (match) => '${match[1]}٬',
    );
    final decimals = parts.length > 1 ? parts[1].replaceFirst(RegExp(r'0+$'), '') : '';
    return decimals.isEmpty ? whole : '$whole.$decimals';
  }

  String _label(String key, String fallback) {
    if (key == 'governorate') {
      return filters.values[key].toString();
    }
    if (key != 'budget') {
      return fallback;
    }
    final low = filters.values['min_price'], high = filters.values['max_price'];
    final range = low != null && high != null
        ? 'من ${_money(low)} إلى ${_money(high)}'
        : low != null ? 'من ${_money(low)}' : 'حتى ${_money(high)}';
    final currency = filters.values['currency'] == 'USD' ? 'دولار'
        : filters.values['currency'] == 'SAR' ? 'ريال سعودي' : 'ريال يمني';
    return '$range $currency${filters.values['purpose'] == 'rent' ? ' شهريًا' : ''}';
  }

  IconData _icon(String key) => switch (key) {
    'type' => Icons.home_outlined,
    'purpose' => Icons.sell_outlined,
    'search' || 'governorate' => Icons.location_on_outlined,
    'map_area' => Icons.map_outlined,
    'budget' || 'currency' => Icons.payments_outlined,
    'min_bedrooms' => Icons.bed_outlined,
    'min_bathrooms' => Icons.bathtub_outlined,
    'min_area_m2' || 'max_area_m2' => Icons.square_foot,
    'floor_number' => Icons.layers_outlined,
    'has_parking' => Icons.local_parking_outlined,
    'has_elevator' => Icons.elevator_outlined,
    'advertiser_id' => Icons.person_outline,
    'spotlight' => Icons.auto_awesome_outlined,
    _ => Icons.check_circle_outline,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final chips = {for (final chip in filters.chips) chip.$1: chip.$2};
    final hasBudget = chips.containsKey('budget');
    final keys = _order.where((key) => chips.containsKey(key) && (key != 'currency' || !hasBudget)).toList();
    final compact = theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    Widget word(String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12), child: Text(text, style: compact),
    );

    return Container(
      key: const ValueKey('smart-search-query-summary'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .6)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.auto_awesome_outlined, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Expanded(child: Text('بحثك الحالي', style: theme.textTheme.labelLarge)),
        ]),
        if (interpreting && keys.isEmpty)
          Padding(
            key: const ValueKey('smart-search-query-pending'),
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Semantics(liveRegion: true, child: Text('نحدّد معايير بحثك…', style: compact)),
          )
        else
          LayoutBuilder(builder: (context, constraints) => Wrap(
            spacing: 6, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              word('ابحث عن'),
              if (!chips.containsKey('type')) word('عقارات'),
              for (final key in keys) ...[
                if (key == 'governorate' || key == 'search') word('في'),
                if (key == 'budget') word('بسعر'),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                  child: InputChip(
                    key: ValueKey('smart-chip-$key'),
                    avatar: Icon(_icon(key), size: 16,
                      color: key == 'search' || key == 'governorate' ? scheme.primary : scheme.onSurfaceVariant),
                    label: Text(_label(key, chips[key]!), maxLines: 2, overflow: TextOverflow.ellipsis),
                    backgroundColor: key == 'search' || key == 'governorate'
                        ? scheme.primaryContainer.withValues(alpha: .55) : scheme.surface,
                    side: BorderSide.none,
                    onPressed: interpreting ? null : () => onEdit(key),
                    onDeleted: interpreting ? null : () => onRemove(key),
                    deleteButtonTooltipMessage: 'إزالة ${_label(key, chips[key]!)}',
                  ),
                ),
              ],
            ],
          )),
        if (interpreting && keys.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 6), child: Semantics(
            liveRegion: true, child: Text('نحدّث معايير بحثك…', style: compact),
          )),
      ]),
    );
  }
}

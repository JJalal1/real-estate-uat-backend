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
    final compact = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    Widget word(String text) => Text(text, style: compact);

    Widget criterion(String key, String label, double width) => ConstrainedBox(
      key: ValueKey('smart-chip-$key'),
      constraints: BoxConstraints(maxWidth: width),
      child: Material(
        color: key == 'search' || key == 'governorate'
            ? scheme.primaryContainer.withValues(alpha: .65) : scheme.surfaceContainerHighest.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(18),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: InkWell(
            key: ValueKey('smart-chip-edit-$key'),
            borderRadius: BorderRadius.circular(18),
            onTap: interpreting ? null : () => onEdit(key),
            child: Semantics(button: true, label: 'تعديل $label', excludeSemantics: true, child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(padding: const EdgeInsetsDirectional.fromSTEB(9, 6, 3, 6),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_icon(key), size: 15, color: scheme.primary),
                  const SizedBox(width: 5),
                  Flexible(child: Text(label, key: ValueKey('smart-chip-label-$key'),
                    style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600), softWrap: true)),
                ]),
              ),
            )),
          )),
          IconButton(
            key: ValueKey('smart-chip-remove-$key'),
            onPressed: interpreting ? null : () => onRemove(key),
            tooltip: 'إزالة $label',
            icon: const Icon(Icons.close, size: 15),
            padding: const EdgeInsets.all(5),
            constraints: const BoxConstraints(minWidth: 30, minHeight: 44),
          ),
        ]),
      ),
    );

    return Container(
      key: const ValueKey('smart-search-query-summary'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (interpreting && keys.isEmpty)
          Padding(
            key: const ValueKey('smart-search-query-pending'),
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Semantics(liveRegion: true, child: Text('نحدّد معايير بحثك…', style: compact)),
          )
        else
          LayoutBuilder(builder: (context, constraints) => Wrap(
            spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (!chips.containsKey('type')) word('ابحث عن عقارات'),
              for (final key in keys)
                ConstrainedBox(constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (key == 'type' || key == 'search' || key == 'governorate' || key == 'budget') ...[
                      word(key == 'type' ? 'ابحث عن' : key == 'budget' ? 'بسعر' : 'في'),
                      const SizedBox(width: 6),
                    ],
                    Flexible(child: criterion(key, _label(key, chips[key]!), constraints.maxWidth)),
                  ]),
                ),
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

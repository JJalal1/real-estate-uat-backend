import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/ebroker_design.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import 'marketplace_category_filter_sheet.dart';
import 'marketplace_section_screen.dart';

const _purposeLabels = {'rent': 'للإيجار', 'sale': 'للبيع'};
const _categoryLabels = {
  'apartment': 'شقق',
  'house': 'منازل',
  'villa': 'فلل',
  'building': 'عمائر',
  'land': 'أراضٍ',
  'farm': 'مزارع',
  'shop': 'محلات',
  'office': 'مكاتب',
};

class MarketplaceCategoriesScreen extends StatefulWidget {
  const MarketplaceCategoriesScreen({
    this.initialPurpose = 'rent',
    this.initialType,
    super.key,
  });

  final String initialPurpose;
  final String? initialType;

  @override
  State<MarketplaceCategoriesScreen> createState() =>
      _MarketplaceCategoriesScreenState();
}

class _MarketplaceCategoriesScreenState
    extends State<MarketplaceCategoriesScreen> {
  final _savedFilters = <(String, String?), Map<String, Object>>{};
  late String _purpose;
  String? _type;

  @override
  void initState() {
    super.initState();
    _purpose = _purposeLabels.containsKey(widget.initialPurpose)
        ? widget.initialPurpose
        : 'rent';
    _type = _categoryLabels.containsKey(widget.initialType)
        ? widget.initialType
        : null;
  }

  Map<String, Object> get _filters =>
      _savedFilters[(_purpose, _type)] ?? const {};

  Future<void> _editFilters() async {
    final selection = (_purpose, _type);
    final filters = await showMarketplaceCategoryFilters(
      context,
      purpose: _purpose,
      type: _type,
      typeLabel: _categoryLabels[_type],
      initial: _filters,
    );
    if (!mounted || filters == null) return;
    setState(() => _savedFilters[selection] = filters);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final filters = _filters;
    final query = <String, Object>{
      ...filters,
      'ranked_search': 0,
      'purpose': _purpose,
      if (_type case final type?) 'type': type,
    };
    final resultsTitle =
        '${_categoryLabels[_type] ?? 'عقارات'} ${_purposeLabels[_purpose]}';
    final scaledLabelSize = MediaQuery.textScalerOf(context).scale(13);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: const AppAppBar(title: 'الأقسام'),
        body: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppLayout.compactPageGutter,
                  12,
                  AppLayout.compactPageGutter,
                  12,
                ),
                child: Row(
                  children: [
                    for (final entry in _purposeLabels.entries) ...[
                      if (entry.key == 'sale') const SizedBox(width: 6),
                      Expanded(
                        child: _PurposeButton(
                          key: ValueKey(
                              'marketplace-category-purpose-${entry.key}'),
                          selected: _purpose == entry.key,
                          label: entry.value,
                          icon: entry.key == 'rent'
                              ? Icons.key_outlined
                              : Icons.sell_outlined,
                          onPressed: () => setState(() => _purpose = entry.key),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(
                height: (48 + (scaledLabelSize - 13) * 2)
                    .clamp(48.0, double.infinity)
                    .toDouble(),
                child: ListView(
                  key: const PageStorageKey('marketplace-category-types'),
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppLayout.compactPageGutter),
                  children: [
                    for (final (type, label) in <(String?, String)>[
                      (null, 'الكل'),
                      for (final entry in _categoryLabels.entries)
                        (entry.key, entry.value),
                    ])
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 6),
                        child: EbrokerCategoryCard(
                          key: ValueKey(
                              'marketplace-category-type-${type ?? 'all'}'),
                          label: label,
                          icon: type == null ? '' : ebrokerCategoryIcon(type),
                          iconOverride:
                              type == null ? Icons.grid_view_outlined : null,
                          selected: _type == type,
                          onTap: () => setState(() => _type = type),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppLayout.compactPageGutter,
                  10,
                  AppLayout.compactPageGutter,
                  0,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child:
                          Text(resultsTitle, style: theme.textTheme.titleLarge),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      key: const ValueKey('marketplace-category-filters'),
                      onPressed: _editFilters,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(48, 30),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        textStyle: theme.textTheme.labelSmall,
                        visualDensity: VisualDensity.standard,
                        tapTargetSize: MaterialTapTargetSize.padded,
                        foregroundColor: scheme.primary,
                        backgroundColor: filters.isEmpty
                            ? scheme.surface
                            : scheme.primaryContainer,
                        side: BorderSide(color: scheme.primary),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.tune_rounded, size: 14),
                      label: const Text('تصفية'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: MarketplaceListingResults(
                  query: query,
                  compactCards: true,
                  bottomPadding: 16,
                  emptyMessage: 'جرّب تغيير النوع أو شروط التصفية.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PurposeButton extends StatelessWidget {
  const _PurposeButton({
    super.key,
    required this.selected,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final bool selected;
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(AppRadii.control);

    return Semantics(
      selected: selected,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient:
              selected ? EbrokerDesign.propertyTypeSelectionGradient : null,
        ),
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            foregroundColor: selected ? Colors.white : scheme.onSurface,
            backgroundColor: selected ? Colors.transparent : scheme.surface,
            shape: RoundedRectangleBorder(borderRadius: radius),
            side: BorderSide(
              color: selected ? Colors.transparent : scheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  color: selected ? Colors.white : scheme.primary, size: 20),
              const SizedBox(width: 6),
              Flexible(child: Text(label, textAlign: TextAlign.center)),
            ],
          ),
        ),
      ),
    );
  }
}

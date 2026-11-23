import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../discovery/domain/smart_search_filters.dart';

class MapDiscoveryToolbar extends StatelessWidget {
  const MapDiscoveryToolbar({
    required this.filters,
    required this.onPurpose,
    required this.onType,
    required this.onSearch,
    required this.onFilters,
    this.onBack,
    this.extraFilters = false,
    super.key,
  });

  final SmartSearchFilters filters;
  final ValueChanged<String?> onPurpose;
  final ValueChanged<String> onType;
  final VoidCallback onSearch, onFilters;
  final VoidCallback? onBack;
  final bool extraFilters;

  static const _types = {
    'apartment': 'شقق',
    'house': 'منازل',
    'villa': 'فلل',
    'land': 'أراضٍ',
    'shop': 'محلات',
    'office': 'مكاتب',
    'building': 'عمائر',
    'farm': 'مزارع',
  };
  static const _radius = BorderRadius.all(Radius.circular(9));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selected = filters.values['purpose'];
    final both = selected == null;
    final activeFilters = extraFilters ||
        filters.chips.any((chip) =>
            !chip.$1.startsWith('type:') &&
            chip.$1 != 'type' &&
            chip.$1 != 'purpose');
    final scaler = MediaQuery.textScalerOf(context);
    final controlsHeight = math.max(44.0, scaler.scale(14) * 1.4 + 8);
    final categoriesHeight = math.max(42.0, scaler.scale(13) * 1.4 + 8);
    final saleBackground =
        both || selected == 'sale' ? colors.primaryContainer : colors.surface;
    final rentBackground =
        both || selected == 'rent' ? colors.primaryContainer : colors.surface;
    final neutralInk = colors.onSurface;

    return Material(
      color: colors.surface,
      elevation: 2,
      shadowColor: colors.shadow.withValues(alpha: .15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            height: controlsHeight,
            child: Row(
                key: const ValueKey('map-search-purpose'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (onBack != null) ...[
                    SizedBox(
                        width: 37,
                        child: BackButton(
                          key: const ValueKey('map-back'),
                          onPressed: onBack,
                          style: IconButton.styleFrom(padding: EdgeInsets.zero),
                          color: colors.primary,
                        )),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                      child: _label(
                    key: const ValueKey('published-purpose-sale'),
                    label: 'بيع',
                    selected: both || selected == 'sale',
                    background: saleBackground,
                    foreground: saleBackground == colors.surface
                        ? neutralInk
                        : colors.onPrimaryContainer,
                    outline: saleBackground == colors.surface
                        ? colors.outlineVariant
                        : colors.primary,
                    onPressed: () =>
                        onPurpose(selected == 'sale' ? null : 'sale'),
                  )),
                  const SizedBox(width: 6),
                  Expanded(
                      child: _label(
                    key: const ValueKey('published-purpose-rent'),
                    label: 'إيجار',
                    selected: both || selected == 'rent',
                    background: rentBackground,
                    foreground: rentBackground == colors.surface
                        ? neutralInk
                        : colors.onPrimaryContainer,
                    outline: rentBackground == colors.surface
                        ? colors.outlineVariant
                        : colors.primary,
                    onPressed: () =>
                        onPurpose(selected == 'rent' ? null : 'rent'),
                  )),
                  const SizedBox(width: 6),
                  SizedBox(
                      width: 46,
                      height: controlsHeight,
                      child: IconButton(
                        key: const ValueKey('map-open-search'),
                        onPressed: onSearch,
                        tooltip: 'بحث',
                        padding: EdgeInsets.zero,
                        style: IconButton.styleFrom(
                          backgroundColor: colors.primary,
                          foregroundColor: colors.onPrimary,
                          shape: const RoundedRectangleBorder(
                              borderRadius: _radius),
                        ),
                        icon: const Icon(Icons.search_rounded, size: 26),
                      )),
                ]),
          ),
          const SizedBox(height: 7),
          LayoutBuilder(builder: (context, constraints) {
            final chipWidth = math.max(
                (constraints.maxWidth - 20) / 5, scaler.scale(13) * 3.2);
            return Semantics(
              label: 'أنواع العقارات',
              child: SingleChildScrollView(
                key: const ValueKey('map-type-rail'),
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final type in _types.entries)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 5),
                      child: SizedBox(
                          width: chipWidth,
                          height: categoriesHeight,
                          child: _label(
                            key: ValueKey('published-type-${type.key}'),
                            label: type.value,
                            fontSize: 13,
                            selected: filters.selectedTypes.contains(type.key),
                            background: filters.selectedTypes.contains(type.key)
                                ? colors.primary
                                : colors.surface,
                            foreground: filters.selectedTypes.contains(type.key)
                                ? colors.onPrimary
                                : neutralInk,
                            outline: filters.selectedTypes.contains(type.key)
                                ? colors.primary
                                : colors.outlineVariant,
                            onPressed: () => onType(type.key),
                          )),
                    ),
                  SizedBox(
                      width: 44,
                      height: categoriesHeight,
                      child: IconButton(
                        key: const ValueKey('published-map-filters'),
                        onPressed: onFilters,
                        tooltip: activeFilters
                            ? 'تصفية · توجد شروط مطبّقة'
                            : 'تصفية',
                        padding: EdgeInsets.zero,
                        style: IconButton.styleFrom(
                          backgroundColor: activeFilters
                              ? colors.primary
                              : colors.primaryContainer,
                          foregroundColor: activeFilters
                              ? colors.onPrimary
                              : colors.onPrimaryContainer,
                          side: BorderSide(
                              color: activeFilters
                                  ? colors.primary
                                  : colors.outlineVariant),
                          shape: const RoundedRectangleBorder(
                              borderRadius: _radius),
                        ),
                        icon: const Icon(Icons.tune_rounded, size: 23),
                      )),
                ]),
              ),
            );
          }),
        ]),
      ),
    );
  }

  Widget _label({
    required Key key,
    required String label,
    required bool selected,
    required Color background,
    required Color foreground,
    required Color outline,
    required VoidCallback onPressed,
    double fontSize = 14,
  }) =>
      Semantics(
        selected: selected,
        child: TextButton(
          key: key,
          onPressed: onPressed,
          style: TextButton.styleFrom(
            backgroundColor: background,
            foregroundColor: foreground,
            side: BorderSide(color: outline),
            padding: const EdgeInsets.symmetric(horizontal: 3),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: const RoundedRectangleBorder(borderRadius: _radius),
          ),
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600)),
        ),
      );
}

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/ebroker_design.dart';
import '../../../core/widgets/app_components.dart';
import '../../properties/domain/category_property_facts.dart';
import '../../properties/domain/property_schema.dart';
import '../domain/smart_search_filters.dart';

/// Opens a draft of the current type-specific search conditions. Dismissing
/// the sheet leaves the active search untouched.
Future<Map<String, Object>?> showMarketplaceCategoryFilters(
  BuildContext context, {
  required String purpose,
  required String? type,
  required String? typeLabel,
  required Map<String, Object> initial,
}) =>
    showModalBottomSheet<Map<String, Object>>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => _MarketplaceCategoryFilterSheet(
        purpose: purpose,
        type: type,
        typeLabel: typeLabel,
        initial: initial,
      ),
    );

const _filterTitles = {
  'apartment': 'الشقق',
  'house': 'المنازل',
  'villa': 'الفلل',
  'building': 'العمائر',
  'land': 'الأراضي',
  'farm': 'المزارع',
  'shop': 'المحلات',
  'office': 'المكاتب',
};

class _MarketplaceCategoryFilterSheet extends StatefulWidget {
  const _MarketplaceCategoryFilterSheet({
    required this.purpose,
    required this.type,
    required this.typeLabel,
    required this.initial,
  });

  final String purpose;
  final String? type, typeLabel;
  final Map<String, Object> initial;

  @override
  State<_MarketplaceCategoryFilterSheet> createState() =>
      _MarketplaceCategoryFilterSheetState();
}

class _MarketplaceCategoryFilterSheetState
    extends State<_MarketplaceCategoryFilterSheet> {
  static const _areaMin = 'min_area_m2';
  static const _areaMax = 'max_area_m2';
  static const _retiredFilters = {
    'has_separate_majlis',
    'has_majlis_bathroom',
    'min_parking_spaces',
  };
  // Preserve TextField focus when the keyboard changes the sheet layout.
  final _optionsKey = GlobalKey();
  late final Map<String, Object> _draft = Map.of(widget.initial)
    ..removeWhere((key, _) => _retiredFilters.contains(key));
  late final _minimum = TextEditingController(text: _initialNumber(_areaMin));
  late final _maximum = TextEditingController(text: _initialNumber(_areaMax));
  String? _error;

  String _initialNumber(String key) {
    final value = _draft[key];
    if (value is double && value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value?.toString() ?? '';
  }

  @override
  void dispose() {
    _minimum.dispose();
    _maximum.dispose();
    super.dispose();
  }

  double? _parseArea(String text) {
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final ascii = text
        .trim()
        .replaceAllMapped(RegExp('[$arabic$persian]'), (match) {
          final digit = match.group(0)!;
          final index = arabic.indexOf(digit);
          return (index >= 0 ? index : persian.indexOf(digit)).toString();
        })
        .replaceAll('٫', '.')
        .replaceAll(RegExp('[٬,]'), '');
    if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(ascii)) return null;
    final value = double.tryParse(ascii);
    return value != null && value.isFinite && value <= 1000000000000
        ? value
        : null;
  }

  void _apply() {
    final minimum = _parseArea(_minimum.text);
    final maximum = _parseArea(_maximum.text);
    if ((_minimum.text.trim().isNotEmpty && minimum == null) ||
        (_maximum.text.trim().isNotEmpty && maximum == null)) {
      setState(() => _error = 'أدخل المساحة بالأرقام.');
      return;
    }
    if (minimum != null && maximum != null && minimum > maximum) {
      setState(() => _error = 'أقل مساحة يجب ألا تتجاوز أكبر مساحة.');
      return;
    }
    final query = Map<String, Object>.of(_draft)
      ..remove(_areaMin)
      ..remove(_areaMax);
    if (minimum != null) query[_areaMin] = minimum;
    if (maximum != null) query[_areaMax] = maximum;
    Navigator.of(context).pop(Map<String, Object>.unmodifiable(query));
  }

  void _reset() {
    setState(() {
      _draft.clear();
      _minimum.clear();
      _maximum.clear();
      _error = null;
    });
  }

  void _update(String key, Object? value) {
    setState(() {
      if (value == null) {
        _draft.remove(key);
      } else {
        _draft[key] = value;
      }
    });
  }

  Widget _fieldGroup(String key, String label, Widget control) => Padding(
        key: ValueKey('section-filter-$key'),
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            control,
          ],
        ),
      );

  Widget _choice<T extends Object>(
    String key,
    String label,
    Map<T?, String> options,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(AppRadii.control);
    return _fieldGroup(
        key,
        label,
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.entries.map((option) {
            final selected = _draft[key] == option.key;
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: selected
                    ? EbrokerDesign.propertyTypeSelectionGradient
                    : null,
                borderRadius: radius,
              ),
              child: ChoiceChip(
                key: ValueKey('section-filter-$key-${option.key ?? 'all'}'),
                label: Text(option.value),
                labelStyle:
                    selected ? const TextStyle(color: Colors.white) : null,
                selected: selected,
                showCheckmark: false,
                selectedColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: radius),
                side: BorderSide(
                  color: selected ? Colors.transparent : scheme.outlineVariant,
                ),
                onSelected: (_) => _update(key, option.key),
              ),
            );
          }).toList(),
        ));
  }

  Widget _count(
    String key,
    String label,
    List<int> thresholds, {
    bool explicitMinimum = false,
  }) =>
      _choice<int>(key, label, {
        null: explicitMinimum ? 'الكل' : 'أي عدد',
        for (final count in thresholds)
          count: '${arabicDigits('$count')}${explicitMinimum ? ' فأكثر' : '+'}',
      });

  Widget _switch(String key, String label) => SwitchListTile(
        key: ValueKey('section-filter-$key'),
        title: Text(label),
        contentPadding: EdgeInsets.zero,
        value: _draft[key] == 1,
        controlAffinity: ListTileControlAffinity.trailing,
        onChanged: (selected) => _update(key, selected ? 1 : null),
      );

  Widget _dropdown(
    String key,
    String label,
    Map<String, String> values, {
    String any = 'الكل',
  }) {
    final selected = _draft[key];
    return _fieldGroup(
        key,
        label,
        InputDecorator(
          decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 14)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              key: ValueKey('section-filter-select-$key'),
              value: values.containsKey(selected) ? selected as String : '',
              isExpanded: true,
              items: [
                DropdownMenuItem(value: '', child: Text(any)),
                for (final option in values.entries)
                  DropdownMenuItem(
                      value: option.key,
                      child: Text(arabicDigits(option.value))),
              ],
              onChanged: (value) => _update(key, value == '' ? null : value),
            ),
          ),
        ));
  }

  Widget _area() => _fieldGroup('area', 'المساحة', LayoutBuilder(
        builder: (context, constraints) {
          final minimum = _areaField(_areaMin, 'من', _minimum);
          final maximum = _areaField(_areaMax, 'إلى', _maximum);
          if (constraints.maxWidth < 240 ||
              MediaQuery.textScalerOf(context).scale(14) > 22) {
            return Column(
                children: [minimum, const SizedBox(height: 8), maximum]);
          }
          return Row(children: [
            Expanded(child: minimum),
            const SizedBox(width: 8),
            Expanded(child: maximum),
          ]);
        },
      ));

  Widget _areaField(
          String key, String label, TextEditingController controller) =>
      TextField(
        key: ValueKey('section-filter-$key'),
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        maxLength: 18,
        decoration: InputDecoration(
            labelText: label, suffixText: 'م²', counterText: ''),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
      );

  Widget _streetWidth() =>
      _choice<int>('min_street_width', 'عرض الشارع', const {
        null: 'الكل',
        10: '١٠ م فأكثر',
        16: '١٦ م فأكثر',
      });

  List<Widget> _controls() {
    final type = widget.type;
    return switch (type) {
      'house' || 'villa' => [
          _area(),
          _count('min_bedrooms', 'غرف النوم', [2, 3, 4, 5],
              explicitMinimum: true),
          _count('min_bathrooms', 'الحمامات', [1, 2, 3], explicitMinimum: true),
          _switch('has_parking', 'موقف سيارة'),
          _dropdown(
              'building_facade', 'واجهة المبنى', SmartSearchFilters.facades),
          if (type == 'villa') _switch('has_yard', 'حوش'),
        ],
      'land' => [
          _choice<String>(
              'land_use', 'نوع الأرض', {null: 'الكل', ...landUseOptions}),
          _area(),
          _streetWidth(),
          _dropdown(
              'building_facade', 'واجهة الأرض', SmartSearchFilters.facades),
        ],
      'apartment' => [
          _count('min_bedrooms', 'عدد الغرف', [1, 2, 3, 4, 5]),
          _dropdown('floor_number', 'الدور',
              DynamicPropertySchema.floorOptionsFor('apartment'),
              any: 'أي دور'),
          _switch('has_section_elevator', 'مصعد'),
          _switch('has_parking', 'موقف سيارة'),
        ],
      'building' => [
          _count('min_floors', 'عدد الأدوار', [2, 3, 4, 5, 6]),
          _count('min_total_units', 'عدد الوحدات', [2, 4, 6, 10]),
          _switch('has_section_elevator', 'مصعد'),
          _switch('has_parking', 'موقف سيارة'),
        ],
      'farm' => [
          _area(),
          _dropdown('farm_water_source', 'مصدر المياه', farmWaterSourceOptions),
          _dropdown('farm_crop_type', 'نوع الزراعة', farmCropTypeOptions),
        ],
      'shop' => [
          _area(),
          _count('min_shop_openings', 'عدد الفتحات', [1, 2, 3, 4]),
          _streetWidth(),
        ],
      'office' => [
          _area(),
          _count('min_office_rooms', 'عدد الغرف', [1, 2, 3, 4, 5]),
          _dropdown('floor_number', 'الدور', DynamicPropertySchema.floorOptions,
              any: 'أي دور'),
          _switch('has_section_elevator', 'مصعد'),
        ],
      _ => [_area()],
    };
  }

  Widget _footer(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final apply = AppButton(
            key: const ValueKey('section-filter-apply'),
            label: 'عرض النتائج',
            expand: true,
            onPressed: _apply,
          );
          final reset = AppButton(
            key: const ValueKey('section-filter-reset'),
            label: 'إعادة تعيين',
            expand: true,
            style: AppButtonStyle.outlined,
            onPressed: _reset,
          );
          if (constraints.maxWidth < 250 ||
              MediaQuery.textScalerOf(context).scale(14) > 22) {
            return Column(children: [apply, const SizedBox(height: 8), reset]);
          }
          return Row(children: [
            Expanded(child: apply),
            const SizedBox(width: 8),
            Expanded(child: reset),
          ]);
        },
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final purposeLabel = widget.purpose == 'rent' ? 'للإيجار' : 'للبيع';
    final header = Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(18, 0, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('تصفية ${_filterTitles[widget.type] ?? 'العقارات'}',
                    style: theme.textTheme.titleLarge),
                Text('${widget.typeLabel ?? 'عقارات'} $purposeLabel',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          AppIconButton(
            icon: Icons.close_rounded,
            tooltip: 'إغلاق التصفية',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
    final options = Padding(
      key: _optionsKey,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _controls(),
      ),
    );
    final actions = [
      if (_error case final error?)
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
          child: Semantics(
            liveRegion: true,
            child: Text(error,
                key: const ValueKey('section-filter-error'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error)),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
        child: _footer(context),
      ),
    ];
    const scrollKey = ValueKey('section-filter-options');

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final enlargedText =
                    MediaQuery.textScalerOf(context).scale(14) > 22;
                if (enlargedText || constraints.maxHeight < 360) {
                  // Give the title and actions room to wrap at accessibility
                  // text sizes and when the keyboard limits the viewport.
                  return SingleChildScrollView(
                    key: scrollKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [header, options, ...actions],
                    ),
                  );
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    Flexible(
                      child: SingleChildScrollView(
                        key: scrollKey,
                        child: options,
                      ),
                    ),
                    ...actions,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

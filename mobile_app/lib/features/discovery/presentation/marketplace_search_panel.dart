import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/app_components.dart';
import '../../account/data/auth_controller.dart';
import '../../map/presentation/map_discovery_toolbar.dart';
import '../../map/presentation/map_screen.dart';
import '../../properties/domain/property_details.dart';
import '../../properties/domain/property_schema.dart';
import '../../properties/presentation/adaptive_property_photo.dart';
import '../data/marketplace_search_session.dart';
import '../data/marketplace_repository.dart';
import '../data/published_listing_suggestions.dart';
import '../domain/smart_search_filters.dart';
import 'smart_search_filter_editor.dart';
import 'assisted_search_screen.dart';

enum _MapSearchAction { address, assistant }
enum _MapFilterAction { drawArea, clearArea, landUse }

/// The public search editor is shared by Home and the map's search sheet.
class MarketplaceSearchPanel extends ConsumerStatefulWidget {
  const MarketplaceSearchPanel({
    this.onMap = false,
    this.onOpenMap,
    this.openFilters = false,
    this.mapActions,
    this.onMapBack,
    this.mapSearchEditor = false,
    super.key,
  });
  final bool onMap;
  final VoidCallback? onOpenMap;
  final bool openFilters;
  final MapSearchActions? mapActions;
  final VoidCallback? onMapBack;
  final bool mapSearchEditor;
  @override
  ConsumerState<MarketplaceSearchPanel> createState() => _MarketplaceSearchPanelState();
}

class _MarketplaceSearchPanelState extends ConsumerState<MarketplaceSearchPanel> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _minPrice = TextEditingController(), _maxPrice = TextEditingController();
  final _priceFields = GlobalKey();
  String? _priceSignature, _priceError;
  bool _priceDirty = false;
  @override
  void initState() {
    super.initState();
    if (widget.openFilters) WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _editFilters(); });
  }
  @override
  void dispose() { _text.dispose(); _focus.dispose(); _minPrice.dispose(); _maxPrice.dispose(); super.dispose(); }
  Future<void> _submit() async {
    final controller = ref.read(marketplaceSearchControllerProvider.notifier);
    final text = controller.suggestionFilters(onMap: widget.onMap).values['search']?.toString() ?? '';
    if (text.length > 120) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختصر البحث أو استخدام الأرض إلى ١٢٠ حرفًا.')));
      return;
    }
    if (!widget.onMap && !_applyPriceRange()) return;
    // Clear the editor's focus history before a later push can restore it.
    FocusManager.instance.primaryFocus?.unfocus();
    final submission = controller.submit(onMap: widget.onMap);
    if (widget.mapSearchEditor) Navigator.of(context).pop();
    await submission;
  }
  Future<void> _editFilters([String? focus]) async {
    final controller = ref.read(marketplaceSearchControllerProvider.notifier);
    final ui = controller.uiFor(onMap: widget.onMap);
    final token = controller.mapJourneyToken;
    final actor = ref.read(authControllerProvider).asData?.value?.id;
    final pending = _priceDirty ? _validatedPriceValues() : ui.criteria.values;
    if (pending == null) return;
    FocusScope.of(context).unfocus();
    final actions = widget.mapActions;
    final value = await AppBottomSheet.show<Object>(context, builder: (sheetContext) => SmartSearchFilterEditor(
      initial: SmartSearchFilters.fromMap({...pending, if (ui.draftQuery.isNotEmpty) 'search': ui.draftQuery}),
      focus: focus, rangesFirst: widget.onMap,
      extraActions: widget.onMap && focus == null ? Wrap(spacing: 8, children: [
        if (actions != null) TextButton.icon(
          key: const ValueKey('map-draw-area'),
          onPressed: () => Navigator.of(sheetContext).pop(_MapFilterAction.drawArea),
          icon: const Icon(Icons.gesture_rounded),
          label: const Text('رسم منطقة'),
        ),
        if (actions?.hasDrawnArea == true) TextButton(
          key: const ValueKey('map-clear-area'),
          onPressed: () => Navigator.of(sheetContext).pop(_MapFilterAction.clearArea),
          child: const Text('إزالة المنطقة المرسومة'),
        ),
        if (ui.landUse.isNotEmpty || ui.criteria.values['type'] == 'land') TextButton(
          key: const ValueKey('published-filter-land-use'),
          onPressed: () => Navigator.of(sheetContext).pop(_MapFilterAction.landUse),
          child: Text(ui.landUse.isEmpty ? 'الاستخدام المعلن' : 'الاستخدام المعلن: ${ui.landUse}'),
        ),
      ]) : null));
    if (!mounted || value == null || actor != ref.read(authControllerProvider).asData?.value?.id ||
        !identical(controller, ref.read(marketplaceSearchControllerProvider.notifier)) ||
        (widget.onMap && !controller.isMapJourneyCurrent(token))) { return; }
    switch (value) {
      case SmartSearchFilters():
        controller.edit(value.values['search']?.toString() ?? '', onMap: widget.onMap);
        controller.applyFilters(value, onMap: widget.onMap);
      case _MapFilterAction.drawArea:
        actions?.onDrawArea();
      case _MapFilterAction.clearArea:
        actions?.onClearArea();
      case _MapFilterAction.landUse:
        await _landUse();
    }
  }
  Future<void> _landUse() async {
    final controller = ref.read(marketplaceSearchControllerProvider.notifier);
    final token = controller.mapJourneyToken;
    final actor = ref.read(authControllerProvider).asData?.value?.id;
    FocusScope.of(context).unfocus();
    final value = await AppBottomSheet.show<String>(context, builder: (_) => _LandUseChoice(
      initial: controller.uiFor(onMap: widget.onMap).landUse));
    if (!mounted || value == null || actor != ref.read(authControllerProvider).asData?.value?.id ||
        !identical(controller, ref.read(marketplaceSearchControllerProvider.notifier)) ||
        (widget.onMap && !controller.isMapJourneyCurrent(token))) { return; }
    controller.setLandUse(value, onMap: widget.onMap);
  }

  Future<void> _showMapSearch() async {
    final controller = ref.read(marketplaceSearchControllerProvider.notifier);
    final token = controller.mapJourneyToken;
    final selection = await AppBottomSheet.show<_MapSearchAction>(context, builder: (context) =>
      MarketplaceSearchPanel(onMap: true, mapSearchEditor: true, mapActions: widget.mapActions));
    if (!mounted || !identical(controller, ref.read(marketplaceSearchControllerProvider.notifier)) ||
        !controller.isMapJourneyCurrent(token)) {
      return;
    }
    controller.stopEditing(onMap: true);
    switch (selection) {
      case _MapSearchAction.address:
        widget.mapActions?.onFindAddress?.call();
      case _MapSearchAction.assistant:
        widget.mapActions?.onSmartSearch();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(marketplaceSearchControllerProvider);
    final controller = ref.read(marketplaceSearchControllerProvider.notifier);
    final ui = controller.uiFor(onMap: widget.onMap);
    if (widget.onMap && !widget.mapSearchEditor) {
      return MapDiscoveryToolbar(
        filters: ui.criteria,
        extraFilters: ui.landUse.isNotEmpty || widget.mapActions?.hasDrawnArea == true,
        onBack: widget.onMapBack,
        onPurpose: (purpose) => controller.setChoice('purpose', purpose, onMap: true),
        onType: (type) => controller.toggleType(type, onMap: true),
        onSearch: _showMapSearch,
        onFilters: _editFilters,
      );
    }
    if (_text.text != ui.draftQuery) {
      _text.value = TextEditingValue(text: ui.draftQuery, selection: TextSelection.collapsed(offset: ui.draftQuery.length));
    }
    if (!widget.onMap) _syncPriceRange(ui.criteria);
    final theme = Theme.of(context), values = ui.criteria.values;
    final active = ui.active || widget.onMap;
    final key = publishedSuggestionKey(controller.suggestionFilters(onMap: widget.onMap));
    final showSuggestions = ui.editing && ui.draftQuery.trim().isNotEmpty && ui.draftQuery.trim().length <= 120;
    final addressAction = widget.mapActions?.onFindAddress;
    final field = TextField(key: ValueKey(widget.onMap ? 'map-published-search-input' : 'home-search'),
      controller: _text, focusNode: _focus, autofocus: widget.mapSearchEditor, maxLines: 1, minLines: 1, maxLength: 120,
      keyboardType: TextInputType.text, textInputAction: TextInputAction.search,
      inputFormatters: [FilteringTextInputFormatter.singleLineFormatter],
      onTap: () => controller.begin(onMap: widget.onMap), onChanged: (text) => controller.edit(text, onMap: widget.onMap), onSubmitted: (_) => unawaited(_submit()),
      decoration: InputDecoration(hintText: 'ابحث عن عقار…', counterText: '',
        isDense: widget.onMap ? true : null,
        contentPadding: widget.onMap ? const EdgeInsets.symmetric(horizontal: 12, vertical: 12) : null,
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _text.text.isEmpty ? null : IconButton(
          key: const ValueKey('published-search-clear'), tooltip: 'مسح النص',
          onPressed: () { controller.edit('', onMap: widget.onMap); _focus.requestFocus(); }, icon: const Icon(Icons.close))));
    final large = MediaQuery.textScalerOf(context).scale(14) > 23;
    final execute = large ? IconButton.filledTonal(key: const ValueKey('published-search-submit'),
      tooltip: 'تنفيذ البحث', onPressed: () => unawaited(_submit()), icon: const Icon(Icons.search))
      : TextButton(key: const ValueKey('published-search-submit'),
          onPressed: () => unawaited(_submit()), child: const Text('تنفيذ'));
    final purposeChips = <Widget>[
      for (final e in const {'rent': 'إيجار', 'sale': 'بيع'}.entries)
        ChoiceChip(key: ValueKey('published-purpose-${e.key}'), label: Text(e.value),
          selected: values['purpose'] == e.key,
          onSelected: (_) => controller.setChoice('purpose', e.key, onMap: widget.onMap)),
    ];
    final typeChips = <Widget>[
      for (final e in const {'apartment': 'شقق', 'house': 'منازل', 'villa': 'فلل',
        'land': 'أراضٍ', 'shop': 'محلات', 'office': 'مكاتب', 'building': 'عمائر', 'farm': 'مزارع'}.entries)
        ChoiceChip(key: ValueKey('published-type-${e.key}'), label: Text(e.value),
          selected: ui.criteria.selectedTypes.contains(e.key),
          showCheckmark: widget.onMap ? false : null,
          onSelected: (_) => controller.toggleType(e.key, onMap: widget.onMap)),
    ];
    final appliedChips = <Widget>[
      for (final chip in ui.criteria.chips)
        if (widget.onMap
            ? !chip.$1.startsWith('type:') && !const ['type', 'purpose'].contains(chip.$1)
            : !_representedByQuickFilter(chip.$1))
          InputChip(
            key: ValueKey('published-selected-${chip.$1}'),
            label: Text(chip.$2),
            onPressed: () => _editFilters(chip.$1),
            onDeleted: () => controller.remove(chip.$1, onMap: widget.onMap),
          ),
      if (ui.landUse.isNotEmpty)
        InputChip(label: Text('الاستخدام المعلن: ${ui.landUse}'), onPressed: _landUse,
          onDeleted: () => controller.setLandUse('', onMap: widget.onMap))
      else if (widget.onMap && values['type'] == 'land')
        ActionChip(key: const ValueKey('published-filter-land-use'),
          label: const Text('الاستخدام المعلن'), onPressed: _landUse),
      if (widget.mapActions?.hasDrawnArea == true)
        InputChip(key: const ValueKey('map-drawn-area'),
          avatar: const Icon(Icons.gesture_rounded, size: 18), label: const Text('منطقة مرسومة'),
          onPressed: widget.mapActions!.onDrawArea, onDeleted: widget.mapActions!.onClearArea),
    ];
    final suggestions = _PublishedSuggestions(suggestionKey: key, onOpen: (row) async {
      _focus.unfocus();
      await context.push('/properties/${row.id}', extra: row);
      if (mounted) ref.invalidate(publishedListingSuggestionsProvider(key));
    });
    if (widget.mapSearchEditor) {
      final scheme = theme.colorScheme;
      return SafeArea(top: false, child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('بحث', style: theme.textTheme.titleLarge)),
            IconButton(tooltip: 'إغلاق', onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close)),
          ]),
          field,
          if (showSuggestions) suggestions,
          if (appliedChips.isNotEmpty) _ChipRail(children: appliedChips),
          const SizedBox(height: 8),
          FilledButton(key: const ValueKey('published-search-submit'),
            style: FilledButton.styleFrom(backgroundColor: scheme.tertiary, foregroundColor: scheme.onTertiary),
            onPressed: () => unawaited(_submit()), child: const Text('بحث')),
          Wrap(spacing: 8, children: [
            if (addressAction != null) TextButton.icon(
              key: const ValueKey('marketplace-map-find-address'),
              onPressed: () => Navigator.of(context).pop(_MapSearchAction.address),
              icon: const Icon(Icons.travel_explore),
              label: const Text('انتقل إلى حي أو عنوان'),
            ),
            if (widget.mapActions != null) TextButton.icon(
              key: const ValueKey('map-smart-search'),
              onPressed: () => Navigator.of(context).pop(_MapSearchAction.assistant),
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('بحث ذكي'),
            ),
          ]),
        ]),
      ));
    }
    return Material(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(16),
      child: Padding(padding: EdgeInsets.all(widget.onMap ? 8 : 10), child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [Expanded(child: field),
          const SizedBox(width: 4), execute,
          if (widget.onOpenMap != null) IconButton(key: const ValueKey('home-map'), tooltip: 'الخريطة',
            onPressed: widget.onOpenMap, icon: const Icon(Icons.map_outlined))]),
        if (active && !ui.editing) ...[
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: _ChipRail(children: purposeChips)),
            const SizedBox(width: 6),
            if (large) IconButton.outlined(key: const ValueKey('published-filter-more'),
              tooltip: 'تصفية', onPressed: () => _editFilters(), icon: const Icon(Icons.tune))
            else OutlinedButton.icon(key: const ValueKey('published-filter-more'),
              onPressed: () => _editFilters(), icon: const Icon(Icons.tune, size: 18),
              label: Text(ui.criteria.chips.isEmpty ? 'تصفية' : 'تصفية (${arabicDigits(ui.criteria.chips.length.toString())})'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))),
          ]),
          _ChipRail(children: typeChips),
          LayoutBuilder(builder: (_, space) => Wrap(spacing: 6, runSpacing: 6, children: [
            if ((ui.criteria.selectedTypes.isNotEmpty || values.containsKey('min_bedrooms')) && DynamicPropertySchema.appliesToFilters('bedrooms', values))
              _quickFilter('min_bedrooms', 'الغرف', Icons.bed_outlined, large ? space.maxWidth : 110),
            if ((ui.criteria.selectedTypes.isNotEmpty || values.containsKey('min_bathrooms')) && DynamicPropertySchema.appliesToFilters('bathrooms', values))
              _quickFilter('min_bathrooms', 'الحمامات', Icons.bathtub_outlined, large ? space.maxWidth : 110),
            if (DynamicPropertySchema.appliesToFilters('area_value', values))
              ActionChip(key: const ValueKey('published-filter-area'), label: const Text('المساحة'),
                onPressed: () => _editFilters('min_area_m2')),
            if (values['type'] == 'land') ActionChip(key: const ValueKey('published-filter-land-use'),
              label: const Text('الاستخدام المعلن'), onPressed: _landUse),
          ])),
          _priceRange(ui.criteria),
        ],
        if (active && (!ui.editing || widget.onMap) && appliedChips.isNotEmpty)
          _ChipRail(children: appliedChips),
        if (showSuggestions) suggestions,
      ])));
  }

  bool _representedByQuickFilter(String key) =>
    key.startsWith('type:') || const ['type', 'purpose', 'min_bedrooms', 'min_bathrooms'].contains(key) ||
    key == 'budget';

  Widget _quickFilter(String field, String label, IconData icon, double width) {
    final filters = ref.read(marketplaceSearchControllerProvider.notifier).uiFor(onMap: widget.onMap).criteria;
    final selected = filters.values[field] != null;
    final summary = selected ? filters.chips.firstWhere((chip) => chip.$1 == field).$2 : label;
    final noun = field == 'min_bedrooms' ? 'غرف' : 'حمام';
    final text = selected ? '${arabicDigits(filters.values[field].toString())}+ $noun'
      : field == 'min_bedrooms' ? label : 'حمامات';
    final key = ValueKey(field == 'min_bedrooms' ? 'published-filter-rooms' : 'published-filter-bathrooms');
    return Tooltip(message: summary, child: SizedBox(width: width,
      child: ActionChip(key: key, avatar: Icon(icon, size: 16), label: Text(text),
        backgroundColor: selected ? Theme.of(context).colorScheme.primaryContainer : null,
        onPressed: () => _editFilters(field))));
  }

  void _syncPriceRange(SmartSearchFilters filters) {
    final signature = '${filters.values['min_price']}:${filters.values['max_price']}:${filters.values['currency']}';
    if (_priceSignature == signature) return;
    _priceSignature = signature;
    String priceText(Object? value) {
      if (value is double && value == value.truncateToDouble()) return value.toStringAsFixed(0);
      return value?.toString() ?? '';
    }
    _minPrice.text = priceText(filters.values['min_price']);
    _maxPrice.text = priceText(filters.values['max_price']);
    _priceDirty = false;
    _priceError = null;
  }

  // Keep the accepted budget editor's Arabic digits, separators and limits.
  String _budgetDigits(String text) {
    const digits = {'٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4',
      '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9', '٫': '.', '٬': '', ',': ''};
    return text.trim().split('').map((char) => digits[char] ?? char).join();
  }

  Map<String, dynamic>? _validatedPriceValues() {
    final next = Map<String, dynamic>.from(ref.read(marketplaceSearchControllerProvider.notifier)
      .uiFor(onMap: widget.onMap).criteria.values);
    for (final field in {'min_price': _minPrice, 'max_price': _maxPrice}.entries) {
      if (field.value.text.trim().isEmpty) { next.remove(field.key); continue; }
      final amount = double.tryParse(_budgetDigits(field.value.text));
      if (amount == null || !amount.isFinite || amount < 0 || amount > 1000000000000) {
        _showPriceError('أدخل أرقامًا صحيحة للسعر.');
        return null;
      }
      next[field.key] = amount;
    }
    if (next['min_price'] is num && next['max_price'] is num &&
        (next['min_price'] as num) > (next['max_price'] as num)) {
      _showPriceError('الحد الأدنى يجب ألا يتجاوز الحد الأعلى.');
      return null;
    }
    return next;
  }

  bool _applyPriceRange() {
    if (!_priceDirty) return true;
    final next = _validatedPriceValues();
    if (next == null) return false;
    setState(() { _priceDirty = false; _priceError = null; });
    ref.read(marketplaceSearchControllerProvider.notifier)
      .applyFilters(SmartSearchFilters.fromMap(next), onMap: widget.onMap);
    return true;
  }

  void _showPriceError(String message) {
    setState(() => _priceError = message);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final fields = _priceFields.currentContext;
      if (fields != null && mounted && _priceError == message) {
        unawaited(Scrollable.ensureVisible(fields, alignment: 1));
      }
    });
  }

  Widget _priceRange(SmartSearchFilters filters) {
    final theme = Theme.of(context);
    final valueStyle = theme.textTheme.bodyLarge;
    Widget input(String name, TextEditingController text, String label) => Semantics(
      identifier: 'published-filter-$name', child: TextField(
      key: ValueKey('published-filter-$name'), controller: text,
      maxLines: 1, maxLength: 24, textInputAction: TextInputAction.done,
      style: valueStyle, textDirection: TextDirection.ltr, textAlign: TextAlign.right,
      scrollPadding: const EdgeInsets.symmetric(vertical: 8),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => setState(() { _priceDirty = true; _priceError = null; }),
      onSubmitted: (_) { if (_applyPriceRange()) FocusScope.of(context).unfocus(); },
      decoration: InputDecoration(labelText: label, counterText: '', isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12))));
    return Padding(padding: const EdgeInsets.only(top: 4), child: LayoutBuilder(builder: (context, constraints) {
      final sample = TextPainter(text: TextSpan(text: '1000000', style: valueStyle),
        textDirection: TextDirection.ltr, textScaler: MediaQuery.textScalerOf(context))..layout();
      final pairWidth = (sample.width + 18) * 2 + 8;
      sample.dispose();
      final sideBySide = constraints.maxWidth >= pairWidth;
      final inlineApply = constraints.maxWidth >= pairWidth + 52;
      final minimum = input('min-price', _minPrice, 'من');
      final maximum = input('max-price', _maxPrice, 'إلى');
      final apply = Semantics(identifier: 'published-price-apply', child: IconButton(
        key: const ValueKey('published-price-apply'), tooltip: 'تطبيق نطاق السعر',
        onPressed: () { if (_applyPriceRange()) FocusScope.of(context).unfocus(); }, icon: const Icon(Icons.check)));
      final currency = Align(alignment: AlignmentDirectional.centerStart, child: TextButton(
        key: const ValueKey('published-filter-currency'), onPressed: () => _editFilters('budget'),
        child: Text('${filters.values['purpose'] == 'rent' ? 'الإيجار الشهري' : 'السعر'} · ${filters.currencyLabel}')));
      final fields = sideBySide
        ? Row(children: [Expanded(child: minimum), const SizedBox(width: 8), Expanded(child: maximum)])
        : Column(children: [minimum, const SizedBox(height: 8), maximum]);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (inlineApply) currency else Row(children: [Expanded(child: currency), apply]),
        Column(key: _priceFields, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (inlineApply) Row(children: [Expanded(child: fields), const SizedBox(width: 4), apply]) else fields,
          if (_priceError case final message?)
            Padding(padding: const EdgeInsets.only(top: 6), child: Semantics(liveRegion: true,
              child: Text(message, key: const ValueKey('published-price-error'),
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error)))),
        ]),
      ]);
    }));
  }

}

class _ChipRail extends StatelessWidget {
  const _ChipRail({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(scrollDirection: Axis.horizontal,
    child: Row(children: [for (final child in children) Padding(
      padding: const EdgeInsetsDirectional.only(end: 6), child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48), child: child))]));
}

class _PublishedSuggestions extends ConsumerWidget {
  const _PublishedSuggestions({required this.suggestionKey, required this.onOpen});
  final String suggestionKey;
  final void Function(PropertySummary) onOpen;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(publishedListingSuggestionsProvider(suggestionKey));
    final rows = value.hasError ? const <PropertySummary>[] : value.asData?.value
      ?? ref.read(publishedListingSuggestionsRepositoryProvider).cached(suggestionKey);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('إعلانات منشورة مقترحة')),
      if (value.isLoading) const LinearProgressIndicator(minHeight: 2),
      if (value.hasError) Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('تعذّر تحميل الاقتراحات. يمكنك تنفيذ بحثك أو المحاولة مجددًا.'),
        TextButton(onPressed: () => ref.invalidate(publishedListingSuggestionsProvider(suggestionKey)), child: const Text('إعادة المحاولة')),
      ]) else if (rows.isEmpty && !value.isLoading) const Padding(padding: EdgeInsets.all(12), child: Text('لا اقتراحات مطابقة الآن.')),
      if (rows.isNotEmpty) ...[
        if (value.isLoading) const Text('اقتراحات حديثة؛ جارٍ تحديثها.'),
        ConstrainedBox(constraints: const BoxConstraints(maxHeight: 250), child: ListView.builder(
          key: const ValueKey('published-suggestions'), shrinkWrap: true, primary: false, cacheExtent: 0,
          itemCount: rows.length, itemBuilder: (_, i) => PublishedListingSuggestionTile(
            key: ValueKey('published-suggestion-${rows[i].id}'), property: rows[i], onTap: () => onOpen(rows[i])))),
      ],
    ]);
  }
}

class PublishedListingSuggestionTile extends StatelessWidget {
  const PublishedListingSuggestionTile({required this.property, required this.onTap, super.key});
  final PropertySummary property;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = property, rent = p.purpose == 'rent', theme = Theme.of(context);
    return Semantics(button: true, child: InkWell(onTap: onTap, child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 64, height: 72, child: ClipRRect(borderRadius: BorderRadius.circular(8),
            child: p.mainImage == null ? ColoredBox(color: theme.colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.home_outlined)) : AdaptivePropertyPhoto(url: p.mainImage!))),
          const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
            Text('${rent ? 'للإيجار' : 'للبيع'} · ${SmartSearchFilters.types[p.type] ?? 'عقار'}', style: theme.textTheme.bodySmall),
            if (p.address?.isNotEmpty == true) Text(p.address!, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
          ])),
        ]),
        Align(alignment: AlignmentDirectional.centerStart, child: FittedBox(fit: BoxFit.scaleDown,
          child: AppPropertyPrice(price: (rent ? p.monthlyRent ?? p.price : p.price).toString(), currency: p.currency,
            suffix: rent && p.monthlyRent != null ? 'شهريًا' : null))),
      ]))));
  }
}

class _LandUseChoice extends StatefulWidget {
  const _LandUseChoice({required this.initial});
  final String initial;
  @override
  State<_LandUseChoice> createState() => _LandUseChoiceState();
}
class _LandUseChoiceState extends State<_LandUseChoice> {
  late final _text = TextEditingController(text: widget.initial);
  @override
  void dispose() { _text.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => SafeArea(top: false, child: SingleChildScrollView(padding: EdgeInsets.fromLTRB(
    18, 18, 18, MediaQuery.viewInsetsOf(context).bottom + 18), child: Column(mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('استخدام الأرض المعلن', style: Theme.of(context).textTheme.titleMedium),
      const Text('ابحث عن الاستخدام المذكور في وصف الإعلان؛ لا يثبت ذلك تصنيف الأرض النظامي.'),
      TextField(controller: _text, maxLength: 40, maxLines: 1, textInputAction: TextInputAction.search,
        decoration: const InputDecoration(labelText: 'مثل سكني أو تجاري أو زراعي'),
        onSubmitted: (_) => Navigator.pop(context, _text.text)),
      TextButton(onPressed: () => Navigator.pop(context, _text.text), child: const Text('تطبيق')),
      TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('كل الاستخدامات')),
    ])));
}

class MarketplaceSearchMapScreen extends ConsumerStatefulWidget {
  const MarketplaceSearchMapScreen({this.embedded = false, this.active = true, super.key});
  final bool embedded, active;
  @override
  ConsumerState<MarketplaceSearchMapScreen> createState() => _MarketplaceSearchMapScreenState();
}
class _MarketplaceSearchMapScreenState extends ConsumerState<MarketplaceSearchMapScreen> {
  bool _openingSmartSearch = false, _entryQueued = false, _routeExited = false;
  MarketplaceSearchController? _mapJourney;
  int? _mapToken;

  @override
  void initState() {
    super.initState();
    // Home can seed the map before pushing its route. Own that token even if
    // navigation removes this page before its first post-frame callback.
    final journey = ref.read(marketplaceSearchControllerProvider.notifier);
    final token = journey.mapJourneyToken;
    if (journey.isMapJourneyCurrent(token)) { _mapJourney = journey; _mapToken = token; }
  }

  void _releaseMap() {
    final token = _mapToken;
    _mapToken = null;
    if (token != null) _mapJourney?.leaveMap(token);
  }

  @override
  void dispose() { _routeExited = true; _releaseMap(); super.dispose(); }

  Future<void> _openSmartSearch() async {
    if (_openingSmartSearch) return;
    _openingSmartSearch = true;
    FocusScope.of(context).unfocus();
    ref.read(marketplaceSearchControllerProvider.notifier).stopEditing(onMap: true);
    final initial = SmartSearchFilters.fromMap(Map<String, dynamic>.from(
      ref.read(marketplaceMapResultsProvider).filters.values));
    try {
      await Navigator.of(context).push<void>(MaterialPageRoute(
        settings: const RouteSettings(name: 'map-smart-search'),
        builder: (_) => AssistedSearchScreen(initialMapMode: true, entryFilters: initial)));
      // The assistant owns its copied criteria. Returning restores this map.
    } finally {
      _openingSmartSearch = false;
    }
  }
  @override
  Widget build(BuildContext context) {
    ref.watch(marketplaceSearchControllerProvider);
    final journey = ref.read(marketplaceSearchControllerProvider.notifier);
    final actor = ref.watch(authControllerProvider.select((value) => value.asData?.value?.id));
    final visible = widget.active;
    final routeCurrent = ModalRoute.of(context)?.isCurrent != false;
    if (!visible) _releaseMap();
    if (visible && routeCurrent && !_routeExited && (!identical(_mapJourney, journey) || _mapToken == null) && !_entryQueued) {
      _entryQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _entryQueued = false;
        if (!mounted || _routeExited || actor != ref.read(authControllerProvider).asData?.value?.id ||
            !widget.active) { return; }
        if (!identical(journey, ref.read(marketplaceSearchControllerProvider.notifier))) {
          setState(() {});
          return;
        }
        if (ModalRoute.of(context)?.isCurrent == false) return;
        _releaseMap();
        _mapJourney = journey;
        _mapToken = journey.enterMap();
      });
    }
    final filters = ref.watch(marketplaceMapResultsProvider.select((state) => state.filters));
    final homeLocation = ref.watch(homeLocationProvider);
    final needsProvinceHint = !filters.hasMapArea &&
      !(filters.values['latitude'] is num && filters.values['longitude'] is num) &&
      filters.values.keys.any((key) => const ['governorate', 'governorate_code'].contains(key));
    final cameraHint = mapSearchInitialCamera(filters, homeLocation) ??
      (needsProvinceHint
        ? mapSearchInitialCamera(filters, homeLocation, ref.watch(homeLocationsProvider).asData?.value ?? const []) : null);
    final mapToken = _mapToken;
    final hasJourney = mapToken != null && identical(_mapJourney, journey) && journey.isMapJourneyCurrent(mapToken);
    return PopScope(onPopInvokedWithResult: (didPop, _) { if (didPop) { _routeExited = true; _releaseMap(); } },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: !visible || !hasJourney ? const SizedBox.shrink()
          : SafeArea(bottom: false, child: MapScreen(key: ValueKey('marketplace-map-$actor-$mapToken'), sharedSearchJourney: true,
          searchSessionProvider: marketplaceMapResultsProvider, enforceViewport: true,
          toolbarAboveMap: true, collapseResults: true, cameraCenterHint: cameraHint, onSmartSearch: _openSmartSearch,
          isJourneyCurrent: () => mounted && !_routeExited && widget.active && _mapToken == mapToken &&
            identical(_mapJourney, journey) && journey.isMapJourneyCurrent(mapToken),
          onMapInteraction: () { FocusScope.of(context).unfocus(); journey.stopEditing(onMap: true); },
          searchToolbarBuilder: (_, actions) => SizedBox(key: const ValueKey('marketplace-search-toolbar'),
            child: MarketplaceSearchPanel(onMap: true, mapActions: actions,
              onMapBack: widget.embedded ? null : () => Navigator.of(context).maybePop()))))));
  }
}

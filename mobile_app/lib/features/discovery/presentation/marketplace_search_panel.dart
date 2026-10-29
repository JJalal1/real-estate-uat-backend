import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/app_components.dart';
import '../../account/data/auth_controller.dart';
import '../../map/presentation/map_screen.dart';
import '../../properties/domain/property_details.dart';
import '../../properties/domain/property_schema.dart';
import '../../properties/presentation/adaptive_property_photo.dart';
import '../data/marketplace_search_session.dart';
import '../data/published_listing_suggestions.dart';
import '../domain/smart_search_filters.dart';
import 'smart_search_filter_editor.dart';
import 'smart_search_assistant.dart';
import 'assisted_search_screen.dart';

/// The same editable input, IME action and public suggestions on Home and map.
class MarketplaceSearchPanel extends ConsumerStatefulWidget {
  const MarketplaceSearchPanel({this.onMap = false, this.onOpenMap, this.openFilters = false, this.mapActions, super.key});
  final bool onMap;
  final VoidCallback? onOpenMap;
  final bool openFilters;
  final MapSearchActions? mapActions;
  @override
  ConsumerState<MarketplaceSearchPanel> createState() => _MarketplaceSearchPanelState();
}

class _MarketplaceSearchPanelState extends ConsumerState<MarketplaceSearchPanel> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  @override
  void initState() {
    super.initState();
    if (widget.openFilters) WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _editFilters(); });
  }
  @override
  void dispose() { _text.dispose(); _focus.dispose(); super.dispose(); }
  Future<void> _submit() async {
    final controller = ref.read(marketplaceSearchControllerProvider.notifier);
    final text = controller.suggestionFilters(onMap: widget.onMap).values['search']?.toString() ?? '';
    if (text.length > 120) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختصر البحث أو استخدام الأرض إلى ١٢٠ حرفًا.')));
      return;
    }
    _focus.unfocus();
    await controller.submit();
  }
  Future<void> _editFilters([String? focus]) async {
    final ui = ref.read(marketplaceSearchControllerProvider);
    _focus.unfocus();
    final value = await AppBottomSheet.show<SmartSearchFilters>(context, builder: (_) => SmartSearchFilterEditor(
      initial: SmartSearchFilters.fromMap({...ui.criteria.values, if (ui.draftQuery.isNotEmpty) 'search': ui.draftQuery}), focus: focus));
    if (!mounted || value == null) return;
    final controller = ref.read(marketplaceSearchControllerProvider.notifier);
    controller.edit(value.values['search']?.toString() ?? '');
    controller.applyFilters(value);
  }
  Future<void> _landUse() async {
    _focus.unfocus();
    final value = await AppBottomSheet.show<String>(context, builder: (_) => _LandUseChoice(
      initial: ref.read(marketplaceSearchControllerProvider).landUse));
    if (mounted && value != null) ref.read(marketplaceSearchControllerProvider.notifier).setLandUse(value);
  }

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(marketplaceSearchControllerProvider);
    final controller = ref.read(marketplaceSearchControllerProvider.notifier);
    if (_text.text != ui.draftQuery) {
      _text.value = TextEditingValue(text: ui.draftQuery, selection: TextSelection.collapsed(offset: ui.draftQuery.length));
    }
    final theme = Theme.of(context), values = ui.criteria.values;
    final active = ui.active || widget.onMap;
    final key = publishedSuggestionKey(controller.suggestionFilters(onMap: widget.onMap));
    final showSuggestions = ui.editing && ui.draftQuery.trim().isNotEmpty && ui.draftQuery.trim().length <= 120;
    final field = TextField(key: ValueKey(widget.onMap ? 'map-published-search-input' : 'home-search'),
      controller: _text, focusNode: _focus, maxLines: 1, minLines: 1, maxLength: 120,
      keyboardType: TextInputType.text, textInputAction: TextInputAction.search,
      inputFormatters: [FilteringTextInputFormatter.singleLineFormatter],
      onTap: controller.begin, onChanged: controller.edit, onSubmitted: (_) => unawaited(_submit()),
      decoration: InputDecoration(hintText: 'ابحث عن عقار…', counterText: '',
        prefixIcon: const Icon(Icons.search), suffixIcon: _text.text.isEmpty ? null : IconButton(
          key: const ValueKey('published-search-clear'), tooltip: 'مسح النص',
          onPressed: () { controller.edit(''); _focus.requestFocus(); }, icon: const Icon(Icons.close))));
    final execute = TextButton(key: const ValueKey('published-search-submit'),
      onPressed: () => unawaited(_submit()), child: const Text('تنفيذ'));
    final large = MediaQuery.textScalerOf(context).scale(14) > 23;
    final mapTools = widget.mapActions == null ? const <Widget>[] : <Widget>[
      const SizedBox(width: 4),
      IconButton.outlined(key: const ValueKey('map-draw-area'), tooltip: 'رسم منطقة على الخريطة',
        isSelected: widget.mapActions!.hasDrawnArea, onPressed: () {
          _focus.unfocus();
          widget.mapActions!.onDrawArea();
        }, icon: const Icon(Icons.gesture_rounded)),
      const SizedBox(width: 4),
      IconButton.outlined(key: const ValueKey('map-smart-search'), tooltip: 'البحث الذكي',
        onPressed: () { _focus.unfocus(); widget.mapActions!.onSmartSearch(); },
        icon: const SmartSearchRobotIcon()),
    ];
    return Material(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(16),
      child: Padding(padding: const EdgeInsets.all(10), child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (large) ...[field, Row(mainAxisAlignment: MainAxisAlignment.end, children: [execute, ...mapTools,
          if (widget.onOpenMap != null) IconButton(key: const ValueKey('home-map'), tooltip: 'الخريطة',
            onPressed: widget.onOpenMap, icon: const Icon(Icons.map_outlined))])]
        else Row(children: [Expanded(child: field), const SizedBox(width: 4), execute,
          if (widget.onOpenMap != null) IconButton(key: const ValueKey('home-map'), tooltip: 'الخريطة',
            onPressed: widget.onOpenMap, icon: const Icon(Icons.map_outlined))]),
        if (active && (!ui.editing || widget.onMap)) ...[
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: _ChipRail(children: [
              for (final e in const {'rent': 'إيجار', 'sale': 'بيع'}.entries)
                ChoiceChip(key: ValueKey('published-purpose-${e.key}'), label: Text(e.value),
                  selected: values['purpose'] == e.key,
                  onSelected: (_) => controller.setChoice('purpose', e.key)),
            ])),
            const SizedBox(width: 6),
            if (large) IconButton.outlined(key: ValueKey(widget.onMap ? 'published-map-filters' : 'published-filter-more'),
              tooltip: 'تصفية', onPressed: () => _editFilters(), icon: const Icon(Icons.tune))
            else OutlinedButton.icon(key: ValueKey(widget.onMap ? 'published-map-filters' : 'published-filter-more'),
              onPressed: () => _editFilters(), icon: const Icon(Icons.tune, size: 18),
              label: Text(ui.criteria.chips.isEmpty ? 'تصفية' : 'تصفية (${arabicDigits(ui.criteria.chips.length.toString())})'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))),
          ]),
          Row(children: [
            Expanded(child: _ChipRail(children: [
              for (final e in const {'all': 'كل الأنواع', 'apartment': 'شقق', 'house': 'منازل', 'villa': 'فلل',
                'land': 'أراضٍ', 'shop': 'محلات', 'office': 'مكاتب', 'building': 'عمائر', 'farm': 'مزارع'}.entries)
                ChoiceChip(key: ValueKey('published-type-${e.key}'), label: Text(e.value),
                  selected: e.key == 'all' ? values['type'] == null : values['type'] == e.key,
                  onSelected: (_) => controller.setChoice('type', e.key == 'all' ? null : e.key)),
            ])),
            if (!large) ...mapTools,
          ]),
          LayoutBuilder(builder: (_, space) => Wrap(spacing: 6, runSpacing: 6, children: [
            if ((values['type'] != null || values.containsKey('min_bedrooms')) && DynamicPropertySchema.applies('bedrooms', values))
              _quickFilter('min_bedrooms', 'الغرف', Icons.bed_outlined, large ? space.maxWidth : 110),
            if ((values['type'] != null || values.containsKey('min_bathrooms')) && DynamicPropertySchema.applies('bathrooms', values))
              _quickFilter('min_bathrooms', 'الحمامات', Icons.bathtub_outlined, large ? space.maxWidth : 110),
            _maximumPrice(ui.criteria, large ? space.maxWidth : 128),
            if (DynamicPropertySchema.applies('area_value', values))
              ActionChip(key: const ValueKey('published-filter-area'), label: const Text('المساحة'),
                onPressed: () => _editFilters('min_area_m2')),
            if (values['type'] == 'land') ActionChip(key: const ValueKey('published-filter-land-use'),
              label: const Text('الاستخدام المعلن'), onPressed: _landUse),
          ])),
          if (ui.criteria.chips.any((e) => !_representedByQuickFilter(e.$1, values)) ||
              ui.landUse.isNotEmpty || widget.mapActions?.hasDrawnArea == true)
            _ChipRail(children: [
              for (final chip in ui.criteria.chips.where((e) => !_representedByQuickFilter(e.$1, values)))
                InputChip(key: ValueKey('published-selected-${chip.$1}'), label: Text(chip.$2),
                  onPressed: () => _editFilters(chip.$1), onDeleted: () => controller.remove(chip.$1)),
              if (ui.landUse.isNotEmpty) InputChip(label: Text('الاستخدام المعلن: ${ui.landUse}'),
                onPressed: _landUse, onDeleted: () => controller.setLandUse('')),
              if (widget.mapActions?.hasDrawnArea == true) InputChip(
                key: const ValueKey('map-drawn-area'), avatar: const Icon(Icons.gesture_rounded, size: 18),
                label: const Text('منطقة مرسومة'), onPressed: widget.mapActions!.onDrawArea,
                onDeleted: widget.mapActions!.onClearArea),
            ]),
        ],
        if (showSuggestions) _PublishedSuggestions(suggestionKey: key, onOpen: (row) async {
          _focus.unfocus();
          await context.push('/properties/${row.id}', extra: row);
          if (mounted) ref.invalidate(publishedListingSuggestionsProvider(key));
        }),
      ])));
  }

  bool _representedByQuickFilter(String key, Map<String, dynamic> values) =>
    const ['type', 'purpose', 'min_bedrooms', 'min_bathrooms'].contains(key) ||
    (key == 'budget' && values['min_price'] == null);

  Widget _quickFilter(String field, String label, IconData icon, double width) {
    final filters = ref.watch(marketplaceSearchControllerProvider).criteria;
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

  Widget _maximumPrice(SmartSearchFilters filters, double width) {
    final max = filters.values['max_price'];
    final value = max is num ? '${arabicDigits(mapPropertyPriceLabel(max.toDouble()))} ${filters.currencyLabel}' : null;
    return SizedBox(width: width,
      child: OutlinedButton(key: const ValueKey('published-filter-max-price'),
        onPressed: () => _editFilters('max_price'),
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48),
          backgroundColor: value == null ? null : Theme.of(context).colorScheme.primaryContainer,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(filters.values['purpose'] == 'rent' ? 'أعلى إيجار' : 'أعلى سعر'),
          if (value != null) Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ])));
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
  const MarketplaceSearchMapScreen({this.embedded = false, super.key});
  final bool embedded;
  @override
  ConsumerState<MarketplaceSearchMapScreen> createState() => _MarketplaceSearchMapScreenState();
}
class _MarketplaceSearchMapScreenState extends ConsumerState<MarketplaceSearchMapScreen> {
  final _toolbarSizeKey = GlobalKey();
  double _toolbarHeight = 0;
  bool _measuring = false;
  bool _openingSmartSearch = false;

  Future<void> _openSmartSearch() async {
    if (_openingSmartSearch) return;
    _openingSmartSearch = true;
    FocusScope.of(context).unfocus();
    ref.read(marketplaceSearchControllerProvider.notifier).stopEditing();
    final actor = ref.read(authControllerProvider).asData?.value?.id;
    final initial = ref.read(marketplaceMapResultsProvider).filters;
    var selected = initial;
    try {
      await Navigator.of(context).push<void>(MaterialPageRoute(
        settings: const RouteSettings(name: 'map-smart-search'),
        builder: (_) => AssistedSearchScreen(entryFilters: initial,
          onFiltersChanged: (filters) => selected = filters)));
      if (!mounted || actor != ref.read(authControllerProvider).asData?.value?.id) return;
      if (initial.values.length == selected.values.length &&
          initial.values.entries.every((entry) => selected.values[entry.key] == entry.value)) { return; }
      ref.read(marketplaceSearchControllerProvider.notifier).adoptMapSearch(selected);
    } finally {
      _openingSmartSearch = false;
    }
  }
  void _measureToolbar() {
    if (_measuring) return;
    _measuring = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measuring = false;
      if (!mounted) return;
      final height = _toolbarSizeKey.currentContext?.size?.height;
      if (height != null && (height - _toolbarHeight).abs() > 1) setState(() => _toolbarHeight = height);
    });
  }
  @override
  Widget build(BuildContext context) {
    _measureToolbar();
    final ui = ref.watch(marketplaceSearchControllerProvider);
    final actor = ref.watch(authControllerProvider.select((value) => value.asData?.value?.id));
    if (!ui.mapOpen) { WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && actor == ref.read(authControllerProvider).asData?.value?.id &&
          !ref.read(marketplaceSearchControllerProvider).mapOpen &&
          ModalRoute.of(context)?.isCurrent != false) {
        ref.read(marketplaceSearchControllerProvider.notifier).enterMap();
      }
    }); }
    return PopScope(onPopInvokedWithResult: (didPop, _) {
      if (didPop) ref.read(marketplaceSearchControllerProvider.notifier).leaveMap();
    }, child: Scaffold(appBar: AppBar(title: const Text('البحث على الخريطة', maxLines: 2),
      toolbarHeight: (56 + (MediaQuery.textScalerOf(context).scale(18) - 18) * 2).clamp(56,116).toDouble(),
      automaticallyImplyLeading: !widget.embedded),
      resizeToAvoidBottomInset: true, body: LayoutBuilder(builder: (context, viewport) {
        final height = viewport.maxHeight > 0 ? viewport.maxHeight : 1.0;
        // Reserve a real, visible map strip between the measured toolbar and
        // expanded list, including on short displays and large system fonts.
        final maxSheet = (1 - (_toolbarHeight + 82) / height).clamp(.29, .72).toDouble();
        final toolbarLimit = (height * (ui.editing ? .86 : .71) - 82).clamp(0.0, height * .65).toDouble();
        return MapScreen(key: ValueKey('marketplace-map-$actor'), sharedSearchJourney: true,
        searchSessionProvider: marketplaceMapResultsProvider, enforceViewport: true,
        onSmartSearch: _openSmartSearch,
        resultsMaxExtent: maxSheet, collapseResults: ui.editing,
        onMapInteraction: () { FocusScope.of(context).unfocus(); ref.read(marketplaceSearchControllerProvider.notifier).stopEditing(); },
        searchToolbarBuilder: (_, actions) => NotificationListener<SizeChangedLayoutNotification>(onNotification: (_) { _measureToolbar(); return false; },
          child: SizeChangedLayoutNotifier(child: SizedBox(key: _toolbarSizeKey,
            child: ConstrainedBox(key: const ValueKey('marketplace-search-toolbar'),
              constraints: BoxConstraints(maxHeight: toolbarLimit),
              child: SingleChildScrollView(child: MarketplaceSearchPanel(onMap: true, mapActions: actions)))))),
      ); })));
  }
}

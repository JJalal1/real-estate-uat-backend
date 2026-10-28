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

/// The same editable input, IME action and public suggestions on Home and map.
class MarketplaceSearchPanel extends ConsumerStatefulWidget {
  const MarketplaceSearchPanel({this.onMap = false, this.onOpenMap, super.key});
  final bool onMap;
  final VoidCallback? onOpenMap;
  @override
  ConsumerState<MarketplaceSearchPanel> createState() => _MarketplaceSearchPanelState();
}

class _MarketplaceSearchPanelState extends ConsumerState<MarketplaceSearchPanel> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  bool _mapFiltersExpanded = false;
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
    if (widget.onMap && _mapFiltersExpanded) setState(() => _mapFiltersExpanded = false);
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
    return Material(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(16),
      child: Padding(padding: const EdgeInsets.all(10), child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (large) ...[field, Row(mainAxisAlignment: MainAxisAlignment.end, children: [execute,
          if (widget.onOpenMap != null) IconButton(key: const ValueKey('home-map'), tooltip: 'الخريطة',
            onPressed: widget.onOpenMap, icon: const Icon(Icons.map_outlined))])]
        else Row(children: [Expanded(child: field), const SizedBox(width: 4), execute,
          if (widget.onOpenMap != null) IconButton(key: const ValueKey('home-map'), tooltip: 'الخريطة',
            onPressed: widget.onOpenMap, icon: const Icon(Icons.map_outlined))]),
        if (active && !widget.onMap) Align(alignment: AlignmentDirectional.centerEnd, child: TextButton(
          key: const ValueKey('home-search-cancel'), onPressed: () { _focus.unfocus(); controller.leaveHomeSearch(); },
          child: const Text('إلغاء البحث والعودة للرئيسية'))),
        if (active && !ui.editing) ...[
          _ChipRail(children: [
            if (widget.onMap) ActionChip(key: const ValueKey('published-map-filters'),
              avatar: const Icon(Icons.tune, size: 18), label: Text(_mapFiltersExpanded ? 'إخفاء الفلاتر' : 'الفلاتر'),
              onPressed: () => setState(() => _mapFiltersExpanded = !_mapFiltersExpanded)),
            for (final e in const {'all': 'الكل', 'rent': 'إيجار', 'sale': 'بيع'}.entries)
              ChoiceChip(key: ValueKey('published-purpose-${e.key}'), label: Text(e.value),
                selected: e.key == 'all' ? values['purpose'] == null : values['purpose'] == e.key,
                onSelected: (_) => controller.setChoice('purpose', e.key == 'all' ? null : e.key)),
            if (widget.onMap && values['type'] != null) InputChip(
              label: Text(SmartSearchFilters.types[values['type']] ?? 'نوع العقار'),
              onPressed: () => _editFilters('type'), onDeleted: () => controller.setChoice('type', null)),
            if (widget.onMap) ...[
              for (final chip in ui.criteria.chips.where((e) => !const ['type', 'purpose'].contains(e.$1)))
                InputChip(label: Text(chip.$2), onPressed: () => _editFilters(chip.$1), onDeleted: () => controller.remove(chip.$1)),
              if (ui.landUse.isNotEmpty) InputChip(label: Text('الاستخدام المعلن: ${ui.landUse}'),
                onPressed: _landUse, onDeleted: () => controller.setLandUse('')),
            ],
          ]),
          if (!widget.onMap || _mapFiltersExpanded) ...[
          _ChipRail(children: [
            for (final e in const {'all': 'كل الأنواع', 'apartment': 'شقق', 'house': 'منازل', 'villa': 'فلل',
              'land': 'أراضٍ', 'shop': 'محلات', 'office': 'مكاتب', 'building': 'عمائر', 'farm': 'مزارع'}.entries)
              ChoiceChip(key: ValueKey('published-type-${e.key}'), label: Text(e.value),
                selected: e.key == 'all' ? values['type'] == null : values['type'] == e.key,
                onSelected: (_) => controller.setChoice('type', e.key == 'all' ? null : e.key)),
          ]),
          _ChipRail(children: [
            if (const ['apartment', 'house', 'villa', 'building'].contains(values['type'])) ...[
              ActionChip(key: const ValueKey('published-filter-rooms'), label: const Text('الغرف'), onPressed: () => _editFilters('min_bedrooms')),
              ActionChip(key: const ValueKey('published-filter-bathrooms'), label: const Text('الحمامات'), onPressed: () => _editFilters('min_bathrooms')),
            ],
            ActionChip(label: const Text('السعر'), onPressed: () => _editFilters('budget')),
            if (DynamicPropertySchema.applies('area_value', values))
              ActionChip(key: const ValueKey('published-filter-area'), label: const Text('المساحة'), onPressed: () => _editFilters('min_area_m2')),
            if (values['type'] == 'land') ActionChip(key: const ValueKey('published-filter-land-use'),
              label: const Text('الاستخدام المعلن'), onPressed: _landUse),
            ActionChip(key: const ValueKey('published-filter-more'), label: const Text('المزيد'), onPressed: () => _editFilters()),
          ]),
          ],
          if (!widget.onMap && (ui.criteria.chips.any((e) => !const ['type', 'purpose'].contains(e.$1)) || ui.landUse.isNotEmpty))
            _ChipRail(children: [
              for (final chip in ui.criteria.chips.where((e) => !const ['type', 'purpose'].contains(e.$1)))
                InputChip(label: Text(chip.$2), onDeleted: () => controller.remove(chip.$1)),
              if (ui.landUse.isNotEmpty) InputChip(label: Text('الاستخدام المعلن: ${ui.landUse}'), onDeleted: () => controller.setLandUse('')),
            ]),
        ],
        if (showSuggestions) _PublishedSuggestions(suggestionKey: key, onOpen: (row) async {
          _focus.unfocus();
          await context.push('/properties/${row.id}', extra: row);
          if (mounted) ref.invalidate(publishedListingSuggestionsProvider(key));
        }),
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !ref.read(marketplaceSearchControllerProvider).mapOpen) {
        ref.read(marketplaceSearchControllerProvider.notifier).enterMap();
      }
    });
  }
  @override
  Widget build(BuildContext context) {
    _measureToolbar();
    final ui = ref.watch(marketplaceSearchControllerProvider);
    final actor = ref.watch(authControllerProvider.select((value) => value.asData?.value?.id));
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
        resultsMaxExtent: maxSheet, collapseResults: ui.editing,
        onMapInteraction: () { FocusScope.of(context).unfocus(); ref.read(marketplaceSearchControllerProvider.notifier).stopEditing(); },
        searchToolbar: NotificationListener<SizeChangedLayoutNotification>(onNotification: (_) { _measureToolbar(); return false; },
          child: SizeChangedLayoutNotifier(child: SizedBox(key: _toolbarSizeKey,
            child: ConstrainedBox(key: const ValueKey('marketplace-search-toolbar'),
              constraints: BoxConstraints(maxHeight: toolbarLimit),
              child: const SingleChildScrollView(child: MarketplaceSearchPanel(onMap: true)))))),
      ); })));
  }
}

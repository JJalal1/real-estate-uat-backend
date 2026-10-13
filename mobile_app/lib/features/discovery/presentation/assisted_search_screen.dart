import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/ebroker_property_card.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../../properties/data/property_repository.dart';
import '../../properties/domain/property_details.dart';
import '../domain/assisted_property_search.dart';

class AssistedSearchScreen extends ConsumerStatefulWidget {
  const AssistedSearchScreen({super.key});
  @override
  ConsumerState<AssistedSearchScreen> createState() => _AssistedSearchState();
}

class _AssistedSearchState extends ConsumerState<AssistedSearchScreen> {
  final _description = TextEditingController();
  AssistedPropertySearch? _filters;
  final _rows = <PropertySummary>[];
  bool _loading = false, _more = false, _searched = false;
  int _request = 0, _page = 0;
  String? _error;

  @override
  void dispose() { _description.dispose(); super.dispose(); }

  void _setFilters(AssistedPropertySearch value) {
    _request++;
    setState(() { _filters = value; _rows.clear(); _searched = false; _loading = false; _error = null; _more = false; _page = 0; });
  }

  void _interpret() {
    if (_description.text.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    _setFilters(AssistedPropertySearch.parse(_description.text));
  }

  Future<void> _edit() async {
    final next = await AppBottomSheet.show<AssistedPropertySearch>(context,
      builder: (_) => _SearchFilterEditor(initial: _filters ?? const AssistedPropertySearch()));
    if (next != null && mounted) _setFilters(next);
  }

  Future<void> _load({bool more = false}) async {
    if (_loading || _filters == null) return;
    final request = ++_request;
    final page = more ? _page + 1 : 1;
    setState(() { _loading = true; _error = null; _searched = true; if (!more) _rows.clear(); });
    try {
      final result = await ref.read(propertyRepositoryProvider).searchListings(_filters!.apiFilters, page: page);
      if (!mounted || request != _request) return;
      setState(() {
        final ids = _rows.map((row) => row.id).toSet();
        _rows.addAll(result.$1.where((row) => ids.add(row.id)));
        _page = page; _more = result.$2; _loading = false;
      });
    } catch (error) {
      if (mounted && request == _request) setState(() { _error = friendlyApiError(error); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), filters = _filters;
    final chips = <(String, String)>[
      if (filters?.type != null) ('type', ebrokerPropertyTypeLabel(filters!.type)),
      if (filters?.purpose != null) ('purpose', filters!.purpose == 'rent' ? 'إيجار' : 'بيع'),
      if (filters?.place != null) ('place', filters!.place!),
      if (filters?.minBedrooms != null) ('rooms', '${filters!.minBedrooms} غرف فأكثر'),
      if (filters?.maxPrice != null) ('price', '${filters!.purpose == 'rent' ? 'شهريًا ' : ''}حتى ${filters.maxPrice!.toStringAsFixed(0)} ريال'),
    ];
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(
      appBar: const AppAppBar(title: 'البحث الذكي'),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        Text('العقار الذي يناسبك', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text('صف ما تبحث عنه، ثم راجع الفلاتر المقترحة وعدّلها قبل البحث.', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 20),
        TextField(key: const ValueKey('smart-search-description'), controller: _description,
          maxLines: 3, maxLength: 500, textInputAction: TextInputAction.search,
          onSubmitted: (_) => _interpret(), decoration: const InputDecoration(
            hintText: 'صف لي العقار الذي تبحث عنه…',
            helperText: 'مثال: شقة إيجار في تعز، 3 غرف، أقل من 150 ألف')),
        const SizedBox(height: 8),
        AppButton(label: 'اقتراح الفلاتر', icon: Icons.auto_awesome_outlined, expand: true, onPressed: _interpret),
        if (filters != null) ...[
          const SizedBox(height: 24),
          Row(children: [Expanded(child: Text('راجع بحثك', style: theme.textTheme.titleMedium)),
            TextButton(onPressed: _edit, child: const Text('تعديل البحث'))]),
          if (chips.isEmpty) const Text('لم نحدد فلاتر واضحة. عدّل البحث لتحديد ما يناسبك.')
          else Wrap(spacing: 6, runSpacing: 6, children: [for (final chip in chips)
            InputChip(label: Text(chip.$2), onPressed: _edit,
              onDeleted: () => _setFilters(filters.without(chip.$1)), deleteButtonTooltipMessage: 'إزالة ${chip.$2}')]),
          const SizedBox(height: 12),
          AppButton(label: 'عرض النتائج', expand: true, loading: _loading, onPressed: _loading ? null : () => _load()),
        ],
        if (_searched) ...[
          const SizedBox(height: 28),
          Text('النتائج', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          if (_loading && _rows.isEmpty) ...[
            const AppSkeleton(height: 170, radius: 8), const SizedBox(height: 12), const AppSkeleton(height: 170, radius: 8),
          ] else if (_error != null)
            AppErrorState(message: _error!, onRetry: () => _load(more: _rows.isNotEmpty))
          else if (_rows.isEmpty)
            AppEmptyState(title: 'لا توجد عقارات بهذه الفلاتر', message: 'جرّب توسيع الميزانية أو تعديل الموقع والنوع.',
              actionLabel: 'تعديل البحث', onAction: _edit),
          for (final row in _rows) Padding(padding: const EdgeInsets.only(bottom: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              EbrokerPropertyHorizontalCard(title: row.title, price: row.price.toStringAsFixed(0), currency: row.currency,
                imageUrl: row.mainImage, location: row.address, categoryLabel: ebrokerPropertyTypeLabel(row.type),
                purposeLabel: row.purpose == 'rent' ? 'للإيجار' : 'للبيع',
                onTap: () => context.push('/properties/${row.id}')),
              if (row.monthlyRent != null) Padding(padding: const EdgeInsets.only(top: 6),
                child: Text('الإيجار الشهري: ${row.monthlyRent!.toStringAsFixed(0)} ${row.currency} قبل السعي', style: theme.textTheme.bodySmall)),
              if (row.priceDisplayNote != null) Text(row.priceDisplayNote!, style: theme.textTheme.bodySmall),
            ])),
          if (_more && _error == null) TextButton(onPressed: _loading ? null : () => _load(more: true), child: const Text('المزيد من العقارات')),
        ],
        const SizedBox(height: 24),
      ]),
    ));
  }
}

class _SearchFilterEditor extends StatefulWidget {
  const _SearchFilterEditor({required this.initial});
  final AssistedPropertySearch initial;
  @override
  State<_SearchFilterEditor> createState() => _SearchFilterEditorState();
}

class _SearchFilterEditorState extends State<_SearchFilterEditor> {
  late final TextEditingController _place, _rooms, _price;
  String? _type, _purpose, _error;
  @override
  void initState() { super.initState(); final initial = widget.initial;
    _type = initial.type; _purpose = initial.purpose;
    _place = TextEditingController(text: initial.place ?? '');
    _rooms = TextEditingController(text: initial.minBedrooms?.toString() ?? '');
    _price = TextEditingController(text: initial.maxPrice?.toStringAsFixed(0) ?? '');
  }
  @override
  void dispose() { _place.dispose(); _rooms.dispose(); _price.dispose(); super.dispose(); }
  void _save() {
    final rooms = int.tryParse(_rooms.text.trim()), price = double.tryParse(_price.text.trim());
    if ((_rooms.text.trim().isNotEmpty && (rooms == null || rooms < 0 || rooms > 50)) ||
        (_price.text.trim().isNotEmpty && (price == null || !price.isFinite || price <= 0))) {
      setState(() => _error = 'أدخل عدد غرف من 0 إلى 50 وميزانية صحيحة أكبر من صفر.'); return;
    }
    Navigator.of(context).pop(AssistedPropertySearch(type: _type, purpose: _purpose,
      place: _place.text.trim().isEmpty ? null : _place.text.trim(), minBedrooms: rooms, maxPrice: price));
  }
  @override
  Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl,
    child: Padding(padding: EdgeInsets.fromLTRB(18, 18, 18, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('تعديل البحث', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 18),
        DropdownButtonFormField<String>(value: _purpose, isExpanded: true, decoration: const InputDecoration(labelText: 'الغرض'),
          items: const [DropdownMenuItem(value: null, child: Text('بيع وإيجار')), DropdownMenuItem(value: 'sale', child: Text('بيع')), DropdownMenuItem(value: 'rent', child: Text('إيجار'))],
          onChanged: (value) => setState(() => _purpose = value)),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(value: _type, isExpanded: true, decoration: const InputDecoration(labelText: 'نوع العقار'),
          items: [const DropdownMenuItem(value: null, child: Text('كل الأنواع')),
            for (final type in const ['apartment', 'floor', 'building', 'house', 'villa', 'land', 'shop', 'office', 'farm'])
              DropdownMenuItem(value: type, child: Text(ebrokerPropertyTypeLabel(type)))], onChanged: (value) => setState(() => _type = value)),
        const SizedBox(height: 12),
        TextField(controller: _place, maxLength: 120, decoration: const InputDecoration(labelText: 'المحافظة أو المنطقة')),
        const SizedBox(height: 12),
        TextField(controller: _rooms, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'غرف النوم على الأقل')),
        const SizedBox(height: 12),
        TextField(controller: _price, keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: _purpose == 'rent' ? 'أقصى إيجار شهري بالريال' : 'أقصى سعر بالريال')),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 18), AppButton(label: 'تطبيق التعديل', onPressed: _save, expand: true),
      ]))));
}

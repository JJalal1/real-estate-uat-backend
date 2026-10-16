import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../data/property_market_repository.dart';
import '../data/property_repository.dart';
import '../domain/property_details.dart';
import '../domain/property_field_options.dart';
import '../domain/property_sai.dart';
import 'property_compare_actions.dart';

class PropertyCompareScreen extends ConsumerStatefulWidget {
  const PropertyCompareScreen({required this.propertyIds, super.key});
  final List<int> propertyIds;
  @override
  ConsumerState<PropertyCompareScreen> createState() => _PropertyCompareState();
}

class _PropertyCompareState extends ConsumerState<PropertyCompareScreen> {
  late List<int> _ids;
  late Future<List<_CompareItem>> _future;
  @override
  void initState() { super.initState(); _ids = widget.propertyIds.where((id) => id > 0).toSet().take(4).toList(); _future = _load(); }
  @override
  void didUpdateWidget(PropertyCompareScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (Object.hashAll(oldWidget.propertyIds) != Object.hashAll(widget.propertyIds)) {
      _ids = widget.propertyIds.where((id) => id > 0).toSet().take(4).toList(); _future = _load();
    }
  }
  void _reload() => setState(() => _future = _load());

  Future<List<_CompareItem>> _load() async {
    if (_ids.length < 2) return const [];
    final repository = ref.read(propertyRepositoryProvider), market = ref.read(propertyMarketRepositoryProvider);
    return Future.wait(_ids.map((id) async {
      try {
        final property = await repository.details(id);
        if (property.status != 'published' || property.availabilityStatus != 'available' || property.financialHold) return _CompareItem(id: id);
        PropertySaiEnvelope? sai;
        PropertyMarketContext? context;
        await Future.wait([
          () async { try { sai = await repository.sai(id); } catch (_) { /* Keep actual facts if Sai fails. */ } }(),
          () async { try { context = await market.context(id); } catch (_) { /* Do not invent a market value. */ } }(),
        ]);
        return _CompareItem(id: id, property: property, sai: sai, market: context);
      } catch (_) { return _CompareItem(id: id); }
    }));
  }

  void _remove(int id) {
    if (ref.read(propertyCompareSelectionProvider).contains(id)) ref.read(propertyCompareSelectionProvider.notifier).toggle(id);
    setState(() { _ids.remove(id); _future = _future.then((items) => items.where((item) => item.id != id).toList(growable: false)); });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(propertyDataRevisionProvider, (_, __) => _reload());
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(
      appBar: AppAppBar(title: 'مقارنة العقارات', actions: [IconButton(onPressed: _reload, tooltip: 'تحديث المقارنة', icon: const Icon(Icons.refresh))]),
      body: FutureBuilder<List<_CompareItem>>(future: _future, builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        final items = snapshot.data ?? const <_CompareItem>[];
        if (items.length < 2) return const AppEmptyState(title: 'اختر عقارين على الأقل', message: 'اختر من بطاقات التصفح أو نتائج البحث حتى أربعة عقارات، ثم افتح المقارنة.', icon: Icons.compare_arrows);
        return _table(context, items);
      }),
    ));
  }

  Widget _table(BuildContext context, List<_CompareItem> items) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final width = scale > 1.4 ? 270.0 : 220.0;
    final labelWidth = scale > 1.4 ? 260.0 : 130.0;
    final fields = <(String, String? Function(_CompareItem))>[
      ('السعر', (item) { final p = item.property; return p == null ? null : '${_number(p.purpose == 'rent' ? p.monthlyRent ?? p.price : p.price)} ${p.currency}${p.purpose == 'rent' && p.monthlyRent != null ? ' شهريًا' : ''}'; }),
      ('السعي', (item) => item.property == null ? null : item.sai?.sai?.displayText ?? 'تعذر تحميل السعي'),
      ('الموقع', (item) => item.property?.address),
      ('نوع العقار', (item) => item.property == null ? null : ebrokerPropertyTypeLabel(item.property!.type)),
      ('الغرض', (item) => item.property == null ? null : item.property!.purpose == 'rent' ? 'للإيجار' : 'للبيع'),
      ('غرف النوم', (item) => _residential(item.property) ? item.property?.bedrooms?.toString() : null),
      ('الحمامات', (item) => _residential(item.property) ? item.property?.bathrooms?.toString() : null),
      ('المساحة', (item) { final p = item.property; if (p?.areaValue != null) return '${formatPropertyAreaValue(p!.areaValue!)} ${propertyAreaUnitLabel(p.areaUnit)}'; return p?.areaM2 == null ? null : '${p!.areaM2} م²'; }),
      ('الدور', (item) => const ['apartment','floor','shop','office'].contains(item.property?.type) ? item.property?.floorNumber : null),
      ('الموقف', (item) => _boolean(item.property?.hasParking)),
      ('المصعد', (item) => const ['apartment','floor','building','office'].contains(item.property?.type) ? _boolean(item.property?.hasElevator) : null),
      ('الواجهة', (item) => item.property?.buildingFacade == null ? null : propertyFacadeLabel(item.property!.buildingFacade)),
      ('التقييم', (item) { final a = item.property?.advertiser; return a == null ? null : a.ratingCount == 0 ? 'لا توجد تقييمات بعد' : '${a.ratingAverage.toStringAsFixed(1)} من 5 (${a.ratingCount})'; }),
      ('مؤشر السوق', (item) { final m = item.market; if (m == null) return null; return m.sufficientData ? '${m.positionLabel} · ${m.sampleCount} عقار مقارنة' : 'البيانات غير كافية (${m.sampleCount})'; }),
    ];
    fields.removeWhere((field) => items.every((item) => field.$2(item) == null));
    Widget cell(String text, {bool heading = false}) => Padding(padding: const EdgeInsets.all(14), child: Text(text,
      style: heading ? Theme.of(context).textTheme.titleSmall : Theme.of(context).textTheme.bodyMedium));
    return SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), child: SingleChildScrollView(scrollDirection: Axis.horizontal,
      child: SizedBox(width: labelWidth + items.length * width, child: Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        columnWidths: {0: FixedColumnWidth(labelWidth), for (var i = 1; i <= items.length; i++) i: FixedColumnWidth(width)},
        border: TableBorder.all(color: Theme.of(context).colorScheme.outlineVariant, borderRadius: BorderRadius.circular(12)),
        children: [
          TableRow(children: [cell('المواصفات\nاسحب لرؤية بقية العقارات', heading: true), for (final item in items) Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (item.property != null) ClipRRect(borderRadius: BorderRadius.circular(8), child: AppPropertyMedia(imageUrl: item.property!.mainImage, height: 120)),
            const SizedBox(height: 8), Text(item.property?.title ?? 'العقار غير متاح حاليًا', style: Theme.of(context).textTheme.titleSmall),
            if (item.property == null) const Text('قد يكون الإعلان أوقف أو تعذر تحميله. يمكنك تحديث المقارنة.'),
            TextButton.icon(onPressed: item.property == null ? null : () => context.push('/properties/${item.id}'), icon: const Icon(Icons.open_in_new, size: 18), label: const Text('عرض')),
            TextButton(onPressed: () => _remove(item.id), child: const Text('إزالة من المقارنة')),
          ]))]),
          for (final field in fields) TableRow(children: [cell(field.$1, heading: true), for (final item in items) cell(item.property == null ? 'غير متاح' : field.$2(item) ?? 'غير مذكور')]),
        ],
      )),
    ));
  }
}

bool _residential(PropertyDetails? property) => const ['apartment','floor','house','villa'].contains(property?.type);
String? _boolean(bool? value) => value == null ? null : value ? 'نعم' : 'لا';
String _number(double value) => value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2);

class _CompareItem {
  const _CompareItem({required this.id, this.property, this.sai, this.market});
  final int id;
  final PropertyDetails? property;
  final PropertySaiEnvelope? sai;
  final PropertyMarketContext? market;
}

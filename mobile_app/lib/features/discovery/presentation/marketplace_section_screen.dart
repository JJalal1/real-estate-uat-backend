import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/ebroker_property_card.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../../properties/data/property_repository.dart';
import '../../properties/domain/property_details.dart';
import '../../properties/presentation/property_compare_actions.dart';
import 'smart_search_assistant.dart';

class MarketplaceSectionScreen extends ConsumerStatefulWidget {
  const MarketplaceSectionScreen({this.section = 'latest', this.governorate, this.type, super.key});
  final String section;
  final String? governorate, type;
  @override
  ConsumerState<MarketplaceSectionScreen> createState() => _MarketplaceSectionState();
}

class _MarketplaceSectionState extends ConsumerState<MarketplaceSectionScreen> {
  final _rows = <PropertySummary>[];
  int _page = 0, _request = 0;
  bool _busy = true, _more = false;
  String? _error;
  @override
  void initState() { super.initState(); Future.microtask(_load); }
  @override
  void didUpdateWidget(MarketplaceSectionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section || oldWidget.governorate != widget.governorate || oldWidget.type != widget.type) Future.microtask(_load);
  }
  Future<void> _load({bool more = false}) async {
    final request = ++_request;
    final page = more ? _page + 1 : 1;
    setState(() { _busy = true; _error = null; if (!more) _rows.clear(); });
    try {
      final r = await ref.read(propertyRepositoryProvider).searchListings({
        if (widget.governorate != null) 'governorate': widget.governorate,
        if (widget.type != null) 'type': widget.type,
        if (const ['sale', 'rent'].contains(widget.section)) 'purpose': widget.section,
        if (widget.section == 'spotlight') 'spotlight': 1,
      }, page: page);
      if (!mounted || request != _request) return;
      setState(() { final ids = _rows.map((r) => r.id).toSet(); _rows.addAll(r.$1.where((r) => ids.add(r.id))); _page = page; _more = r.$2; _busy = false; });
    } catch (error) { if (mounted && request == _request) setState(() { _busy = false; _error = friendlyApiError(error); }); }
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.section) { 'spotlight' => 'عقارات مميزة', 'sale' => 'عقارات للبيع', 'rent' => 'عقارات للإيجار', _ => 'أحدث العقارات' };
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(appBar: AppAppBar(title: title),
      body: SmartSearchAssistantLayer(child: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 110), physics: const AlwaysScrollableScrollPhysics(), children: [
        if (widget.governorate != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(widget.governorate!)),
        if (_busy && _rows.isEmpty) const AppSkeleton(height: 190, radius: 12)
        else if (_error != null) AppErrorState(message: _error!, onRetry: () => _load(more: _rows.isNotEmpty))
        else if (_rows.isEmpty) const AppEmptyState(title: 'لا توجد عقارات في هذا القسم الآن', message: 'يمكنك تغيير المنطقة أو استكشاف الأقسام الأخرى.'),
        for (final row in _rows) Padding(padding: const EdgeInsets.only(bottom: 14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          EbrokerPropertyHorizontalCard(title: row.title, price: row.price.toStringAsFixed(0), currency: row.currency,
            imageUrl: row.mainImage, imageUrls: row.imageUrls, isSpotlight: row.isSpotlight,
            location: row.address, categoryLabel: ebrokerPropertyTypeLabel(row.type), purposeLabel: row.purpose == 'rent' ? 'للإيجار' : 'للبيع',
            onTap: () => context.push('/properties/${row.id}')),
          PropertyCompareAction(propertyId: row.id, enabled: row.status == 'published'),
          if (row.monthlyRent != null) Text('الإيجار الشهري: ${row.monthlyRent!.toStringAsFixed(0)} ${row.currency}', style: Theme.of(context).textTheme.bodySmall),
          if (row.priceDisplayNote != null) Text(row.priceDisplayNote!, style: Theme.of(context).textTheme.bodySmall),
        ])),
        if (_more && _error == null) TextButton(onPressed: _busy ? null : () => _load(more: true), child: const Text('المزيد من العقارات')),
      ])))));
  }
}

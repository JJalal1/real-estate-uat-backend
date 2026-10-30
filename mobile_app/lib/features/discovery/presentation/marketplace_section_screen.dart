import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/widgets/app_components.dart';
import '../../properties/presentation/property_summary_card.dart';
import '../../properties/data/property_repository.dart';
import '../../properties/domain/property_details.dart';
import 'smart_search_assistant.dart';
import '../domain/smart_search_filters.dart';

class MarketplaceSectionScreen extends ConsumerStatefulWidget {
  const MarketplaceSectionScreen({this.section = 'latest', this.governorate, this.type, this.purpose, this.latitude, this.longitude,
    this.filters = const SmartSearchFilters(), super.key});
  final SmartSearchFilters filters;
  final String section;
  final double? latitude, longitude;
  final String? governorate, type, purpose;
  @override
  ConsumerState<MarketplaceSectionScreen> createState() => _MarketplaceSectionState();
}

class _MarketplaceSectionState extends ConsumerState<MarketplaceSectionScreen> {
  final _rows = <PropertySummary>[];
  int _page = 0, _request = 0;
  bool _busy = true, _more = false;
  String? _error;
  bool _failedMore = false;
  CancelToken? _transfer;
  @override
  void initState() { super.initState(); Future.microtask(_load); }
  @override
  void didUpdateWidget(MarketplaceSectionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section || oldWidget.governorate != widget.governorate || oldWidget.type != widget.type || oldWidget.purpose != widget.purpose || oldWidget.latitude != widget.latitude || oldWidget.longitude != widget.longitude || !oldWidget.filters.sameAs(widget.filters)) {
      _rows.clear(); _page = 0; _more = false; _busy = true; _error = null;
      _transfer?.cancel('Section changed'); _request++;
      Future.microtask(_load);
    }
  }
  Future<void> _load({bool more = false}) async {
    if (!mounted) return;
    if (more && (_busy || !_more)) return;
    final request = ++_request;
    final page = more ? _page + 1 : 1;
    _transfer?.cancel('Section request superseded');
    final transfer = _transfer = CancelToken();
    _failedMore = more;
    setState(() { _busy = true; _error = null; });
    try {
      final r = await ref.read(propertyRepositoryProvider).searchListings({
        ...widget.filters.apiFilters,
        if (widget.governorate != null) 'governorate': widget.governorate,
        if (widget.type != null) 'type': widget.type,
        if (widget.purpose != null) 'purpose': widget.purpose
        else if (const ['sale', 'rent'].contains(widget.section)) 'purpose': widget.section,
        if (widget.section=='nearby' && widget.latitude!=null && widget.longitude!=null)...{'latitude':widget.latitude,'longitude':widget.longitude,'radius_km':30},
        if (widget.section == 'spotlight') 'spotlight': 1,
      }, page: page, cancelToken: transfer, refresh: !more && _page > 0);
      if (!mounted || request != _request) return;
      setState(() { if (!more) _rows.clear(); final ids = _rows.map((r) => r.id).toSet(); _rows.addAll(r.$1.where((r) => ids.add(r.id))); _page = page; _more = r.$2; _busy = false; });
    } catch (error) { if (mounted && request == _request) { setState(() {
      if (!isTransientApiFailure(error)) _rows.clear();
      _busy = false; _error = friendlyApiError(error);
    }); } }
  }

  @override
  void dispose() { _request++; _transfer?.cancel('Section disposed'); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.section) { 'nearby'=>'قريبة منك', 'spotlight' => 'عقارات مميزة', 'sale' => 'عقارات للبيع', 'rent' => 'عقارات للإيجار', _ => 'أحدث العقارات' };
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(appBar: AppAppBar(title: title),
      body: SmartSearchAssistantLayer(mapFilters: SmartSearchFilters.fromApiFilters({...widget.filters.apiFilters,
        if (widget.governorate != null) 'governorate': widget.governorate,
        if (widget.type != null) 'type': widget.type,
        if (widget.purpose != null) 'purpose': widget.purpose
        else if (const ['sale', 'rent'].contains(widget.section)) 'purpose': widget.section,
        if (widget.section == 'nearby' && widget.latitude != null && widget.longitude != null)
          ...{'latitude': widget.latitude, 'longitude': widget.longitude, 'radius_km': 30},
        if (widget.section == 'spotlight') 'spotlight': 1,
      }), child: RefreshIndicator(onRefresh: _load, child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 110), cacheExtent: 300,
        physics: const AlwaysScrollableScrollPhysics(), itemCount: _rows.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (widget.governorate != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(widget.governorate!)),
            if (_busy && _rows.isEmpty) const AppSkeleton(height: 190, radius: 12)
            else if (_error != null && _rows.isEmpty) AppErrorState(message: _error!, onRetry: () => _load(more: _failedMore))
            else if (_rows.isEmpty) const AppEmptyState(title: 'لا توجد عقارات في هذا القسم الآن', message: 'يمكنك تغيير المنطقة أو استكشاف الأقسام الأخرى.'),
            if (_rows.isNotEmpty) AppRefreshStatus(loading: _busy, error: _error, onRetry: () => _load(more: _failedMore)),
            ]);
          }
          if (index <= _rows.length) {
            final row = _rows[index - 1];
            return Padding(key: ValueKey('section-property-${row.id}'), padding: const EdgeInsets.only(bottom: 14), child: PropertySummaryCard(property: row));
          }
          if (_more && _error == null) {
            return TextButton(onPressed: _busy ? null : () => _load(more: true), child: _busy
              ? const Text('جارٍ تحميل المزيد…') : const Text('المزيد من العقارات'));
          }
          return const SizedBox.shrink();
        })))));
  }
}

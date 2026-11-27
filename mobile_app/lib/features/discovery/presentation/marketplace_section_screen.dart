import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../../properties/data/property_repository.dart';
import '../../properties/domain/property_details.dart';
import '../../properties/presentation/property_summary_card.dart';
import '../domain/smart_search_filters.dart';
import 'smart_search_assistant.dart';

class MarketplaceSectionScreen extends StatelessWidget {
  const MarketplaceSectionScreen({
    this.section = 'latest',
    this.governorate,
    this.type,
    this.purpose,
    this.latitude,
    this.longitude,
    this.filters = const SmartSearchFilters(),
    super.key,
  });

  final SmartSearchFilters filters;
  final String section;
  final double? latitude, longitude;
  final String? governorate, type, purpose;

  @override
  Widget build(BuildContext context) {
    final title = switch (section) {
      'nearby' => 'قريبة منك',
      'spotlight' => 'عقارات مميزة',
      'sale' => 'عقارات للبيع',
      'rent' => 'عقارات للإيجار',
      'regional' when governorate != null => 'عقارات $governorate',
      'regional' => 'العقارات',
      _ => 'أحدث العقارات',
    };
    final query = {
      ...filters.apiFilters,
      if (governorate != null) 'governorate': governorate,
      if (type != null) 'type': type,
      if (purpose != null)
        'purpose': purpose
      else if (const ['sale', 'rent'].contains(section))
        'purpose': section,
      if (section == 'nearby' && latitude != null && longitude != null) ...{
        'latitude': latitude,
        'longitude': longitude,
        'radius_km': 30,
      },
      if (section == 'spotlight') 'spotlight': 1,
    };
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppAppBar(title: title),
        body: SmartSearchAssistantLayer(
          mapFilters: SmartSearchFilters.fromApiFilters(query),
          child: MarketplaceListingResults(
            query: query,
            locationLabel: section == 'regional' ? null : governorate,
            compactCards:
                type != null && (section == 'rent' || section == 'sale'),
          ),
        ),
      ),
    );
  }
}

class MarketplaceListingResults extends ConsumerStatefulWidget {
  const MarketplaceListingResults({
    required this.query,
    this.locationLabel,
    this.compactCards = false,
    this.bottomPadding = 110,
    this.emptyMessage = 'يمكنك تغيير المنطقة أو استكشاف الأقسام الأخرى.',
    super.key,
  });

  final Map<String, dynamic> query;
  final String? locationLabel;
  final bool compactCards;
  final double bottomPadding;
  final String emptyMessage;

  @override
  ConsumerState<MarketplaceListingResults> createState() =>
      _MarketplaceListingResultsState();
}

class _MarketplaceListingResultsState
    extends ConsumerState<MarketplaceListingResults> {
  final _rows = <PropertySummary>[];
  final _scroll = ScrollController(keepScrollOffset: false);
  int _page = 0, _request = 0;
  bool _busy = true, _more = false;
  String? _error;
  bool _failedMore = false;
  CancelToken? _transfer;

  @override
  void initState() {
    super.initState();
    _scheduleFirstPage();
  }

  @override
  void didUpdateWidget(MarketplaceListingResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (mapEquals(oldWidget.query, widget.query)) return;
    _rows.clear();
    _page = 0;
    _more = false;
    _busy = true;
    _error = null;
    _failedMore = false;
    _transfer?.cancel('Section changed');
    _request++;
    final query = widget.query;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(widget.query, query) && _scroll.hasClients) {
        _scroll.jumpTo(0);
      }
    });
    _scheduleFirstPage();
  }

  void _scheduleFirstPage() {
    final request = _request;
    Future<void>.microtask(() async {
      if (mounted && request == _request) await _load();
    });
  }

  Future<void> _load({bool more = false}) async {
    if (!mounted || (more && (_busy || !_more))) return;
    final request = ++_request;
    final page = more ? _page + 1 : 1;
    _transfer?.cancel('Section request superseded');
    final transfer = _transfer = CancelToken();
    _failedMore = more;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final (rows, hasMore) =
          await ref.read(propertyRepositoryProvider).searchListings(
                widget.query,
                page: page,
                cancelToken: transfer,
                refresh: !more && _page > 0,
              );
      if (!mounted || request != _request) return;
      setState(() {
        if (!more) _rows.clear();
        final ids = _rows.map((row) => row.id).toSet();
        _rows.addAll(rows.where((row) => ids.add(row.id)));
        _page = page;
        _more = hasMore;
        _busy = false;
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        if (!isTransientApiFailure(error)) _rows.clear();
        _busy = false;
        _error = friendlyApiError(error);
      });
    }
  }

  @override
  void dispose() {
    _request++;
    _transfer?.cancel('Section disposed');
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        key: const ValueKey('marketplace-listing-results'),
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(
          AppLayout.compactPageGutter,
          widget.compactCards ? 10 : 18,
          AppLayout.compactPageGutter,
          widget.bottomPadding,
        ),
        cacheExtent: 300,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _rows.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.locationLabel case final label?)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(label)),
                if (_busy && _rows.isEmpty)
                  const AppSkeleton(height: 190, radius: 12)
                else if (_error != null && _rows.isEmpty)
                  AppErrorState(
                      message: _error!, onRetry: () => _load(more: _failedMore))
                else if (_rows.isEmpty)
                  AppEmptyState(
                    title: 'لا توجد عقارات في هذا القسم الآن',
                    message: widget.emptyMessage,
                  ),
                if (_rows.isNotEmpty && !_failedMore)
                  AppRefreshStatus(
                    loading: _busy,
                    error: _error,
                    onRetry: _load,
                  ),
              ],
            );
          }
          if (index <= _rows.length) {
            final row = _rows[index - 1];
            return Padding(
              key: ValueKey('section-property-${row.id}'),
              padding: EdgeInsets.only(bottom: widget.compactCards ? 12 : 14),
              child: PropertySummaryCard(
                  property: row, compact: widget.compactCards),
            );
          }
          if (_rows.isNotEmpty && _failedMore && (_busy || _error != null)) {
            return AppRefreshStatus(
              loading: _busy,
              error: _error,
              onRetry: () => _load(more: true),
            );
          }
          if (_more && _error == null) {
            return TextButton(
              onPressed: _busy ? null : () => _load(more: true),
              child: Text(_busy ? 'جارٍ تحميل المزيد…' : 'المزيد من العقارات'),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

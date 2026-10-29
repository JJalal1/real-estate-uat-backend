import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_components.dart';
import '../../properties/presentation/property_summary_card.dart';
import '../data/marketplace_search_session.dart';
import '../data/smart_search_session.dart';
import '../domain/smart_search_filters.dart';
import 'marketplace_search_panel.dart';

/// One pushed page above Home. Its editor/list and the optional map retain
/// independent scroll/spatial snapshots through the existing search controller.
class MarketplaceSearchScreen extends ConsumerStatefulWidget {
  const MarketplaceSearchScreen({this.openFilters = false, super.key});
  final bool openFilters;
  @override
  ConsumerState<MarketplaceSearchScreen> createState() => _MarketplaceSearchScreenState();
}

class _MarketplaceSearchScreenState extends ConsumerState<MarketplaceSearchScreen> {
  final _scroll = ScrollController();
  bool _openingMap = false;
  @override
  void dispose() { _scroll.dispose(); super.dispose(); }

  Future<void> _openMap() async {
    if (_openingMap) return;
    _openingMap = true;
    FocusScope.of(context).unfocus();
    ref.read(marketplaceSearchControllerProvider.notifier).enterMap();
    try { await context.push('/marketplace-search-map'); }
    finally { _openingMap = false; }
  }

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(marketplaceSearchControllerProvider);
    final search = ref.watch(homeSearchResultsProvider);
    final controller = ref.read(marketplaceSearchControllerProvider.notifier);
    ref.listen(homeSearchResultsProvider, (previous, next) {
      if (previous?.filters == next.filters) return;
      if (ModalRoute.of(context)?.isCurrent == false) return;
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted && _scroll.hasClients) _scroll.jumpTo(0); });
    });
    return PopScope(onPopInvokedWithResult: (didPop, _) {
      if (didPop) controller.leaveHomeSearch();
    }, child: Scaffold(
      appBar: AppBar(title: const Text('البحث عن عقار'),
        toolbarHeight: (56 + (MediaQuery.textScalerOf(context).scale(18) - 18) * 2).clamp(56, 116).toDouble(),
        leading: IconButton(key: const ValueKey('marketplace-search-back'), tooltip: 'العودة للرئيسية',
          onPressed: () => context.pop(), icon: const Icon(Icons.arrow_back, size: 20))),
      body: RefreshIndicator(onRefresh: controller.refresh, child: CustomScrollView(
        key: const PageStorageKey('home-search-results'), controller: _scroll,
        cacheExtent: 0, physics: const AlwaysScrollableScrollPhysics(), slivers: [
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
          child: MarketplaceSearchPanel(openFilters: widget.openFilters))),
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: Wrap(
          alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (search.started && !ui.editing) Text(ui.submittedQuery.isEmpty ? 'العقارات المطابقة' : 'نتائج «${ui.submittedQuery}»',
            key: const ValueKey('published-result-context'), style: Theme.of(context).textTheme.titleSmall),
          TextButton.icon(key: const ValueKey('home-search-map'), onPressed: _openMap,
            icon: const Icon(Icons.map_outlined, size: 18), label: const Text('عرض على الخريطة')),
        ]))),
        // The old query's title, rows, count, error and paging controls all stay
        // out of the new editor state, including while requests finish late.
        if (ui.editing || !search.started)
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            child: Text(ui.draftQuery.isEmpty ? 'اكتب اسم العقار أو ما تبحث عنه، ثم نفّذ البحث.'
              : 'الاقتراحات تخص النص الحالي. اضغط «تنفيذ» لعرض نتائجه.')))
        else ..._results(search, controller),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ])),
    ));
  }

  List<Widget> _results(SmartSearchState search, MarketplaceSearchController controller) => [
    if (search.loading || search.resultsError != null) SliverToBoxAdapter(child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18), child: AppRefreshStatus(loading: search.loading,
        error: search.resultsError, onRetry: () => ref.read(homeSearchResultsProvider.notifier).retryResults()))),
    if (search.rows.isEmpty && search.loading)
      const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(18), child: AppSkeleton(height: 200, radius: 12)))
    else if (search.rows.isEmpty && search.resultsError == null)
      SliverToBoxAdapter(child: AppEmptyState(title: 'لا توجد عقارات مطابقة الآن',
        message: 'جرّب نصًا آخر أو خفّف الفلاتر.', actionLabel: 'إزالة الفلاتر',
        onAction: () => controller.applyFilters(SmartSearchFilters.fromMap({
          if (ref.read(marketplaceSearchControllerProvider).criteria.values['purpose'] != null)
            'purpose': ref.read(marketplaceSearchControllerProvider).criteria.values['purpose'],
        }))))
    else SliverList(delegate: SliverChildBuilderDelegate((context, i) => Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 4), child: PropertySummaryCard(
        key: ValueKey('home-result-${search.rows[i].id}'), property: search.rows[i])), childCount: search.rows.length)),
    if (search.more) SliverToBoxAdapter(child: TextButton(onPressed: search.loading ? null
      : () => ref.read(homeSearchResultsProvider.notifier).search(more: true), child: const Text('المزيد من العقارات'))),
  ];
}

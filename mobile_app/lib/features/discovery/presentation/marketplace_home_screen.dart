import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/theme/ebroker_design.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/ebroker_property_card.dart';
import '../../../core/widgets/ebroker_screen_sections.dart';
import '../../properties/presentation/property_details_screen.dart';
import '../../properties/domain/property_details.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../../map/presentation/map_screen.dart';
import '../../broker/data/broker_repository.dart';
import '../../broker/presentation/broker_directory.dart';

const homeDiscoveryQuery = NearbyQuery(center: LatLng(15.3694, 44.1910));

// Existing public details supply the advertiser cards; no template API or
// public directory, follower count or direct-contact capability is introduced.
class HomeAdvertiserEntry {
  const HomeAdvertiserEntry(this.propertyId, this.advertiser);
  final int propertyId;
  final AdvertiserCommunitySummary advertiser;
}
final homeAdvertisersProvider = FutureProvider.autoDispose.family<List<HomeAdvertiserEntry>, NearbyQuery>((ref, query) async {
  final properties = await ref.watch(nearbyPropertiesProvider(query).future);
  final ids = properties.where((property) => property.type != null).take(5).map((property) => property.id).toSet();
  final results = await Future.wait(ids.map((id) async {
    try {
      final details = await ref.watch(propertyDetailsProvider(id).future);
      final advertiser = details.advertiser;
      return details.status == 'published' && advertiser != null
        ? HomeAdvertiserEntry(id, advertiser) : null;
    } catch (_) {
      return null;
    }
  }));
  final unique = <int, HomeAdvertiserEntry>{};
  for (final entry in results.whereType<HomeAdvertiserEntry>()) {
    unique.putIfAbsent(entry.advertiser.id, () => entry);
  }
  return unique.values.toList(growable: false);
});

// Purchased home_screen/HomeSearchField/CategoriesSection/AllPropertiesSection.
// Data and action callbacks use our existing public API and router exclusively.
class MarketplaceHomeScreen extends ConsumerStatefulWidget {
  const MarketplaceHomeScreen({this.showAdvertiserActions = false, super.key});
  final bool showAdvertiserActions;
  @override
  ConsumerState<MarketplaceHomeScreen> createState() => _MarketplaceHomeState();
}
class _MarketplaceHomeState extends ConsumerState<MarketplaceHomeScreen> {
  String? _type;
  NearbyQuery get _query => _type == null ? homeDiscoveryQuery : NearbyQuery(center: homeDiscoveryQuery.center, type: _type);
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final properties = ref.watch(nearbyPropertiesProvider(_query));
    final advertisers = ref.watch(brokerDirectoryProvider);
    void openMap() => context.push('/property-market');
    return Scaffold(backgroundColor: EbrokerDesign.page,
      appBar: AppBar(backgroundColor: EbrokerDesign.page, elevation: 0,
        automaticallyImplyLeading: false, titleSpacing: 16,
        title: GestureDetector(onTap: openMap, child: Row(children: [
          EbrokerImage('home_active', size: 24.rw(context), color: scheme.primary), const SizedBox(width: 10),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            EbrokerText('الموقع', size: 12, maxLines: 1),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: EbrokerText('صنعاء', size: 14, weight: FontWeight.w600, maxLines: 1)),
              SizedBox(width: 4), EbrokerImage('down_arrow', size: 16, color: EbrokerDesign.textLight),
            ]),
          ])),
        ])), actions: [Padding(padding: const EdgeInsetsDirectional.only(end: 16),
          child: Semantics(button: true, label: 'الإشعارات', child: Tooltip(message: 'الإشعارات',
            child: GestureDetector(onTap: () => context.push('/notifications'),
              child: Container(width: 40, height: 40, alignment: Alignment.center,
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: EbrokerDesign.border), borderRadius: BorderRadius.circular(6)),
                child: const EbrokerImage('notification', size: 20, color: EbrokerDesign.text))))))]),
      body: RefreshIndicator(onRefresh: () async {
        try { final future = ref.refresh(nearbyPropertiesProvider(_query).future); await future; }
        catch (_) { /* Provider keeps its error/retry state. */ }
      }, child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.only(top: 8, right: 18, left: 18), child: Row(children: [
          Expanded(child: Semantics(button: true, label: 'البحث عن عقار', child: GestureDetector(
            key: const ValueKey('home-search'), onTap: openMap, child: AbsorbPointer(child: SizedBox(height: 48.rh(context), child: TextField(readOnly: true,
              decoration: InputDecoration(hintText: 'ابحث عن عقار أو منطقة...', prefixIcon: Padding(padding: const EdgeInsets.all(8), child: EbrokerImage('search', color: scheme.primary))))))))),
          const SizedBox(width: 8), Semantics(button: true, label: 'الخريطة', child: GestureDetector(
            key: const ValueKey('home-map'), onTap: openMap, child: Container(width: 48.rw(context), height: 48.rh(context), alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: EbrokerDesign.border), borderRadius: BorderRadius.circular(4)),
              child: EbrokerImage('propertymap', color: scheme.primary)))),
        ]))),
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
          child: Material(color: scheme.primary.withValues(alpha: .045), borderRadius: BorderRadius.circular(8),
            child: InkWell(key: const ValueKey('home-smart-search'), borderRadius: BorderRadius.circular(8),
              onTap: () => context.push('/smart-search'), child: Padding(padding: const EdgeInsets.all(14),
                child: Row(children: [EbrokerIcon(Icons.auto_awesome_outlined, size: 20, color: scheme.primary), const SizedBox(width: 10),
                  const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    EbrokerText('صف لي العقار الذي تبحث عنه…', size: 14, weight: FontWeight.w600),
                    SizedBox(height: 3), EbrokerText('البحث الذكي · فلاتر مقترحة يمكنك تعديلها', size: 12, color: EbrokerDesign.textLight),
                  ])), const SizedBox(width: 8), EbrokerIcon(Icons.chevron_left, size: 18, color: scheme.primary),
                ])))))),
        if (widget.showAdvertiserActions) SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
          child: Wrap(spacing: 12, children: [
            TextButton.icon(onPressed: () => context.push('/broker/workspace'), icon: const EbrokerIcon(Icons.work_outline, size: 18), label: const Text('إدارة عملي')),
            TextButton.icon(onPressed: () => context.push('/add-property'), icon: const EbrokerIcon(Icons.add, size: 18), label: const Text('إضافة عقار')),
          ]))),
        SliverToBoxAdapter(child: EbrokerTitleHeader(title: 'البحث حسب الفئة', onSeeAll: openMap)),
        SliverToBoxAdapter(child: SizedBox(height: 44.rh(context), child: ListView(scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 18), children: [
            for (final category in const [('الكل', null), ('شقق', 'apartment'), ('أدوار', 'floor'), ('عمائر', 'building'), ('منازل', 'house'), ('فلل', 'villa'), ('أراضٍ', 'land'), ('محلات', 'shop'), ('مكاتب', 'office'), ('مزارع', 'farm')])
              Padding(padding: const EdgeInsetsDirectional.only(end: 5), child: EbrokerCategoryCard(
                label: category.$1, icon: ebrokerCategoryIcon(category.$2), selected: _type == category.$2,
                onTap: () => setState(() => _type = category.$2))),
          ]))),
        SliverToBoxAdapter(child: EbrokerTitleHeader(title: 'عقارات في صنعاء', onSeeAll: openMap)),
        properties.when(
          loading: () => SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Column(children: const [AppSkeleton(key: ValueKey('home-feed-loading'), height: 250, radius: 8), SizedBox(height: 8), AppSkeleton(height: 80, radius: 4)]))),
          error: (error, _) => SliverToBoxAdapter(child: AppErrorState(message: friendlyApiError(error), onRetry: () => ref.invalidate(nearbyPropertiesProvider(_query)))),
          data: (items) => items.isEmpty ? SliverToBoxAdapter(child: AppEmptyState(title: 'لا توجد عقارات في هذا النطاق',
            message: 'يمكنك استكشاف مناطق أخرى على الخريطة.', actionLabel: 'استكشاف الخريطة', onAction: openMap))
            : SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 18), sliver: SliverList(delegate: SliverChildBuilderDelegate((context, index) {
              final property = items[index];
              return Padding(padding: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                EbrokerPropertyHorizontalCard(key: ValueKey('home-property-${property.id}'), imageFirst: true, title: property.title,
                  price: property.price.toStringAsFixed(0), currency: property.currency, imageUrl: property.mainImage, location: property.address,
                  categoryLabel: ebrokerPropertyTypeLabel(property.type),
                  purposeLabel: property.purpose == 'rent' ? 'للإيجار' : 'للبيع', onTap: () => context.push('/properties/${property.id}')),
                if (property.priceDisplayNote != null) Padding(padding: const EdgeInsets.only(top: 8), child: EbrokerText(property.priceDisplayNote!, size: 12)),
              ]));
            }, childCount: items.length))),
        ),
        advertisers.maybeWhen(data: (entries) => entries.isEmpty
          ? const SliverToBoxAdapter()
          : SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              EbrokerTitleHeader(title: 'تعرّف على الدلالين', onSeeAll: () => context.push('/brokers')),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 18, vertical: 8), child: BrokerGovernorateFilter()),
              SingleChildScrollView(scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: 18.rw(context)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (var i = 0; i < entries.length; i++) ...[
                    if (i > 0) SizedBox(width: 8.rw(context)),
                    EbrokerAdvertiserCard(width: 320.rw(context),
                      name: entries[i].name, identity: entries[i].typeLabel,
                      rating: entries[i].rating, ratingCount: entries[i].ratingCount,
                      verified: entries[i].verified, photoUrl: entries[i].photoUrl,
                      completedDeals: entries[i].completedDeals, activeListings: entries[i].activeListings,
                      onTap: () => context.push('/advertisers/${entries[i].id}')),
                  ],
                ])),
            ])), orElse: () => const SliverToBoxAdapter()),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ])),
    );
  }
}

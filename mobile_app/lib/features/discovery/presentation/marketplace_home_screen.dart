import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/theme/ebroker_design.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/ebroker_property_card.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../../map/presentation/map_screen.dart';

const homeDiscoveryQuery = NearbyQuery(center: LatLng(15.3694, 44.1910));

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
    void openMap() => context.push('/property-market');
    return Scaffold(backgroundColor: EbrokerDesign.page,
      appBar: AppBar(backgroundColor: EbrokerDesign.page, elevation: 0,
        automaticallyImplyLeading: false, titleSpacing: 16,
        title: GestureDetector(onTap: openMap, child: Row(children: [
          EbrokerImage('home_active', size: 42.rw(context), color: scheme.primary), const SizedBox(width: 10),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            EbrokerText('صنعاء', size: 16, weight: FontWeight.w600, maxLines: 1),
            EbrokerText('اليمن', size: 12, color: EbrokerDesign.textLight, maxLines: 1),
          ])), const EbrokerImage('down_arrow', size: 16, color: EbrokerDesign.textLight),
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
            key: const ValueKey('home-search'), onTap: openMap, child: AbsorbPointer(child: TextField(readOnly: true,
              decoration: InputDecoration(hintText: 'ابحث عن عقار', prefixIcon: Padding(padding: const EdgeInsets.all(8), child: EbrokerImage('search', color: scheme.primary)))))))),
          const SizedBox(width: 8), Semantics(button: true, label: 'الخريطة', child: GestureDetector(
            key: const ValueKey('home-map'), onTap: openMap, child: Container(width: 48.rw(context), height: 48.rh(context), alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: EbrokerDesign.border), borderRadius: BorderRadius.circular(4)),
              child: EbrokerImage('propertymap', color: scheme.primary)))),
        ]))),
        SliverToBoxAdapter(child: EbrokerTitleHeader(title: 'أنواع العقارات', onSeeAll: openMap)),
        SliverToBoxAdapter(child: SizedBox(height: 44.rh(context), child: ListView(scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 18), children: [
            for (final category in const [('الكل', null), ('شقق', 'apartment'), ('منازل', 'house'), ('أراضٍ', 'land')])
              Padding(padding: const EdgeInsetsDirectional.only(end: 5), child: EbrokerCategoryCard(
                label: category.$1, icon: category.$2 == 'land' ? 'location' : 'properties_icon', selected: _type == category.$2,
                onTap: () => setState(() => _type = category.$2))),
          ]))),
        SliverToBoxAdapter(child: EbrokerTitleHeader(title: 'عقارات في صنعاء', onSeeAll: openMap)),
        properties.when(
          loading: () => SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Column(children: const [AppSkeleton(height: 132, radius: 4), SizedBox(height: 8), AppSkeleton(height: 80, radius: 4)]))),
          error: (error, _) => SliverToBoxAdapter(child: AppErrorState(message: friendlyApiError(error), onRetry: () => ref.invalidate(nearbyPropertiesProvider(_query)))),
          data: (items) => items.isEmpty ? SliverToBoxAdapter(child: AppEmptyState(title: 'لا توجد عقارات في هذا النطاق',
            message: 'يمكنك استكشاف مناطق أخرى على الخريطة.', actionLabel: 'استكشاف الخريطة', onAction: openMap))
            : SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 18), sliver: SliverList(delegate: SliverChildBuilderDelegate((context, index) {
              final property = items[index];
              return Padding(padding: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                EbrokerPropertyHorizontalCard(key: ValueKey('home-property-${property.id}'), title: property.title,
                  price: property.price.toStringAsFixed(0), currency: property.currency, imageUrl: property.mainImage, location: property.address,
                  categoryLabel: ebrokerPropertyTypeLabel(property.type),
                  purposeLabel: property.purpose == 'rent' ? 'للإيجار' : 'للبيع', onTap: () => context.push('/properties/${property.id}')),
                if (property.priceDisplayNote != null) Padding(padding: const EdgeInsets.only(top: 8), child: EbrokerText(property.priceDisplayNote!, size: 12)),
              ]));
            }, childCount: items.length))),
        ),
        if (widget.showAdvertiserActions) SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(18),
          child: AppButton(label: 'إضافة عقار', expand: true, icon: Icons.add, onPressed: () => context.push('/add-property')))),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ])),
    );
  }
}

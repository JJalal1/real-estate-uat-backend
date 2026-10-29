import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/ebroker_design.dart';
import '../../../core/branding/aqer_brand.dart';
import '../../../core/widgets/app_components.dart';
import '../../properties/presentation/property_summary_card.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../../../core/widgets/ebroker_home/category_card.dart';
import '../../../core/widgets/ebroker_home/property_card_big.dart';
import '../../../core/widgets/ebroker_home/agent_card.dart';
import '../../../core/widgets/ebroker_home/source_adapters.dart';
import '../../properties/presentation/property_compare_actions.dart';
import '../../map/presentation/map_screen.dart';
import '../../properties/domain/property_details.dart';
import '../../properties/presentation/property_details_screen.dart';
import '../data/marketplace_repository.dart';
import '../data/discovery_location.dart';
import 'home_ai_search_entry.dart';
import 'smart_search_assistant.dart';
import '../data/marketplace_search_session.dart';

const homeDiscoveryQuery = NearbyQuery(center: LatLng(15.3694, 44.1910));

// Kept for existing callers; the current home uses the bounded regional feed.
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
      return details.status == 'published' && advertiser != null ? HomeAdvertiserEntry(id, advertiser) : null;
    } catch (_) { return null; }
  }));
  final unique = <int, HomeAdvertiserEntry>{};
  for (final entry in results.whereType<HomeAdvertiserEntry>()) { unique.putIfAbsent(entry.advertiser.id, () => entry); }
  return unique.values.toList(growable: false);
});

class MarketplaceHomeScreen extends ConsumerStatefulWidget {
  const MarketplaceHomeScreen({this.showAdvertiserActions = false, super.key});
  final bool showAdvertiserActions;
  @override
  ConsumerState<MarketplaceHomeScreen> createState() => _MarketplaceHomeState();
}

class _MarketplaceHomeState extends ConsumerState<MarketplaceHomeScreen> {
  String? _type;
  bool _locationBusy = false;
  final _feedScroll = ScrollController();
  bool _openingSearch = false;
  @override
  void dispose() { _feedScroll.dispose(); super.dispose(); }
  HomeFeedQuery get _query {
    final location = ref.read(homeLocationProvider);
    return (latitude: location.latitude, longitude: location.longitude, governorate: location.governorate, type: _type, purpose: ref.watch(marketplaceSearchControllerProvider).criteria.values['purpose']?.toString(), device: location.device);
  }
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _tryDeviceLocation(); }); }

  Future<void> _tryDeviceLocation({bool prompt = false}) async {
    if (!prompt && ref.read(homeLocationAttemptedProvider)) return;
    ref.read(homeLocationAttemptedProvider.notifier).state = true;
    if (!prompt && ref.read(homeLocationProvider).manual) return;
    var deviceChosen = prompt;
    setState(() => _locationBusy = true);
    try {
      final coordinator = ref.read(discoveryLocationCoordinatorProvider);
      if (prompt) { await coordinator.useDevice(); } else {
        await coordinator.initialize();
        if (mounted && coordinator.shouldOfferChoice && ModalRoute.of(context)?.isCurrent != false) {
          await coordinator.markIntroductionShown();
          if (!mounted) return;
          setState(() => _locationBusy = false);
          final choice = await AppBottomSheet.show<String>(context, builder: (_) => const DiscoveryLocationIntroduction());
          if (!mounted) return;
          if (choice == 'device') {
            deviceChosen = true;
            setState(() => _locationBusy = true);
            await coordinator.useDevice();
          }
          else if (choice == 'manual') { await _chooseLocation(); }
        }
      }
    } catch (_) {
      if (deviceChosen && mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('تعذّر تحديد موقعك. يمكنك اختيار المنطقة يدويًا.'),
        action: SnackBarAction(label: 'اختيار منطقة', onPressed: _chooseLocation))); }
    } finally { if (mounted) setState(() => _locationBusy = false); }
  }

  Future<void> _chooseLocation() async {
    final choice = await AppBottomSheet.show<Object>(context, builder: (_) => const _HomeLocationSheet());
    if (!mounted) return;
    if (choice is HomeLocation) { await ref.read(discoveryLocationCoordinatorProvider).selectManual(choice); }
    else if (choice == 'device') { await _tryDeviceLocation(prompt: true); }
  }

  Future<void> _openSearch({bool filters = false}) async {
    if (_openingSearch) return;
    _openingSearch = true;
    ref.read(marketplaceSearchControllerProvider.notifier).prepareSearch(type: _type);
    try { await context.push(filters ? '/marketplace-search?filters=1' : '/marketplace-search'); }
    finally { _openingSearch = false; }
  }

  void _openMap() {
    FocusScope.of(context).unfocus();
    final controller = ref.read(marketplaceSearchControllerProvider.notifier);
    controller.prepareSearch(type: _type);
    controller.enterMap();
    final place = ref.read(homeLocationProvider);
    context.push(Uri(path: '/marketplace-search-map', queryParameters: {
      if (place.manual) ...{'lat': '${place.latitude}', 'lon': '${place.longitude}',
        if (place.governorate != null) 'governorate': place.governorate!},
    }).toString());
  }
  void _section(String section,String? governorate) {
    final location=ref.read(homeLocationProvider);
    context.push(Uri(path:'/marketplace-section',queryParameters:{'section':section,
      if (ref.read(marketplaceSearchControllerProvider).criteria.values['purpose'] != null) 'purpose': ref.read(marketplaceSearchControllerProvider).criteria.values['purpose'].toString(),
      if(governorate!=null && section!='nearby')'governorate':governorate,if(_type!=null)'type':_type!,
      if(section=='nearby')...{'lat':'${location.latitude}','lon':'${location.longitude}'},
    }).toString());
  }


  @override
  Widget build(BuildContext context) {
    final location = ref.watch(homeLocationProvider), theme = Theme.of(context);
    final query = _query, purpose = ref.watch(marketplaceSearchControllerProvider).criteria.values['purpose']?.toString();
    final feed = ref.watch(marketplaceFeedProvider(query));
    ref.listen(marketplaceFeedProvider(query), (_, next) {
      final governorate = next.asData?.value.governorate;
      final current = ref.read(homeLocationProvider);
      if (!current.device || governorate == null) return;
      unawaited(() async {
        try {
          final registry = await ref.read(homeLocationsProvider.future);
          if (!mounted || !identical(ref.read(homeLocationProvider), current)) return;
          await ref.read(discoveryLocationCoordinatorProvider).rememberPublicRegion(governorate, registry);
        } catch (_) { /* Public region caching never blocks browsing. */ }
      }());
    });
    final data = feed.asData?.value;
    return Scaffold(backgroundColor: EbrokerDesign.page,
      appBar: AppBar(backgroundColor: EbrokerDesign.page, elevation: 0, automaticallyImplyLeading: false,
        toolbarHeight: (58 + (MediaQuery.textScalerOf(context).scale(15) - 15) * 2).clamp(58, 112).toDouble(),
        titleSpacing: 18, title: Row(children: [
          const AqerBrandMark(size: 32), const SizedBox(width: 8),
          Flexible(child: Semantics(button: true, label: 'تغيير المنطقة', child: TextButton.icon(
            key: const ValueKey('home-location'), onPressed: _chooseLocation,
            icon: _locationBusy ? const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const EbrokerImage('location', size: 17),
            label: Text(data?.label ?? location.label, maxLines: 1, overflow: TextOverflow.ellipsis)))),
          Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('عقار اليمن', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700)),
            Text('بيتك… يبدأ من هنا', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(fontSize: 10)),
          ])),
        ]), actions: [IconButton(tooltip: 'الإشعارات', onPressed: () => context.push('/notifications'),
          icon: const EbrokerImage('notification', size: 21))]),
      body: SmartSearchAssistantLayer(onPressed: () => context.push('/smart-search'), child: RefreshIndicator(onRefresh: () async {
        try { ref.read(marketplaceRepositoryProvider).invalidateFeed(query); ref.invalidate(marketplaceFeedProvider(query));
          await ref.read(marketplaceFeedProvider(query).future); } catch (_) { /* Inline retry retains only this query. */ }
      }, child: CustomScrollView(key: const PageStorageKey('marketplace-home'), controller: _feedScroll,
        cacheExtent: 0, physics: const AlwaysScrollableScrollPhysics(), slivers: [
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(18, 8, 18, 0), child: Column(children: [
          Row(children: [
            _HomeCircleAction(key: const ValueKey('home-filters'), tooltip: 'فلاتر البحث', icon: 'filter',
              onTap: () => _openSearch(filters: true)),
            const SizedBox(width: 8), Expanded(child: TextField(key: const ValueKey('home-search'), readOnly: true,
              onTap: _openSearch, decoration: const InputDecoration(hintText: 'ابحث عن عقار أو منطقة…',
                filled: true, fillColor: Colors.white, suffixIcon: Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(18)), borderSide: BorderSide.none)))),
            const SizedBox(width: 8), _HomeCircleAction(key: const ValueKey('home-map'),
              tooltip: 'الخريطة', icon: 'propertymap', onTap: _openMap),
          ]),
          Align(alignment: AlignmentDirectional.centerEnd, child: Wrap(spacing: 4, children: [
            for (final entry in const {'rent': 'إيجار', 'sale': 'بيع'}.entries)
              Semantics(button: true, selected: purpose == entry.key, child: InkWell(
                key: ValueKey('home-purpose-${entry.key}'), borderRadius: BorderRadius.circular(20),
                onTap: () => ref.read(marketplaceSearchControllerProvider.notifier).choosePurpose(entry.key),
                child: Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                  child: AnimatedContainer(duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 16),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(20),
                      color: purpose == entry.key ? theme.colorScheme.primary : theme.colorScheme.primary.withValues(alpha: .06)),
                    child: Text(entry.value, style: theme.textTheme.labelMedium?.copyWith(
                      color: purpose == entry.key ? Colors.white : theme.colorScheme.primary)))))),
          ])),
          HomeAiSearchEntry(wide: true, location: data?.governorate ?? location.governorate ?? 'صنعاء', type: _type, purpose: purpose),
        ]))),
        SliverToBoxAdapter(child: EbrokerTitleHeader(title: 'ماذا تبحث عنه؟', onSeeAll: _openMap)),
        SliverToBoxAdapter(child: SizedBox(height: 56 + (MediaQuery.textScalerOf(context).scale(14) - 14) * 2,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 18), children: [
            for (final category in const [('الكل', null), ('شقق', 'apartment'), ('منازل', 'house'), ('فلل', 'villa'),
              ('عمائر', 'building'), ('أراضٍ', 'land'), ('محلات', 'shop'), ('مكاتب', 'office'), ('مزارع', 'farm')])
              EbrokerHomeCategoryCard(frontSpacing: category.$2 != null,
                category: SourceCategory(category.$1, category.$2, selected: _type == category.$2),
                onTapCategory: (_) => setState(() => _type = category.$2)),
          ]))),
        if (feed.hasValue && (feed.isRefreshing || (feed.hasError && isTransientApiFailure(feed.error!))))
          SliverToBoxAdapter(child: AppRefreshStatus(loading: feed.isLoading,
            error: feed.hasError ? friendlyApiError(feed.error!) : null,
            onRetry: () => ref.invalidate(marketplaceFeedProvider(query)))),
        feed.when(skipLoadingOnReload: false, skipError: feed.hasValue && feed.hasError && isTransientApiFailure(feed.error!),
          loading: () => const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(18),
            child: AppSkeleton(key: ValueKey('home-feed-loading'), height: 270, radius: 8))),
          error: (error, _) => SliverToBoxAdapter(child: AppErrorState(message: friendlyApiError(error),
            onRetry: () => ref.invalidate(marketplaceFeedProvider(query)))), data: _feedSliver),
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ]))),
    );
  }

  Widget _feedSliver(MarketplaceFeed data) {
    final slivers = <Widget>[];
    if (data.brokers.isNotEmpty) {
      slivers.add(SliverToBoxAdapter(child: EbrokerTitleHeader(title: 'دلالون ومكاتب في ${data.label}',
        onSeeAll: () => context.push('/brokers'))));
      slivers.add(SliverToBoxAdapter(child: SingleChildScrollView(key: const PageStorageKey('home-brokers-rail'), scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final broker in data.brokers) Padding(padding: const EdgeInsetsDirectional.only(end: 8),
            child: EbrokerHomeAgentCard(profile: broker,
              width: (MediaQuery.sizeOf(context).width - 60).clamp(240, 320).toDouble(),
              onTap: () => context.push('/advertisers/${broker.id}'))),
        ]))));
    }
    final seen = <int>{}, width = MediaQuery.sizeOf(context).width;
    final columns = MediaQuery.textScalerOf(context).scale(14) > 20 || width < 360 ? 1 : width >= 900 ? 4 : width >= 600 ? 3 : 2;
    for (final key in data.sectionOrder) {
      final rows = (data.sections[key] ?? const <PropertySummary>[])
        .where((row) => !seen.contains(row.id)).take(columns == 1 ? 4 : columns * 2).toList();
      if (rows.isEmpty) continue;
      seen.addAll(rows.map((row) => row.id));
      final title = switch (key) { 'nearby' => 'قريبة منك', 'spotlight' => 'عقارات مميزة',
        'sale' => 'عقارات للبيع', 'rent' => 'عقارات للإيجار', _ => 'أحدث العقارات' };
      slivers.add(SliverToBoxAdapter(child: EbrokerTitleHeader(title: title, onSeeAll: () => _section(key, data.governorate))));
      for (var offset = 0; offset < rows.length; offset += columns) {
        final group = rows.skip(offset).take(columns).toList();
        slivers.add(SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < columns; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: i >= group.length ? const SizedBox.shrink() : EbrokerHomePropertyCard(
                key: ValueKey('home-property-${group[i].id}'), property: SourceProperty(group[i]), isFromGrid: columns > 1,
                favorite: PropertyFavoriteAction(propertyId: group[i].id, enabled: group[i].status == 'published', sourceStyle: true),
                action: PropertyCompareAction(propertyId: group[i].id, enabled: group[i].status == 'published'),
                facts: summaryPropertyFacts(group[i]).take(3).toList(),
                onTap: () => context.push('/properties/${group[i].id}', extra: group[i]))),
            ],
          ]))));
      }
    }
    if (seen.isEmpty) {
      slivers.add(SliverToBoxAdapter(child: AppEmptyState(
      title: ref.read(marketplaceSearchControllerProvider).criteria.values['purpose'] == null
        ? 'لا توجد عقارات في هذه المنطقة الآن' : 'لا توجد عقارات مطابقة في هذه المنطقة الآن', message: 'يمكنك تغيير المنطقة أو الغرض.',
      actionLabel: 'تغيير المنطقة', onAction: _chooseLocation)));
    }
    // Keep Aqer's original SliverList host: on retained Flutter 3.27, grouping
    // all box adapters leaves far media geometry unusable after a large jump.
    // The original eBroker card/section bodies remain inside this lazy host.
    return SliverList(delegate: SliverChildListDelegate.fixed([
      for (final section in slivers.cast<SliverToBoxAdapter>()) section.child!,
    ]));
  }
}

class _HomeCircleAction extends StatelessWidget {
  const _HomeCircleAction({required this.tooltip, required this.icon, required this.onTap, super.key});
  final String tooltip, icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => IconButton(tooltip: tooltip, onPressed: onTap,
    style: IconButton.styleFrom(minimumSize: const Size(48, 48),
      backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: .06)),
    icon: EbrokerImage(icon, size: 22, color: Theme.of(context).colorScheme.primary));
}

/// A foreground choice; displaying this explanation never requests OS access.
class DiscoveryLocationIntroduction extends StatelessWidget {
  const DiscoveryLocationIntroduction({super.key});
  @override
  Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl,
    child: SafeArea(top: false, child: SingleChildScrollView(padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('عقارات في منطقتك', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        const Text('اختر محافظتك أو اسمح بموقعك التقريبي لعرض العقارات والدلالين القريبين. يمكنك المتابعة وتغيير المنطقة لاحقًا.'),
        const SizedBox(height: 20),
        AppButton(key: const ValueKey('location-introduction-device'), label: 'تحديد موقعي',
          icon: Icons.my_location, expand: true, onPressed: () => Navigator.pop(context, 'device')),
        const SizedBox(height: 8),
        TextButton(key: const ValueKey('location-introduction-manual'), onPressed: () => Navigator.pop(context, 'manual'),
          child: const Text('اختيار المحافظة يدويًا')),
        TextButton(key: const ValueKey('location-introduction-later'), onPressed: () => Navigator.pop(context),
          child: const Text('المتابعة الآن')),
      ]))));
}

class _HomeLocationSheet extends ConsumerWidget {
  const _HomeLocationSheet();
  @override
  Widget build(BuildContext context, WidgetRef ref) => Directionality(textDirection: TextDirection.rtl, child: SizedBox(
    height: MediaQuery.sizeOf(context).height * .60, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.fromLTRB(18, 18, 18, 6), child: Text('أين تبحث؟', style: Theme.of(context).textTheme.titleLarge)),
      ListTile(leading: const EbrokerIcon(Icons.near_me_outlined, size: 22), title: const Text('استخدم موقعي'),
        onTap: () => Navigator.of(context).pop('device')),
      ListTile(leading: const EbrokerIcon(Icons.location_on_outlined, size: 22), title: const Text('صنعاء'),
        onTap: () => Navigator.of(context).pop(const HomeLocation(governorate: 'صنعاء', manual: true))),
      const Divider(height: 1),
      Expanded(child: ref.watch(homeLocationsProvider).when(loading: () => const AppLoadingState(),
        error: (error, _) => AppErrorState(message: friendlyApiError(error), onRetry: () => ref.invalidate(homeLocationsProvider)),
        data: (rows) => ListView(children: [for (final row in rows.where((row) => row.label != 'صنعاء')) ListTile(
          leading: const EbrokerIcon(Icons.location_on_outlined, size: 22), title: Text(row.label), onTap: () => Navigator.of(context).pop(row))]))),
    ])));
}

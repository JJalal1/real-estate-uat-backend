import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/ebroker_design.dart';
import '../../../core/branding/aqer_brand.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/viewport_media.dart';
import '../../properties/presentation/property_summary_card.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../../broker/domain/broker_models.dart';
import '../../map/presentation/map_screen.dart';
import '../../properties/domain/property_details.dart';
import '../../properties/presentation/property_details_screen.dart';
import '../data/marketplace_repository.dart';
import '../data/discovery_location.dart';
import 'home_ai_search_entry.dart';
import 'smart_search_assistant.dart';

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
  HomeFeedQuery get _query {
    final location = ref.read(homeLocationProvider);
    return (latitude: location.latitude, longitude: location.longitude, governorate: location.governorate, type: _type, device: location.device);
  }
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _tryDeviceLocation(); }); }

  Future<void> _tryDeviceLocation({bool prompt = false}) async {
    if (!prompt && ref.read(homeLocationAttemptedProvider)) return;
    ref.read(homeLocationAttemptedProvider.notifier).state = true;
    if (!prompt && ref.read(homeLocationProvider).manual) return;
    setState(() => _locationBusy = true);
    try {
      final coordinator = ref.read(discoveryLocationCoordinatorProvider);
      if (prompt) { await coordinator.useDevice(); } else {
        await coordinator.initialize();
        if (mounted && coordinator.shouldOfferChoice) {
          await coordinator.markIntroductionShown();
          if (!mounted) return;
          final choice = await AppBottomSheet.show<String>(context, builder: (_) => const DiscoveryLocationIntroduction());
          if (!mounted) return;
          if (choice == 'device') { await coordinator.useDevice(); }
          else if (choice == 'manual') { await _chooseLocation(); }
        }
      }
    } catch (_) {
      if (prompt && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّر تحديد موقعك. يمكنك اختيار المنطقة يدويًا.')));
    } finally { if (mounted) setState(() => _locationBusy = false); }
  }

  Future<void> _chooseLocation() async {
    final choice = await AppBottomSheet.show<Object>(context, builder: (_) => const _HomeLocationSheet());
    if (!mounted) return;
    if (choice is HomeLocation) { await ref.read(discoveryLocationCoordinatorProvider).selectManual(choice); }
    else if (choice == 'device') { await _tryDeviceLocation(prompt: true); }
  }

  void _openMap() {
    final location = ref.read(homeLocationProvider);
    context.push(Uri(path: '/property-market', queryParameters: {'lat': '${location.latitude}', 'lon': '${location.longitude}',
      if(location.governorate!=null) 'governorate':location.governorate!, if (_type != null) 'type': _type!}).toString());
  }
  void _section(String section,String? governorate) {
    final location=ref.read(homeLocationProvider);
    context.push(Uri(path:'/marketplace-section',queryParameters:{'section':section,
      if(governorate!=null && section!='nearby')'governorate':governorate,if(_type!=null)'type':_type!,
      if(section=='nearby')...{'lat':'${location.latitude}','lon':'${location.longitude}'},
    }).toString());
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), location = ref.watch(homeLocationProvider);
    final feed = ref.watch(marketplaceFeedProvider(_query));
    ref.listen(marketplaceFeedProvider(_query), (_, next) {
      final governorate = next.asData?.value.governorate;
      final current = ref.read(homeLocationProvider);
      if (!current.device || governorate == null) return;
      unawaited(() async {
        try {
          final registry = await ref.read(homeLocationsProvider.future);
          if (!mounted || !identical(ref.read(homeLocationProvider), current)) return;
          await ref.read(discoveryLocationCoordinatorProvider).rememberPublicRegion(governorate, registry);
        } catch (_) { /* Public context caching never blocks discovery. */ }
      }());
    });
    final data = feed.asData?.value;
    final label = data?.label ?? location.label;
    return Scaffold(backgroundColor: EbrokerDesign.page,
      appBar: AppBar(toolbarHeight: (58 + (MediaQuery.textScalerOf(context).scale(15) - 15) * 2).clamp(58, 112).toDouble(),
        backgroundColor: EbrokerDesign.page, elevation: 0, automaticallyImplyLeading: false, titleSpacing: 18,
        title: Semantics(button: true, label: 'تغيير المنطقة', child: InkWell(onTap: _chooseLocation, child: Row(children: [
          const AqerBrandMark(size: 32), const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const EbrokerText('الموقع', size: 11),
            Row(children: [Flexible(child: EbrokerText(label, size: 15, weight: FontWeight.w600, maxLines: 1)), const SizedBox(width: 4),
              if (_locationBusy) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              else const EbrokerImage('down_arrow', size: 15, color: EbrokerDesign.textLight)]),
          ])),
        ]))), actions: [Padding(padding: const EdgeInsetsDirectional.only(end: 12), child: IconButton(
          tooltip: 'الإشعارات', onPressed: () => context.push('/notifications'), icon: const EbrokerImage('notification', size: 21)))]),
      body: SmartSearchAssistantLayer(onPressed: () {
        context.push('/smart-search');
      }, child: RefreshIndicator(onRefresh: () async { try { ref.read(marketplaceRepositoryProvider).invalidateFeed(_query); ref.invalidate(marketplaceFeedProvider(_query)); await ref.read(marketplaceFeedProvider(_query).future); } catch (_) {} },
        child: CustomScrollView(key: const PageStorageKey('marketplace-home'), cacheExtent: 0,
          physics: const AlwaysScrollableScrollPhysics(), slivers: [
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(18, 8, 18, 0), child: Row(children: [
            Expanded(child: Semantics(button: true, label: 'البحث عن عقار', child: GestureDetector(key: const ValueKey('home-search'), onTap: _openMap,
              child: AbsorbPointer(child: TextField(readOnly: true, decoration: InputDecoration(hintText: 'ابحث عن عقار أو منطقة…',
                prefixIcon: Padding(padding: const EdgeInsets.all(10), child: EbrokerImage('search', color: theme.colorScheme.primary)))))))),
            const SizedBox(width: 8), IconButton.filledTonal(key: const ValueKey('home-map'), tooltip: 'الخريطة', onPressed: _openMap,
              icon: EbrokerImage('propertymap', size: 22, color: theme.colorScheme.primary)),
          ]))),
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
            child: Row(children: [
              HomeAiSearchEntry(location: data?.governorate ?? location.governorate ?? 'صنعاء', type: _type),
              const SizedBox(width: 10),
              Expanded(child: Text('صف ما تحتاجه بالنص أو الصوت', style: theme.textTheme.bodySmall)),
            ]))),
          SliverToBoxAdapter(child: EbrokerTitleHeader(title: 'ماذا تبحث عنه؟', onSeeAll: _openMap)),
          SliverToBoxAdapter(child: SizedBox(height: 48 + (MediaQuery.textScalerOf(context).scale(13) - 13) * 2, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 18), children: [
            for (final category in const [('الكل', null), ('شقق', 'apartment'), ('منازل', 'house'), ('فلل', 'villa'), ('عمائر', 'building'), ('أراضٍ', 'land'), ('محلات', 'shop'), ('مكاتب', 'office'), ('مزارع', 'farm')])
              Padding(padding: const EdgeInsetsDirectional.only(end: 6), child: EbrokerCategoryCard(label: category.$1, icon: ebrokerCategoryIcon(category.$2),
                selected: _type == category.$2, onTap: () => setState(() => _type = category.$2))),
          ]))),
          if (feed.hasValue && (feed.isRefreshing || (feed.hasError && isTransientApiFailure(feed.error!)))) SliverToBoxAdapter(
            child: AppRefreshStatus(loading: feed.isLoading, error: feed.hasError ? friendlyApiError(feed.error!) : null,
              onRetry: () => ref.invalidate(marketplaceFeedProvider(_query)))),
          feed.when(
            skipLoadingOnReload: false, skipError: feed.hasValue && feed.hasError && isTransientApiFailure(feed.error!),
            loading: () => const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(18), child: AppSkeleton(key: ValueKey('home-feed-loading'), height: 270, radius: 12))),
            error: (error, _) => SliverToBoxAdapter(child: AppErrorState(message: friendlyApiError(error), onRetry: () => ref.invalidate(marketplaceFeedProvider(_query)))),
            data: _feedSliver,
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ]))),
    );
  }

  Widget _property(PropertySummary row, bool large) => PropertySummaryCard(key: ValueKey('home-property-${row.id}'),
    property: row, imageFirst: large);

  Widget _feedSliver(MarketplaceFeed data) {
    final entries = <WidgetBuilder>[];
    if (data.brokers.isNotEmpty) {
      entries.add((_) => EbrokerTitleHeader(title: 'أفضل الدلالين في ${data.label}', onSeeAll: () => context.push('/brokers')));
      entries.add((_) => SingleChildScrollView(scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final broker in data.brokers) Padding(padding: const EdgeInsetsDirectional.only(end: 10), child: _HomeBrokerCard(profile: broker)),
        ])));
    }
    for (final key in data.sectionOrder) {
      final rows = data.sections[key] ?? const <PropertySummary>[];
      if (rows.isEmpty) continue;
      final title = switch (key) { 'nearby' => 'قريبة منك', 'spotlight' => 'عقارات تستحق نظرة',
        'sale' => 'تملّك في منطقتك', 'rent' => 'مساحة تناسب حياتك', _ => 'أحدث العقارات' };
      entries.add((_) => EbrokerTitleHeader(title: title, onSeeAll: () => _section(key, data.governorate)));
      if (const ['latest', 'nearby'].contains(key)) {
        for (final row in rows.take(3)) {
          entries.add((_) => Padding(padding: const EdgeInsets.fromLTRB(18, 0, 18, 12), child: _property(row, false)));
        }
      } else {
        // Rails are bounded by the feed contract. Keep intrinsic height for
        // large Arabic text; ViewportMedia gates each horizontal image too.
        entries.add((_) => SingleChildScrollView(scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 18), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final row in rows) Padding(padding: const EdgeInsetsDirectional.only(end: 12),
              child: SizedBox(width: (MediaQuery.sizeOf(context).width - 64).clamp(250, 380).toDouble(), child: _property(row, true))),
          ])));
      }
    }
    if (data.sections.values.every((rows) => rows.isEmpty)) {
      entries.add((_) => AppEmptyState(title: 'لا توجد عقارات في هذه المنطقة الآن', message: 'استكشف الخريطة أو اختر منطقة أخرى.',
        actionLabel: 'تغيير المنطقة', onAction: _chooseLocation));
    }
    return SliverList(delegate: SliverChildBuilderDelegate((context, index) => entries[index](context), childCount: entries.length));
  }
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

class _HomeBrokerCard extends StatelessWidget {
  const _HomeBrokerCard({required this.profile});
  final BrokerProfile profile;
  @override
  Widget build(BuildContext context) => SizedBox(width: 238, child: AppSurface(onTap: () => context.push('/advertisers/${profile.id}'), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [ClipOval(child: profile.photoUrl == null ? const EbrokerImage('defaultProfileIcon', size: 54)
      : SizedBox.square(dimension: 54, child: ViewportMedia(builder: (_) => Image.network(profile.photoUrl!, width: 54, height: 54, fit: BoxFit.cover, cacheWidth: 180,
        errorBuilder: (_, __, ___) => const EbrokerImage('defaultProfileIcon', size: 54))))), const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(profile.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 3), Row(children: [if (profile.verified) ...[EbrokerIcon(Icons.verified_outlined, size: 14, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 3)],
          Expanded(child: Text(profile.typeLabel, style: Theme.of(context).textTheme.bodySmall))])])),
    ]), const SizedBox(height: 12),
    if (profile.ratingCount > 0) Row(children: [const EbrokerIcon(Icons.star_outline, size: 17, color: Colors.amber), const SizedBox(width: 4),
      Expanded(child: Text('${profile.rating.toStringAsFixed(1)} · ${profile.ratingCount} تقييمًا', style: Theme.of(context).textTheme.bodySmall))])
    else Text('جديد على المنصة', style: Theme.of(context).textTheme.bodySmall),
    const SizedBox(height: 6), Text('${profile.completedDeals} صفقات مؤكدة', style: Theme.of(context).textTheme.bodySmall),
  ])));
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

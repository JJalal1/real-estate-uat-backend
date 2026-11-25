import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/network/conditional_image_prefetch.dart';
import '../../../core/widgets/viewport_media.dart';
import '../../broker/domain/broker_models.dart';
import '../../../core/branding/aqer_brand.dart';
import '../../../core/widgets/app_components.dart';
import '../../account/data/auth_controller.dart';
import '../../properties/presentation/property_summary_card.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../../map/presentation/map_screen.dart';
import '../../messages/presentation/unread_inbox_badge.dart';
import '../../properties/data/recent_properties_store.dart';
import '../../properties/domain/property_details.dart';
import '../../properties/presentation/property_details_screen.dart';
import '../data/marketplace_repository.dart';
import '../domain/smart_search_filters.dart';
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
  const MarketplaceHomeScreen({super.key});
  @override
  ConsumerState<MarketplaceHomeScreen> createState() => _MarketplaceHomeState();
}

class _MarketplaceHomeState extends ConsumerState<MarketplaceHomeScreen> {
  bool _locationBusy = false;
  final _feedScroll = ScrollController();
  bool _openingSearch = false;
  int _openingEpoch = 0;
  @override
  void dispose() { _feedScroll.dispose(); super.dispose(); }
  HomeFeedQuery get _query {
    final location = ref.read(homeLocationProvider);
    final filters = ref.watch(marketplaceSearchControllerProvider).criteria;
    return HomeFeedQuery(latitude: location.latitude, longitude: location.longitude, governorate: location.governorate, governorateCode: location.governorateCode, accuracyMetres: location.accuracyMetres,
      type: filters.values['type']?.toString(), purpose: filters.values['purpose']?.toString(),
      filters: filters, device: location.device);
  }
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _tryDeviceLocation(); }); }

  Future<void> _tryDeviceLocation({bool prompt = false}) async {
    if (!prompt && ref.read(homeLocationAttemptedProvider)) return;
    ref.read(homeLocationAttemptedProvider.notifier).state = true;
    if (!prompt && ref.read(homeLocationProvider).manual) return;
    final deviceChosen = prompt;
    setState(() => _locationBusy = true);
    try {
      final coordinator = ref.read(discoveryLocationCoordinatorProvider);
      if (prompt) { await coordinator.useDevice(); } else {
        await coordinator.initialize();
      }
      if (deviceChosen && mounted && ref.read(homeLocationProvider).device) {
        ref.read(marketplaceSearchControllerProvider.notifier).locationChanged();
      }
      if (deviceChosen && mounted && ref.read(homeLocationProvider).needsConfirmation) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('دقة الموقع لا تكفي لتأكيد المحافظة. اخترها يدويًا.'),
          action: SnackBarAction(label: 'اختيار المحافظة', onPressed: _chooseLocation)));
      }
    } catch (_) {
      if (deviceChosen && mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('تعذّر تحديد موقعك. يمكنك اختيار المنطقة يدويًا.'),
        action: SnackBarAction(label: 'اختيار منطقة', onPressed: _chooseLocation))); }
    } finally { if (mounted) setState(() => _locationBusy = false); }
  }

  Future<void> _chooseLocation() async {
    final choice = await AppBottomSheet.show<Object>(context, builder: (_) => const MarketplaceLocationSheet());
    if (!mounted) return;
    if (choice is HomeLocation) {
      await ref.read(discoveryLocationCoordinatorProvider).selectManual(choice);
      if (mounted) ref.read(marketplaceSearchControllerProvider.notifier).locationChanged();
    }
    else if (choice == 'device') { await _tryDeviceLocation(prompt: true); }
  }

  Future<void> _pushHomeRoute(String location, VoidCallback prepare) async {
    if (_openingSearch) return;
    _openingSearch = true;
    final epoch = ++_openingEpoch;
    void release() { if (epoch == _openingEpoch) _openingSearch = false; }
    try {
      prepare();
      final navigation = context.push<void>(location);
      // A platform deep link can replace a pushed page without completing its
      // pop Future. Guard duplicate entry only until the first pushed frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => release());
      await navigation;
    } finally { release(); }
  }

  Future<void> _openSearch() => _pushHomeRoute(
    '/marketplace-search',
    () => ref.read(marketplaceSearchControllerProvider.notifier).begin());

  Future<void> _openMap() async {
    final place = ref.read(homeLocationProvider);
    final controller = ref.read(marketplaceSearchControllerProvider.notifier);
    int? mapJourney;
    try {
      await _pushHomeRoute(Uri(path: '/marketplace-search-map', queryParameters: {
        if (place.manual) ...{'lat': '${place.latitude}', 'lon': '${place.longitude}',
          if (place.governorate != null) 'governorate': place.governorate!},
      }).toString(), () {
        FocusScope.of(context).unfocus();
        mapJourney = controller.enterMap();
      });
    } finally {
      if (mapJourney != null) controller.leaveMap(mapJourney);
    }
  }
  void _section(String section, String? governorate, {SmartSearchFilters? filters}) {
    final location = ref.read(homeLocationProvider);
    final criteria = filters ?? SmartSearchFilters.fromMap({
      ...ref.read(marketplaceSearchControllerProvider).criteria.values,
      if (location.governorateCode != null && !location.needsConfirmation) 'governorate_code': location.governorateCode,
    });
    context.push(Uri(path: '/marketplace-section', queryParameters: {
      'section': section,
      if (criteria.values['purpose'] != null) 'purpose': criteria.values['purpose'].toString(),
      if (governorate != null) 'governorate': governorate,
    }).toString(), extra: criteria);
  }


  @override
  Widget build(BuildContext context) {
    final location = ref.watch(homeLocationProvider), theme = Theme.of(context);
    final background = theme.colorScheme.surfaceContainerLow;
    final selectedTypes = ref.watch(marketplaceSearchControllerProvider).criteria.selectedTypes;
    final professional = ref.watch(authControllerProvider.select((state) =>
      state.asData?.value?.hasVerifiedProfessionalProfile == true));
    final query = _query;
    final criteria = query.effectiveFilters;
    final locationKnown = !location.needsConfirmation && (location.governorate != null || location.governorateCode != null);
    final useDhamar = !locationKnown && !criteria.hasMapArea &&
      !criteria.values.containsKey('governorate') && !criteria.values.containsKey('governorate_code');
    final dhamar = useDhamar ? ref.watch(marketplaceDhamarPreviewProvider(query)) : null;
    final feed = ref.watch(marketplaceFeedProvider(query));
    final transientError = feed.hasError && isTransientApiFailure(feed.error!);
    final canShowSnapshot = !feed.hasValue && (feed.hasError ? transientError : feed.isLoading);
    final snapshot = canShowSnapshot ? ref.watch(marketplaceInitialSnapshotProvider(query)).valueOrNull : null;
    final recent = ref.watch(recentPropertiesProvider).asData?.value;
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
    final data = feed.hasError && !transientError ? null : feed.valueOrNull ?? snapshot;
    return Scaffold(backgroundColor: background,
      appBar: AppBar(backgroundColor: background, elevation: 0, automaticallyImplyLeading: false,
        toolbarHeight: (58 + (MediaQuery.textScalerOf(context).scale(15) - 15) * 2).clamp(58, 112).toDouble(),
        titleSpacing: 18, title: Row(children: [
          const AqerBrandMark(size: 32), const SizedBox(width: 8),
          Flexible(child: Semantics(button: true, label: 'تغيير المنطقة', child: TextButton.icon(
            key: const ValueKey('home-location'), onPressed: _chooseLocation,
            style: TextButton.styleFrom(foregroundColor: theme.colorScheme.primary),
            icon: _locationBusy ? const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : EbrokerImage('location', size: 17, color: theme.colorScheme.primary),
            label: Text(location.needsConfirmation ? location.label : (data?.label ?? location.label), maxLines: 1, overflow: TextOverflow.ellipsis)))),
          Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('عقار اليمن', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700)),
          ])),
        ]), actions: [IconButton(tooltip: 'الإشعارات', onPressed: () => context.push('/notifications'),
          icon: PlatformNotificationUnreadBadge(
            child: EbrokerImage('notification', size: 21, color: theme.colorScheme.onSurface)))]),
      body: SmartSearchAssistantLayer(
        showHint: false,
        onOpenMap: _openMap,
        onPressed: () => context.push('/smart-search'),
        child: RefreshIndicator(onRefresh: () async {
        ref.read(marketplaceRepositoryProvider).invalidateFeed(query);
        ref.invalidate(marketplaceFeedProvider(query));
        if (useDhamar) ref.invalidate(marketplaceDhamarPreviewProvider(query));
        try { await Future.wait([
          ref.read(marketplaceFeedProvider(query).future),
          if (useDhamar) ref.read(marketplaceDhamarPreviewProvider(query).future),
        ]); } catch (_) { /* Inline retry retains only this query. */ }
      }, child: CustomScrollView(key: const PageStorageKey('marketplace-home'), controller: _feedScroll,
        cacheExtent: ConditionalImagePrefetch.enabled ? ConditionalImagePrefetch.extent : 0,
        physics: const AlwaysScrollableScrollPhysics(), slivers: [
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(18, 8, 18, 0), child: Theme(data: theme, child: Column(children: [
          TextField(
            key: const ValueKey('home-search'),
            readOnly: true,
            style: TextStyle(color: theme.colorScheme.onSurface),
            onTap: _openSearch,
            decoration: InputDecoration(
              hintText: 'ابحث عن عقار أو منطقة…',
              filled: true,
              fillColor: theme.colorScheme.surface,
              hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              suffixIcon: Icon(Icons.search, color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 8),
          HomeAiSearchEntry(wide: true, professional: professional),
        ])))),
        SliverToBoxAdapter(child: EbrokerTitleHeader(title: 'ماذا تبحث عنه؟', compact: true, onSeeAll: _openMap)),
              SliverToBoxAdapter(child: SizedBox(height: 48 + (MediaQuery.textScalerOf(context).scale(13) - 13) * 2,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 18), children: [
                  for (final category in const [('شقق', 'apartment'), ('منازل', 'house'), ('فلل', 'villa'),
                    ('عمائر', 'building'), ('أراضٍ', 'land'), ('محلات', 'shop'), ('مكاتب', 'office'), ('مزارع', 'farm')])
                    Padding(padding: const EdgeInsetsDirectional.only(end: 6), child: EbrokerCategoryCard(label: category.$1,
                      icon: ebrokerCategoryIcon(category.$2), selected: selectedTypes.contains(category.$2),
                      onTap: () => ref.read(marketplaceSearchControllerProvider.notifier).chooseType(category.$2))),
                ]))),
        if (data != null && (feed.isLoading || transientError))
          SliverToBoxAdapter(child: AppRefreshStatus(loading: feed.isLoading,
            error: feed.hasError ? friendlyApiError(feed.error!) : null,
            onRetry: () => ref.invalidate(marketplaceFeedProvider(query)))),
        if (snapshot != null) _feedSliver(snapshot, dhamar)
        else feed.when(skipLoadingOnReload: true, skipError: feed.hasValue && transientError,
          loading: () => const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(18),
            child: AppSkeleton(key: ValueKey('home-feed-loading'), height: 270, radius: 8))),
          error: (error, _) => SliverToBoxAdapter(child: AppErrorState(message: friendlyApiError(error),
            onRetry: () => ref.invalidate(marketplaceFeedProvider(query)))), data: (data) => _feedSliver(data, dhamar)),
        if (dhamar != null) SliverToBoxAdapter(child: dhamar.when(
          loading: () => const AppRefreshStatus(loading: true),
          error: (error, _) => AppRefreshStatus(error: friendlyApiError(error),
            onRetry: () => ref.invalidate(marketplaceDhamarPreviewProvider(query))),
          data: (rows) => rows.isEmpty ? const SizedBox.shrink() : Column(children: [
            EbrokerTitleHeader(title: 'بالقرب منك', compact: true, onSeeAll: () =>
              _section('regional', dhamarPreviewGovernorate.name, filters: dhamarPreviewFilters(criteria))),
            _propertyRail('dhamar', rows),
          ]),
        )),
         if (recent != null && recent.isNotEmpty)
           SliverToBoxAdapter(child: Column(children: [
             EbrokerTitleHeader(title: 'شوهد مؤخرًا', compact: true, onSeeAll: () => context.push('/recent')),
             _propertyRail('recent', recent.take(6)),
           ])),
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ]))),
    );
  }

  Widget _propertyRail(String section, Iterable<PropertySummary> rows) {
    final width = (MediaQuery.sizeOf(context).width - 78).clamp(220, 366).toDouble();
    // Keep intrinsic height for large Arabic text. ViewportMedia gates the images.
    return SingleChildScrollView(
      key: PageStorageKey('home-properties-$section'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final row in rows)
          Padding(padding: const EdgeInsetsDirectional.only(end: 12),
            child: SizedBox(width: width, child: PropertySummaryCard(
              key: ValueKey('home-property-${row.id}'), property: row,
              imageFirst: true, preview: true, compactPreview: true))),
      ]),
    );
  }

  Widget _feedSliver(MarketplaceFeed data, AsyncValue<List<PropertySummary>>? dhamar) {
    final entries = <WidgetBuilder>[];
    if (data.brokers.isNotEmpty) {
      entries.add((context) {
        final viewportWidth = MediaQuery.sizeOf(context).width;
        final largeText = MediaQuery.textScalerOf(context).scale(12) > 18;
        final width = viewportWidth * (largeText ? .88 : .54);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EbrokerTitleHeader(title: 'أفضل الدلالين في ${data.label}', compact: true,
              onSeeAll: () => context.push('/brokers')),
            SingleChildScrollView(
              key: const ValueKey('home-broker-directory'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final broker in data.brokers)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 10),
                    child: _HomeBrokerCard(
                      key: ValueKey('home-broker-${broker.id}'),
                      width: width,
                      profile: broker,
                    ),
                  ),
              ]),
            ),
          ],
        );
      });
    }
    final sections = [
      if (data.sectionOrder.contains('latest')) 'latest',
      ...data.sectionOrder.where((key) => key == 'spotlight' || (key == 'sale' && dhamar == null)),
    ];
    for (final key in sections) {
      final rows = data.sections[key] ?? const <PropertySummary>[];
      if (rows.isEmpty) continue;
      final title = switch (key) { 'spotlight' => 'عقارات تستحق نظرة',
        'sale' => 'بالقرب منك', _ => 'أحدث العقارات' };
      entries.add((_) => EbrokerTitleHeader(title: title, compact: true, onSeeAll: () => _section(key, data.governorate)));
      entries.add((_) => _propertyRail(key, rows));
    }
    if (sections.every((key) => data.sections[key]?.isNotEmpty != true) &&
        (dhamar == null || dhamar.asData?.value.isEmpty == true)) {
      entries.add((_) => AppEmptyState(title: 'لا توجد عقارات في هذه المنطقة الآن', message: 'استكشف الخريطة أو اختر منطقة أخرى.',
        actionLabel: 'تغيير المنطقة', onAction: _chooseLocation));
    }
    return SliverList(delegate: SliverChildBuilderDelegate((context, index) => entries[index](context), childCount: entries.length));
  }
}

class _HomeBrokerCard extends StatelessWidget {
  const _HomeBrokerCard({required this.width, required this.profile, super.key});

  final double width;
  final BrokerProfile profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final photoUrl = profile.photoUrl;
    final fallback = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(child: EbrokerImage('defaultProfileIcon', size: 36, color: scheme.primary)),
    );
    final rating = arabicDigits(profile.rating.toStringAsFixed(1)).replaceAll('.', '٫');
    final ratingCount = profile.ratingCount;
    final ratingLabel = switch (ratingCount) {
      0 => 'بلا تقييمات',
      1 => 'تقييم واحد',
      2 => 'تقييمان',
      <= 10 => '${arabicDigits('$ratingCount')} تقييمات',
      _ => '${arabicDigits('$ratingCount')} تقييمًا',
    };
    final labelStyle = theme.textTheme.bodySmall?.copyWith(fontSize: 8.5, height: 1.2);
    final valueStyle = theme.textTheme.bodySmall?.copyWith(fontSize: 13, fontWeight: FontWeight.w700);
    Widget metric(String value, String label, {Widget? icon}) => Expanded(child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (icon != null) icon,
          Flexible(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: valueStyle)),
        ]),
        Text(label, textAlign: TextAlign.center, style: labelStyle),
      ]),
    ));
    Widget separator() => Container(width: 1, height: 22, color: scheme.outlineVariant);

    return SizedBox(
      width: width,
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/advertisers/${profile.id}'),
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: 1.75,
                  child: Stack(fit: StackFit.expand, children: [
                    if (photoUrl == null || photoUrl.isEmpty) fallback
                    else ViewportMedia(
                      placeholder: fallback,
                      builder: (_) => Image.network(photoUrl, fit: BoxFit.cover,
                        cacheWidth: 640, excludeFromSemantics: true,
                        errorBuilder: (_, __, ___) => fallback),
                    ),
                    const Align(alignment: Alignment.bottomCenter, child: SizedBox(
                      height: 22, width: double.infinity,
                      child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0x77007C86)],
                      ))),
                    )),
                    PositionedDirectional(
                      top: 5,
                      start: 5,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.group_outlined, size: 12, color: scheme.onPrimaryContainer),
                            const SizedBox(width: 3),
                            Text(profile.typeLabel, style: labelStyle?.copyWith(color: scheme.onPrimaryContainer)),
                          ]),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(3, 4, 1, 4),
                child: Row(children: [
                  Expanded(child: Row(children: [
                    Flexible(child: Text(profile.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 11, fontWeight: FontWeight.w700))),
                    if (profile.verified) ...[
                      const SizedBox(width: 3),
                      const Icon(Icons.verified_rounded, color: Color(0xFF198CE0), size: 14,
                        semanticLabel: 'موثّق'),
                    ],
                  ])),
                  Icon(Icons.chevron_left_rounded, textDirection: TextDirection.ltr,
                    color: scheme.primary, size: 18),
                ]),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: .55),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    metric(ratingCount == 0 ? '—' : rating, ratingLabel,
                      icon: Icon(Icons.star_rounded, size: 12, color: scheme.primary)),
                    separator(),
                    metric(arabicDigits('${profile.completedDeals}'), 'صفقات مؤكدة'),
                    separator(),
                    metric(arabicDigits('${profile.activeListings}'), 'عقارات نشطة'),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class MarketplaceLocationSheet extends ConsumerWidget {
  const MarketplaceLocationSheet({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Directionality(textDirection: TextDirection.rtl, child: SizedBox(
    height: MediaQuery.sizeOf(context).height * .60, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.fromLTRB(18, 18, 18, 6), child: Text('أين تبحث؟', style: Theme.of(context).textTheme.titleLarge)),
      ListTile(leading: const EbrokerIcon(Icons.near_me_outlined, size: 22), title: const Text('استخدم موقعي'),
        onTap: () => Navigator.of(context).pop('device')),
      const Divider(height: 1),
      Expanded(child: ref.watch(homeLocationsProvider).when(loading: () => const AppLoadingState(),
        error: (error, _) => AppErrorState(message: friendlyApiError(error), onRetry: () => ref.invalidate(homeLocationsProvider)),
        data: (rows) => ListView(children: [for (final row in rows) ListTile(
          key: ValueKey('home-governorate-${row.governorateCode ?? row.governorate}'),
          leading: const EbrokerIcon(Icons.location_on_outlined, size: 22), title: Text(row.label), onTap: () => Navigator.of(context).pop(row))]))),
    ])));
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/ebroker_design.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/ebroker_property_card.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../../broker/domain/broker_models.dart';
import '../../map/presentation/map_screen.dart';
import '../../properties/domain/property_details.dart';
import '../../properties/presentation/property_details_screen.dart';
import '../data/marketplace_repository.dart';
import 'home_ai_search_entry.dart';

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
  void initState() { super.initState(); Future.microtask(() => _tryDeviceLocation()); }

  Future<void> _tryDeviceLocation({bool prompt = false}) async {
    if (!prompt && ref.read(homeLocationAttemptedProvider)) return;
    ref.read(homeLocationAttemptedProvider.notifier).state = true;
    if (!prompt && ref.read(homeLocationProvider).manual) return;
    if (prompt) setState(() => _locationBusy = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) throw StateError('Location service unavailable.');
      var permission = await Geolocator.checkPermission();
      if (prompt && permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) throw StateError('Location permission unavailable.');
      final before = ref.read(homeLocationProvider);
      final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 8)));
      if (!mounted || !identical(before, ref.read(homeLocationProvider))) return;
      ref.read(homeLocationProvider.notifier).state = HomeLocation(latitude: position.latitude, longitude: position.longitude, label: 'موقعي', device: true);
    } catch (_) {
      if (prompt && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّر تحديد موقعك. يمكنك اختيار المنطقة يدويًا.')));
    } finally { if (mounted && prompt) setState(() => _locationBusy = false); }
  }

  Future<void> _chooseLocation() async {
    final choice = await AppBottomSheet.show<Object>(context, builder: (_) => const _HomeLocationSheet());
    if (!mounted) return;
    if (choice is HomeLocation) { ref.read(homeLocationProvider.notifier).state = choice; }
    else if (choice == 'device') { await _tryDeviceLocation(prompt: true); }
  }

  void _openMap() {
    final location = ref.read(homeLocationProvider);
    context.push(Uri(path: '/property-market', queryParameters: {'lat': '${location.latitude}', 'lon': '${location.longitude}', if (_type != null) 'type': _type!}).toString());
  }
  void _section(String section, String? governorate) => context.push(Uri(path: '/marketplace-section',
    queryParameters: {'section': section, if (governorate != null) 'governorate': governorate, if (_type != null) 'type': _type!}).toString());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), location = ref.watch(homeLocationProvider);
    final active = ModalRoute.of(context)?.isCurrent ?? true;
    final feed = active ? ref.watch(marketplaceFeedProvider(_query))
      : const AsyncLoading<MarketplaceFeed>();
    final data = feed.asData?.value;
    final label = data?.label ?? location.label;
    return Scaffold(backgroundColor: EbrokerDesign.page,
      appBar: AppBar(toolbarHeight: (58 + (MediaQuery.textScalerOf(context).scale(15) - 15) * 2).clamp(58, 112).toDouble(),
        backgroundColor: EbrokerDesign.page, elevation: 0, automaticallyImplyLeading: false, titleSpacing: 18,
        title: Semantics(button: true, label: 'تغيير المنطقة', child: InkWell(onTap: _chooseLocation, child: Row(children: [
          EbrokerImage('home_active', size: 24, color: theme.colorScheme.primary), const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const EbrokerText('الموقع', size: 11),
            Row(children: [Flexible(child: EbrokerText(label, size: 15, weight: FontWeight.w600, maxLines: 1)), const SizedBox(width: 4),
              if (_locationBusy) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              else const EbrokerImage('down_arrow', size: 15, color: EbrokerDesign.textLight)]),
          ])),
        ]))), actions: [Padding(padding: const EdgeInsetsDirectional.only(end: 12), child: IconButton(
          tooltip: 'الإشعارات', onPressed: () => context.push('/notifications'), icon: const EbrokerImage('notification', size: 21)))]),
      body: RefreshIndicator(onRefresh: () async { try { ref.invalidate(marketplaceFeedProvider(_query)); await ref.read(marketplaceFeedProvider(_query).future); } catch (_) {} },
        child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(18, 8, 18, 0), child: Row(children: [
            Expanded(child: Semantics(button: true, label: 'البحث عن عقار', child: GestureDetector(key: const ValueKey('home-search'), onTap: _openMap,
              child: AbsorbPointer(child: TextField(readOnly: true, decoration: InputDecoration(hintText: 'ابحث عن عقار أو منطقة…',
                prefixIcon: Padding(padding: const EdgeInsets.all(10), child: EbrokerImage('search', color: theme.colorScheme.primary)))))))),
            const SizedBox(width: 8), IconButton.filledTonal(key: const ValueKey('home-map'), tooltip: 'الخريطة', onPressed: _openMap,
              icon: EbrokerImage('propertymap', size: 22, color: theme.colorScheme.primary)),
          ]))),
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
            child: HomeAiSearchEntry(location: data?.governorate ?? location.governorate ?? 'صنعاء', type: _type))),
          if (widget.showAdvertiserActions) SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: Wrap(spacing: 10, children: [
            TextButton.icon(onPressed: () => context.push('/broker/workspace'), icon: const EbrokerIcon(Icons.work_outline, size: 18), label: const Text('إدارة عملي')),
            TextButton.icon(onPressed: () => context.push('/add-property'), icon: const EbrokerIcon(Icons.add, size: 18), label: const Text('إضافة عقار')),
          ]))),
          SliverToBoxAdapter(child: EbrokerTitleHeader(title: 'ماذا تبحث عنه؟', onSeeAll: _openMap)),
          SliverToBoxAdapter(child: SizedBox(height: 48 + (MediaQuery.textScalerOf(context).scale(13) - 13) * 2, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 18), children: [
            for (final category in const [('الكل', null), ('شقق', 'apartment'), ('منازل', 'house'), ('فلل', 'villa'), ('عمائر', 'building'), ('أراضٍ', 'land'), ('محلات', 'shop'), ('مكاتب', 'office'), ('مزارع', 'farm')])
              Padding(padding: const EdgeInsetsDirectional.only(end: 6), child: EbrokerCategoryCard(label: category.$1, icon: ebrokerCategoryIcon(category.$2),
                selected: _type == category.$2, onTap: () => setState(() => _type = category.$2))),
          ]))),
          if (feed.hasError && feed.hasValue) SliverToBoxAdapter(child: Padding(
            key: const ValueKey('home-refresh-error'), padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('تعذّر تحديث العقارات الآن. نعرض آخر تحميل ناجح.'),
              TextButton.icon(onPressed: () => ref.invalidate(marketplaceFeedProvider(_query)),
                icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
            ]))),
          feed.when(
            skipError: feed.hasValue,
            loading: () => const SliverToBoxAdapter(child: _HomeFeedLoading()),
            error: (error, _) => SliverToBoxAdapter(child: AppErrorState(message: friendlyApiError(error), onRetry: () => ref.invalidate(marketplaceFeedProvider(_query)))),
            data: (data) => SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (data.brokers.isNotEmpty) ...[
                EbrokerTitleHeader(title: 'أفضل الدلالين في ${data.label}', onSeeAll: () => context.push('/brokers')),
                SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 18), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final broker in data.brokers) Padding(padding: const EdgeInsetsDirectional.only(end: 10), child: _HomeBrokerCard(profile: broker)),
                ])),
              ],
              for (final section in const [('spotlight', 'عقارات تستحق نظرة'), ('latest', 'أحدث العقارات'), ('sale', 'تملّك في منطقتك'), ('rent', 'مساحة تناسب حياتك')])
                if ((data.sections[section.$1] ?? const []).isNotEmpty) ...[
                  EbrokerTitleHeader(title: section.$2, onSeeAll: () => _section(section.$1, data.governorate)),
                  if (section.$1 == 'latest') Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: Column(children: [
                    for (final row in data.sections[section.$1]!.take(3)) Padding(padding: const EdgeInsets.only(bottom: 12), child: _property(row, false)),
                  ]))
                  else SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 18), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final row in data.sections[section.$1]!) Padding(padding: const EdgeInsetsDirectional.only(end: 12),
                      child: SizedBox(width: (MediaQuery.sizeOf(context).width - 64).clamp(250, 380).toDouble(), child: _property(row, true))),
                  ])),
                ],
              if (data.sections.values.every((rows) => rows.isEmpty)) AppEmptyState(title: 'لا توجد عقارات في هذه المنطقة الآن', message: 'استكشف الخريطة أو اختر منطقة أخرى.',
                actionLabel: 'تغيير المنطقة', onAction: _chooseLocation),
            ])),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ])),
    );
  }

  Widget _property(PropertySummary row, bool large) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    EbrokerPropertyHorizontalCard(key: ValueKey('home-property-${row.id}'), title: row.title, price: row.price.toStringAsFixed(0), currency: row.currency,
      imageFirst: large, imageUrl: row.mainImage, imageUrls: row.imageUrls, isSpotlight: row.isSpotlight,
      location: row.address, categoryLabel: ebrokerPropertyTypeLabel(row.type), purposeLabel: row.purpose == 'rent' ? 'للإيجار' : 'للبيع',
      onTap: () => context.push('/properties/${row.id}')),
    if (row.monthlyRent != null) Padding(padding: const EdgeInsets.only(top: 5), child: Text('الإيجار الشهري: ${row.monthlyRent!.toStringAsFixed(0)} ${row.currency}', style: Theme.of(context).textTheme.bodySmall)),
    if (row.priceDisplayNote != null) Text(row.priceDisplayNote!, style: Theme.of(context).textTheme.bodySmall),
  ]);
}

class _HomeFeedLoading extends StatefulWidget {
  const _HomeFeedLoading();
  @override
  State<_HomeFeedLoading> createState() => _HomeFeedLoadingState();
}

class _HomeFeedLoadingState extends State<_HomeFeedLoading> {
  Timer? _slowTimer;
  bool _slow = false;
  @override
  void initState() {
    super.initState();
    _slowTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _slow = true);
    });
  }
  @override
  void dispose() { _slowTimer?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(18),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Semantics(liveRegion: true, child: Text(_slow
        ? 'الاتصال يستغرق وقتًا أطول. نحاول تحميل العقارات تلقائيًا…'
        : 'جارٍ تحميل العقارات…', key: const ValueKey('home-loading-message'))),
      const SizedBox(height: 12),
      const AppSkeleton(key: ValueKey('home-feed-loading'), height: 270, radius: 12),
    ]));
}

class _HomeBrokerCard extends StatelessWidget {
  const _HomeBrokerCard({required this.profile});
  final BrokerProfile profile;
  @override
  Widget build(BuildContext context) => SizedBox(width: 238, child: AppSurface(onTap: () => context.push('/advertisers/${profile.id}'), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [ClipOval(child: profile.photoUrl == null ? const EbrokerImage('defaultProfileIcon', size: 54)
      : Image.network(profile.photoUrl!, width: 54, height: 54, fit: BoxFit.cover, cacheWidth: 180,
        errorBuilder: (_, __, ___) => const EbrokerImage('defaultProfileIcon', size: 54))), const SizedBox(width: 10),
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

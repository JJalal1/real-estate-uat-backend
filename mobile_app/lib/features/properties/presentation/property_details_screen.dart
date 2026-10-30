import 'adaptive_property_photo.dart';
import '../../../core/network/adaptive_image_policy.dart';
import '../domain/rental_condition_summary.dart';
import 'property_summary_card.dart';
import 'package:flutter/material.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../../../core/widgets/ebroker_screen_sections.dart';
import '../../../core/theme/ebroker_design.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/platform/contact_actions.dart';
import '../../../core/platform/platform_share.dart';
import '../../broker/data/broker_repository.dart';
import '../../community/data/community_repository.dart';
import '../../community/presentation/community_dialogs.dart';
import 'property_compare_actions.dart';
import 'property_location_preview.dart';
import 'property_fullscreen_gallery.dart';
import '../../../core/local/listing_viewer_key_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../../../router/app_deep_links.dart';
import '../../account/data/auth_controller.dart';
import '../../account/data/auth_return_intent.dart';
import '../../community/presentation/listing_community_screen.dart';
import '../../messages/data/message_repository.dart';
import '../data/favorites_repository.dart';
import '../data/recent_properties_store.dart';
import '../data/property_repository.dart';
import '../domain/property_details.dart';
import '../domain/property_field_options.dart';
import '../domain/property_schema.dart';
import 'add_property_wizard_screen.dart';
import 'my_listings_screen.dart';
import 'property_market_context_card.dart';
import 'property_sai_public_line.dart';

final propertyDetailsProvider =
    FutureProvider.autoDispose.family<PropertyDetails, int>((ref, propertyId) {
  ref.watch(propertyDataRevisionProvider);
  ref.watch(authControllerProvider.select((state) => state.asData?.value?.id));
  return ref.watch(propertyRepositoryProvider).details(propertyId);
});

class PropertyDetailsScreen extends ConsumerStatefulWidget {
  const PropertyDetailsScreen({required this.propertyId, this.scrollController, this.inSheet = false, this.initialSummary, super.key});

  final int propertyId;
  final ScrollController? scrollController;
  final bool inSheet;
  final PropertySummary? initialSummary;

  @override
  ConsumerState<PropertyDetailsScreen> createState() => _PropertyDetailsScreenState();
}

class _PropertyDetailsScreenState extends ConsumerState<PropertyDetailsScreen> {
  int _imageIndex = 0;
  bool _startingConversation = false;
  bool _changingFavorite = false;
  bool _consumingPendingFavorite = false;
  bool _viewRecorded = false;
  String? _recentRecordedScope;
  bool _calling = false, _reporting = false;
  String? _loadedScope;

  @override
  void didUpdateWidget(covariant PropertyDetailsScreen old) {
    super.didUpdateWidget(old);
    if (old.propertyId != widget.propertyId) {
      _viewRecorded = false;
      _recentRecordedScope = null;
      _imageIndex = 0;
    }
  }

  Future<void> _recordView() async {
    try {
      final repo = ref.read(propertyRepositoryProvider);
      final key = await ref.read(listingViewerKeyProvider.future);
      if (mounted) await repo.recordView(widget.propertyId, key);
    } catch (_) { /* A failed analytics request never blocks public browsing. */ }
  }

  @override
  Widget build(BuildContext context) {
    final details = ref.watch(propertyDetailsProvider(widget.propertyId));
    final user = ref.watch(authControllerProvider).asData?.value;
    final scope = '${user?.id}:${widget.propertyId}';
    if (details.asData != null) _loadedScope = scope;
    final retain = _loadedScope == scope && details.hasValue && details.hasError && isTransientApiFailure(details.error!);
    final pendingFavorite = ref.watch(pendingFavoriteAfterAuthProvider);
    final favoriteIds = user == null
        ? const <int>{}
        : ref.watch(favoritePropertyIdsProvider).maybeWhen(
              data: (value) => value,
              orElse: () => const <int>{},
            );
    final loaded = details.asData?.value;
    if (!_viewRecorded && loaded != null && !loaded.isOwner && loaded.status == 'published') {
      _viewRecorded = true;
      Future<void>.microtask(_recordView);
    }

    final recentStore = ref.watch(recentPropertiesStoreProvider);
    if (recentStore.enabled && _recentRecordedScope != scope && loaded != null && loaded.status == 'published') {
      _recentRecordedScope = scope;
      Future<void>.microtask(() async {
        try {
          await recentStore.record(loaded.toSummary());
          if (mounted) ref.invalidate(recentPropertiesProvider);
        } catch (_) {
          // Recent local history is best-effort: missing storage, denied IO,
          // or a mock platform must not crash property details.
        }
      });
    }

    if (user != null &&
        user.isActive &&
        pendingFavorite == widget.propertyId &&
        !_consumingPendingFavorite) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _consumePendingFavorite();
      });
    }

    final showPrimaryActions = loaded != null &&
        loaded.status == 'published' &&
        !loaded.isOwner && loaded.availabilityStatus == 'available' && !loaded.financialHold;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppAppBar(
          title: 'تفاصيل العقار',
          actions: [
            if (loaded != null && loaded.status == 'published' && !loaded.isOwner)
              AppIconButton(
                icon: favoriteIds.contains(loaded.id)
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                tooltip: favoriteIds.contains(loaded.id)
                    ? 'إزالة من المفضلة'
                    : 'حفظ في المفضلة',
                onPressed: _changingFavorite || _consumingPendingFavorite
                    ? null
                    : () => _toggleFavorite(
                          loaded.id,
                          currentlyFavorite: favoriteIds.contains(loaded.id),
                        ),
              ),
            AppIconButton(
              icon: Icons.ios_share_outlined,
              tooltip: 'مشاركة العقار',
              onPressed: loaded?.status == 'published' && loaded?.availabilityStatus == 'available'
                  ? () => _shareProperty(loaded!) : null,
            ),
          ],
        ),
        body: details.when(
          skipLoadingOnReload: false,
          skipError: retain,
          loading: () => _PropertyDetailsSkeleton(scrollController: widget.scrollController,
            summary: widget.initialSummary?.id == widget.propertyId && widget.initialSummary?.status == 'published' ? widget.initialSummary : null),
          error: (error, _) => AppErrorState(
            message: friendlyApiError(error),
            onRetry: () => ref.invalidate(propertyDetailsProvider(widget.propertyId)),
          ),
          data: (property) => Column(children: [
            if (details.isLoading || retain) AppRefreshStatus(loading: details.isLoading,
              error: retain ? friendlyApiError(details.error!) : null,
              onRetry: () => ref.invalidate(propertyDetailsProvider(widget.propertyId))),
            Expanded(child: _buildContent(property, favoriteIds)),
          ]),
        ),
        bottomNavigationBar: showPrimaryActions
            ? _PropertyPrimaryActions(
                loading: _startingConversation, calling: _calling, onCall: _calling ? null : () => _callAdvertiser(loaded),
                onMessage: _startingConversation
                    ? null
                    : () => _startConversation(loaded),
              )
            : null,
      ),
    );
  }

  Widget _buildContent(PropertyDetails property, Set<int> favoriteIds) {
    final published = property.status == 'published';
    final schemaContext={'type':property.type,'purpose':property.purpose,'unit_occupies_entire_floor':property.unitOccupiesEntireFloor};
    bool applies(String key)=>DynamicPropertySchema.applies(key,schemaContext);
    final residential=applies('bedrooms'),unit=applies('floor_number');
    final facts = <AppPropertyFact>[
      if (applies('area_value') && property.areaValue != null)
        AppPropertyFact(
          icon: Icons.square_foot,
          label:
              '${formatPropertyAreaValue(property.areaValue!)} ${propertyAreaUnitLabel(property.areaUnit)}',
        )
      else if (applies('area_value') && property.areaM2 != null)
        AppPropertyFact(icon: Icons.square_foot, label: '${property.areaM2} م²'),
      if (residential && property.bedrooms != null)
        AppPropertyFact(icon: Icons.bed_outlined, label: '${property.bedrooms} غرف'),
      if (residential && property.bathrooms != null)
        AppPropertyFact(icon: Icons.bathtub_outlined, label: '${property.bathrooms} حمام'),
      if (property.hasParking != null && applies('has_parking')) AppPropertyFact(icon: Icons.local_parking_outlined, label: property.hasParking! ? 'موقف سيارة' : 'بدون موقف'),
      if (unit && property.floorNumber?.isNotEmpty == true) AppPropertyFact(icon: Icons.layers_outlined, label: DynamicPropertySchema.floorLabel(property.floorNumber)),
      if (property.unitOccupiesEntireFloor) const AppPropertyFact(icon: Icons.apartment, label: 'الوحدة تشغل الدور كاملًا'),
      if (applies('floors_count') && property.floorsCount != null) AppPropertyFact(icon: Icons.layers_outlined, label: '${property.floorsCount} أدوار'),
      if (applies('units_per_floor') && property.unitsPerFloor.isNotEmpty) AppPropertyFact(icon: Icons.apartment_outlined, label: 'الوحدات حسب الأدوار: ${property.unitsPerFloor.join('، ')}'),
      if (applies('shop_openings') && property.shopOpenings != null) AppPropertyFact(icon: Icons.storefront_outlined, label: '${property.shopOpenings} فتحات'),
      if (property.tenureType != null && applies('tenure_type'))
        AppPropertyFact(
          icon: Icons.account_balance_outlined,
          label: property.tenureType == 'waqf' ? 'وقف' : 'حر',
        ),
      if (property.buildingFacade != null && applies('building_facade'))
        AppPropertyFact(
          icon: Icons.explore_outlined,
          label: propertyFacadeLabel(property.buildingFacade),
        ),
    ];

    return RefreshIndicator(
      notificationPredicate: (notification) => !widget.inSheet && notification.depth == 0,
      onRefresh: () async {
        ref.invalidate(propertyDetailsProvider(widget.propertyId));
        ref.invalidate(propertySaiPublicProvider(widget.propertyId));
        ref.invalidate(propertyMarketContextProvider(widget.propertyId));
        if (ref.read(authControllerProvider).asData?.value != null) {
          ref.invalidate(favoritePropertyIdsProvider);
        }
        try { await ref.read(propertyDetailsProvider(widget.propertyId).future); } catch (_) { /* The page renders failure and retry. */ }
      },
      child: ListView(
        key: ValueKey('property-details-${widget.propertyId}'),
        controller: widget.scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsetsDirectional.fromSTEB(
          AppLayout.compactPageGutter,
          AppSpacing.s12,
          AppLayout.compactPageGutter,
          published && !property.isOwner ? 124.0 : AppSpacing.s40,
        ),
        children: [
          if (widget.inSheet) Semantics(label: 'اسحب لتوسيع الإعلان أو تصغيره',
            child: Listener(key: const ValueKey('property-details-handle'), behavior: HitTestBehavior.opaque,
              child: SizedBox(height: 24, child: Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant, borderRadius: BorderRadius.circular(4))))))),
          _Gallery(
            images: property.images,
            privateImages:property.status!='published',
            index: _imageIndex,
            onChanged: (index) => setState(() => _imageIndex = index),
          ),
          EbrokerPropertyHeading(
            category: _typeLabel(property.type), title: property.title,
            purpose: _purposeLabel(property.purpose),
            price: AppPropertyPrice(price: _formatPrice(property.purpose == 'rent' ? property.monthlyRent ?? property.price : property.price), currency: property.currency,
              suffix: property.purpose == 'rent' && property.monthlyRent != null ? 'شهريًا' : null),
            trailing: property.isOwner ? PopupMenuButton<String>(
              tooltip: 'إدارة الإعلان',
              onSelected: (action) => _ownerAction(action, property),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('تعديل الإعلان')),
                PopupMenuItem(value: 'mine', child: Text('إعلاناتي')),
              ],
            ) : null,
          ),
          PropertySaiPublicLine(propertyId: property.id),
          if (!published) ...[
            const SizedBox(height: AppSpacing.s12),
            AppStatusBadge(label: _statusLabel(property.status),
              tone: property.status == 'rejected' ? AppStatusTone.error : AppStatusTone.warning,
              icon: Icons.info_outline),
          ],
          if (!published && !property.isOwner) ...[
            const SizedBox(height: 16),
            const AppUnavailableState(),
          ],
          if (property.address?.isNotEmpty == true) Padding(padding: const EdgeInsets.only(top: 12), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.location_on_outlined, size: 20, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 6), Expanded(child: Text(property.address!)),
          ])),
          if (published) Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            PropertyCompareAction(propertyId: property.id, enabled: property.availabilityStatus == 'available'), const PropertyCompareTray(),
          ]),
          const SizedBox(height: AppSpacing.s24),
          EbrokerSectionPanel(title: 'حول العقار',
            child: Text(
              property.description ??
                  'لم يضف المعلن وصفاً تفصيلياً لهذا العقار بعد.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
          if (facts.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s24),
            EbrokerSectionPanel(title: 'مواصفات العقار',
              child: GridView.builder(shrinkWrap: true, padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(), itemCount: facts.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: MediaQuery.textScalerOf(context).scale(14) > 20 ? 1 : 2,
                  mainAxisSpacing: 16, crossAxisSpacing: 16,
                  mainAxisExtent: 39.rh(context) + (MediaQuery.sizeOf(context).width < 360 ? 18 : 0) + (MediaQuery.textScalerOf(context).scale(14) - 14) * 4.5),
                itemBuilder: (context, index) => Row(children: [
                  Container(width: 36.rw(context), height: 36.rh(context), padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(4), border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
                    child: EbrokerIcon(facts[index].icon, size: 24, color: Theme.of(context).colorScheme.onSurface)),
                  SizedBox(width: 10.rw(context)),
                  Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                      EbrokerText(_factLabel(facts[index].icon), size: 12, color: Theme.of(context).colorScheme.onSurfaceVariant, maxLines: 1),
                      EbrokerText(facts[index].label, weight: FontWeight.w500, maxLines: 2),
                    ])),
                ]))),
          ],
          if (published) ...[
            const SizedBox(height: AppSpacing.s24),
            const AppSectionHeader(
              title: 'السعر مقارنة بالسوق',
              subtitle:
                  'مقارنة استرشادية من عقارات منشورة ومعتمدة داخل المنصة فقط.',
            ),
            const SizedBox(height: AppSpacing.s8),
            PropertyMarketContextCard(
              propertyId: property.id,
              currency: property.currency,
            ),
          ],
          if (property.purpose == 'rent' && property.rentalConditions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s24),
            EbrokerSectionPanel(title: 'شروط الإيجار', child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final c in property.rentalConditions) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(rentalConditionSummary(c)))])),
          ],
          if (published && property.advertiser != null) ...[
            const SizedBox(height: AppSpacing.s24),
            const AppSectionHeader(title: 'المعلن'),
            const SizedBox(height: AppSpacing.s8),
            _AdvertiserCard(
              property: property,
              onCommunity: () => _openCommunity(property),
            ),
          ],
          if (property.images.length > 1) ...[
            const SizedBox(height: 24), EbrokerSectionPanel(title: 'معرض الصور', child: SizedBox(height: 96, child: ListView.separated(
              scrollDirection: Axis.horizontal, itemCount: property.images.length, separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) => Semantics(button: true, label: 'فتح صورة العقار ${index + 1}', child: InkWell(
                onTap: () => Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => PropertyFullscreenGallery(images: property.images, initialIndex: index, privateImages:property.status!='published'))),
                child: ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: 112, height: 96,
                  child: AdaptivePropertyPhoto(url: property.images[index].cardUrl,
                    authenticated:property.status!='published',use:PropertyImageUse.thumbnail))),
              )),
            ))),
          ],
          if (property.hasValidLocation) ...[
            const SizedBox(height: 24), EbrokerSectionPanel(title: 'الموقع والخريطة', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (property.address?.isNotEmpty == true) ...[Text(property.address!), const SizedBox(height: 12)],
              PropertyLocationPreview(latitude: property.latitude, longitude: property.longitude, onOpen: () => context.push(Uri(path: '/property-market',
                queryParameters: {'lat': '${property.latitude}', 'lon': '${property.longitude}'}).toString())),
            ])),
          ] else ...[
            const SizedBox(height: 24),
            const Text('موقع العقار غير محدد على الخريطة', key: ValueKey('property-location-unspecified')),
          ],
          if (published && !property.isOwner) Padding(padding: const EdgeInsets.only(top: 18), child: Align(alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(key: const ValueKey('property-report'), onPressed: _reporting ? null : () => _reportListing(property),
              icon: const Icon(Icons.flag_outlined, size: 20), label: Text(_reporting ? 'جارٍ إرسال البلاغ...' : 'الإبلاغ عن الإعلان')))),
          if (property.similar.isNotEmpty) ...[
            const SizedBox(height: 28), const AppSectionHeader(title: 'عقارات مشابهة'), const SizedBox(height: 12),
            if (MediaQuery.textScalerOf(context).scale(14) > 20)
              ...[for (final item in property.similar) Padding(padding: const EdgeInsets.only(bottom: 16), child: _similarCard(item, favoriteIds))]
            else SizedBox(height: 442, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: property.similar.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12), itemBuilder: (_, index) => SizedBox(width: 290, child: _similarCard(property.similar[index], favoriteIds)))),
          ],
        ],
      ),
    );
  }

  Widget _similarCard(PropertySummary item, Set<int> favoriteIds) => PropertySummaryCard(property: item, imageFirst: true,
    onTap: () { if (item.status == 'published') context.push('/properties/${item.id}'); });

  Future<bool> _requireContactAccount() async {
    if (ref.read(authControllerProvider).asData?.value == null) {
      setAuthReturnLocation(ref, '/properties/${widget.propertyId}'); await context.push('/auth');
      if (!mounted || ref.read(authControllerProvider).asData?.value == null) return false;
    }
    if (ref.read(authControllerProvider).asData?.value?.isActive != true) {
      setAuthReturnLocation(ref, '/properties/${widget.propertyId}'); await context.push('/verify-phone');
    }
    return mounted && ref.read(authControllerProvider).asData?.value?.isActive == true;
  }

  Future<void> _callAdvertiser(PropertyDetails property) async {
    if (_calling || !await _requireContactAccount() || !mounted) return;
    setState(() => _calling = true);
    try {
      var phone = await ref.read(propertyRepositoryProvider).contactPhone(property.id);
      if (!mounted) return;
      final other = ref.read(propertyRepositoryProvider).alternateContactPhone(property.id);
      if (other != null) {
        final selected = await AppBottomSheet.show<String>(context, builder: (sheet) => Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: const Text('رقم الاتصال'), subtitle: Text(phone, textDirection: TextDirection.ltr), leading: const Icon(Icons.phone_outlined), onTap: () => Navigator.pop(sheet, phone)),
          ListTile(title: const Text('رقم اتصال آخر'), subtitle: Text(other, textDirection: TextDirection.ltr), leading: const Icon(Icons.phone_outlined), onTap: () => Navigator.pop(sheet, other)),
        ]));
        if (!mounted || selected == null) return;
        phone = selected;
      }
      final opened = await ref.read(contactActionsProvider).openDialer(phone);
      if (!mounted || opened) return;
      await showDialog<void>(context: context, builder: (dialog) => AlertDialog(title: const Text('رقم الاتصال بالإعلان'),
        content: SelectableText(phone, textDirection: TextDirection.ltr), actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('إغلاق')),
          TextButton(onPressed: () async { await Clipboard.setData(ClipboardData(text: phone)); if (dialog.mounted) Navigator.pop(dialog); }, child: const Text('نسخ الرقم')),
        ]));
    } catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error)))); }
    finally { if (mounted) setState(() => _calling = false); }
  }

  Future<void> _reportListing(PropertyDetails property) async {
    if (_reporting || !await _requireContactAccount() || !mounted) return;
    final actor = ref.read(authControllerProvider).asData?.value?.id;
    final repository = ref.read(communityRepositoryProvider);
    final result = await showCommunityReportDialog(context, label: 'الإعلان');
    if (result == null || !mounted || ref.read(authControllerProvider).asData?.value?.id != actor) return;
    setState(() => _reporting = true);
    try {
      final receipt = await repository.report(targetType: 'listing', targetId: property.id, reason: result.reason, details: result.details);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(receipt.message),
          action: SnackBarAction(label: 'متابعة', onPressed: () => context.push('/support?case=${receipt.id}'))));
      }
    } catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error)))); }
    finally { if (mounted) setState(() => _reporting = false); }
  }

  Future<void> _toggleFavorite(
    int propertyId, {
    required bool currentlyFavorite,
  }) async {
    final user = ref.read(authControllerProvider).asData?.value;

    if (user == null) {
      ref.read(pendingFavoriteAfterAuthProvider.notifier).state = propertyId;
      setAuthReturnLocation(ref, '/properties/$propertyId');
      await context.push('/auth');
      if (!mounted) return;
      if (ref.read(authControllerProvider).asData?.value == null) {
        if (ref.read(pendingFavoriteAfterAuthProvider) == propertyId) {
          ref.read(pendingFavoriteAfterAuthProvider.notifier).state = null;
        }
        takeAuthReturnLocation(ref);
      }
      return;
    }

    if (!user.isActive) {
      ref.read(pendingFavoriteAfterAuthProvider.notifier).state = propertyId;
      setAuthReturnLocation(ref, '/properties/$propertyId');
      await context.push('/verify-phone');
      return;
    }
    if (_changingFavorite) return;

    setState(() => _changingFavorite = true);
    try {
      final repository = ref.read(favoritesRepositoryProvider);
      if (currentlyFavorite) {
        await repository.remove(propertyId);
      } else {
        await repository.add(propertyId);
      }
      ref.read(favoriteDataRevisionProvider.notifier).state++;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            currentlyFavorite
                ? 'تمت إزالة العقار من المفضلة.'
                : 'تم حفظ العقار في المفضلة.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyApiError(error))),
      );
    } finally {
      if (mounted) setState(() => _changingFavorite = false);
    }
  }

  Future<void> _consumePendingFavorite() async {
    if (_consumingPendingFavorite) return;
    final propertyId = ref.read(pendingFavoriteAfterAuthProvider);
    if (propertyId == null || propertyId != widget.propertyId) return;

    setState(() => _consumingPendingFavorite = true);
    ref.read(pendingFavoriteAfterAuthProvider.notifier).state = null;
    try {
      await ref.read(favoritesRepositoryProvider).add(propertyId);
      ref.read(favoriteDataRevisionProvider.notifier).state++;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ العقار في المفضلة.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyApiError(error))),
      );
    } finally {
      if (mounted) setState(() => _consumingPendingFavorite = false);
    }
  }

  Future<void> _shareProperty(PropertyDetails property) async {
    final link = propertyPublicShareLink(property.id).toString();
    final price = property.currency.trim().isEmpty
        ? property.price.toStringAsFixed(0)
        : '${property.price.toStringAsFixed(0)} ${property.currency}';
    final text = 'عقار: ${property.title}\nالسعر: $price\n$link';
    try {
      await PlatformShare.text(text: text, subject: property.title);
    } on PlatformException {
      await Clipboard.setData(ClipboardData(text: link));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذرت المشاركة المباشرة، فتم نسخ رابط العقار.')),
      );
    }
  }

  Future<void> _openCommunity(PropertyDetails property) async {
    final advertiser = property.advertiser;
    if (advertiser == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ListingCommunityScreen(
          propertyId: property.id,
          advertiserId: advertiser.id,
          advertiserName: advertiser.name,
        ),
      ),
    );
    if (mounted) ref.invalidate(propertyDetailsProvider(widget.propertyId));
  }

  Future<void> _startConversation(PropertyDetails property) async {
    final user = ref.read(authControllerProvider).asData?.value;
    if (user == null) {
      await context.push('/auth');
      return;
    }
    if (!user.isActive) {
      await context.push('/verify-phone');
      return;
    }
    if (_startingConversation) return;
    setState(() => _startingConversation = true);
    try {
      final thread =
          await ref.read(messageRepositoryProvider).startForProperty(property.id);
      ref.read(messageDataRevisionProvider.notifier).state++;
      if (mounted) await context.push('/messages/${thread.id}');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _startingConversation = false);
    }
  }

  Future<void> _ownerAction(String action, PropertyDetails property) async {
    if (action == 'mine') {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const MyListingsScreen()),
      );
      return;
    }
    if (action == 'edit') {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => AddPropertyWizardScreen(existingProperty: property),
        ),
      );
      if (mounted) {
        ref.invalidate(propertyDetailsProvider(widget.propertyId));
        ref.invalidate(propertyMarketContextProvider(widget.propertyId));
      }
    }
  }

}

class _Gallery extends StatelessWidget {
  const _Gallery({
    required this.images,
    required this.index,
    required this.onChanged,
    this.privateImages=false,
  });

  final List<PropertyImageItem> images;
  final int index;
  final ValueChanged<int> onChanged;
  final bool privateImages;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: SizedBox(
        height: 250.rs(context),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (images.isEmpty)
              const AppPropertyMedia(height: double.infinity)
            else
              PageView.builder(
                itemCount: images.length,
                onPageChanged: onChanged,
                itemBuilder: (context, imageIndex) => Semantics(
                  button: true,
                  label: 'فتح صورة العقار ${imageIndex + 1} من ${images.length}',
                  child: InkWell(
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => PropertyFullscreenGallery(
                          images: images,
                          initialIndex: imageIndex,
                          privateImages:privateImages,
                        ),
                      ),
                    ),
                    child: AdaptivePropertyPhoto(key:ValueKey(images[imageIndex].id),
                      url:images[imageIndex].galleryUrl,authenticated:privateImages,use:PropertyImageUse.detail),
                  ),
                ),
              ),
            if (images.length > 1)
              Positioned(bottom: 10, left: 0, right: 0,
                child: IgnorePointer(child: Row(mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(images.length, (i) => Container(width: 8, height: 8,
                    margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    decoration: BoxDecoration(shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: index == i ? .9 : .4))))))),
            if (images.isNotEmpty)
              PositionedDirectional(bottom: 12.rh(context), end: 16.rw(context),
                child: Semantics(button: true, label: 'تكبير الصور',
                  child: GestureDetector(onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(builder: (_) => PropertyFullscreenGallery(images: images, initialIndex: index,privateImages:privateImages))),
                    child: Container(padding: EdgeInsets.symmetric(horizontal: 8.rw(context), vertical: 4.rh(context)),
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(16), border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        EbrokerImage('gallery', size: 14, color: Theme.of(context).colorScheme.onSurface),
                        SizedBox(width: 4.rw(context)),
                        EbrokerText('${images.length}', size: 12, weight: FontWeight.w600),
                      ]))))),
          ],
        ),
      ),
    );
  }
}

class _AdvertiserCard extends ConsumerWidget {
  const _AdvertiserCard({
    required this.property,
    required this.onCommunity,
  });

  final PropertyDetails property;
  final VoidCallback onCommunity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final advertiser = property.advertiser!;
    final profile = ref.watch(brokerProfileProvider(advertiser.id)).asData?.value;
    final verified = advertiser.verificationStatus == 'approved';
    final signals = <_AdvertiserTrustSignal>[
      if (advertiser.verificationFlag('identity_reviewed'))
        const _AdvertiserTrustSignal(Icons.badge_outlined, 'هوية المعلن متحققة'),
      if (advertiser.verificationFlag('relationship_document_reviewed'))
        const _AdvertiserTrustSignal(Icons.home_work_outlined, 'علاقة المالك بالعقار متحققة'),
      if (advertiser.verificationFlag('professional_document_reviewed'))
        const _AdvertiserTrustSignal(Icons.workspace_premium_outlined, 'بيانات مهنية متحققة'),
      if (advertiser.verificationFlag('commercial_register_reviewed'))
        const _AdvertiserTrustSignal(Icons.business_outlined, 'السجل التجاري متحقق'),
      if (advertiser.verificationFlag('office_documents_reviewed'))
        const _AdvertiserTrustSignal(Icons.domain_verification_outlined, 'بيانات المكتب متحققة'),
      if (advertiser.verificationFlag('office_location_registered'))
        const _AdvertiserTrustSignal(Icons.location_on_outlined, 'موقع المكتب مسجل'),
    ];

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EbrokerAdvertiserCard(name: advertiser.name, compact: true, photoUrl: profile?.photoUrl, completedDeals: profile?.completedDeals, activeListings: profile?.activeListings,
            identity: verified ? advertiser.verificationLabel : 'معلن غير موثق',
            rating: advertiser.ratingAverage, ratingCount: advertiser.ratingCount,
            verified: verified, onTap: () => context.push('/advertisers/${advertiser.id}')),
          ExpansionTile(tilePadding: EdgeInsets.zero, title: const Text('التوثيق والتقييم'), children: [
          Text(
            verified
                ? 'تم التحقق من صفة المعلن داخل المنصة. إشارات الثقة أدناه مبنية على بيانات تحقق فعلية وليست شارات دعائية.'
                : 'لم يكتمل توثيق هذا المعلن داخل المنصة. استخدم المراسلة داخل التطبيق وناقش تفاصيل العقار مع المعلن قبل اتخاذ أي قرار.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          if (signals.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s12),
            Wrap(
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.s8,
              children: signals
                  .map(
                    (signal) => Chip(
                      avatar: EbrokerIcon(signal.icon, size: 18),
                      label: Text(signal.label),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          const SizedBox(height: AppSpacing.s12),
          Row(
            children: [
              Expanded(
                child: Text(
                  advertiser.ratingCount == 0
                      ? 'لا توجد تقييمات للمعلن بعد'
                      : 'التقييم ${advertiser.ratingAverage.toStringAsFixed(1)} من 5 (${advertiser.ratingCount})',
                ),
              ),
              Text('${property.commentsCount} تعليق ظاهر'),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          AppButton(
            label: 'التعليقات والتقييمات',
            icon: Icons.rate_review_outlined,
            style: AppButtonStyle.tonal,
            onPressed: onCommunity,
            expand: true,
          ),
          ]),
        ],
    );
  }
}

class _AdvertiserTrustSignal {
  const _AdvertiserTrustSignal(this.icon, this.label);
  final IconData icon;
  final String label;
}

class _PropertyPrimaryActions extends StatelessWidget {
  const _PropertyPrimaryActions({required this.loading, required this.calling, required this.onMessage, required this.onCall});
  final bool loading, calling;
  final VoidCallback? onMessage, onCall;
  @override
  Widget build(BuildContext context) {
    final call = AppButton(key: const ValueKey('property-call'), label: 'اتصال', icon: Icons.call_outlined, loading: calling, onPressed: onCall, expand: true);
    final message = AppButton(key: const ValueKey('property-message'), label: 'محادثة', icon: Icons.chat_bubble_outline, loading: loading, onPressed: onMessage, expand: true);
    return Material(color: Theme.of(context).colorScheme.surface, elevation: 10,
      child: SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: MediaQuery.textScalerOf(context).scale(14) > 20
          ? Column(mainAxisSize: MainAxisSize.min, children: [call, const SizedBox(height: 8), message])
          : Row(children: [Expanded(child: call), const SizedBox(width: 10), Expanded(child: message)]),
      )),
    );
  }
}

class _PropertyDetailsSkeleton extends StatelessWidget {
  const _PropertyDetailsSkeleton({this.scrollController, this.summary});
  final ScrollController? scrollController;
  final PropertySummary? summary;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsetsDirectional.all(AppLayout.compactPageGutter),
      children: [
        if (summary case final PropertySummary row) ...[
          AppPropertyMedia(imageUrl: row.mainImage, height: 260, propertyType: row.type),
          const SizedBox(height: 12), Text(row.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8), AppPropertyPrice(price: _formatPrice(row.purpose == 'rent' ? row.monthlyRent ?? row.price : row.price), currency: row.currency),
          const SizedBox(height: 8), const Text('جارٍ تحديث تفاصيل الإعلان…'),
        ] else ...[
          const AppSkeleton(height: 260, radius: AppRadii.card),
          const SizedBox(height: AppSpacing.s40), const AppSkeleton(height: 32),
          const SizedBox(height: AppSpacing.s12), const AppSkeleton(height: 24, width: 180),
        ],
        const SizedBox(height: AppSpacing.s24), const AppSkeleton(height: 120, radius: AppRadii.card),
        const SizedBox(height: AppSpacing.s16), const AppSkeleton(height: 160, radius: AppRadii.card),
      ],
    );
  }
}

String _factLabel(IconData icon) {
  if (icon == Icons.square_foot) { return 'المساحة'; }
  if (icon == Icons.bed_outlined) { return 'غرف النوم'; }
  if (icon == Icons.bathtub_outlined) { return 'الحمامات'; }
  if (icon == Icons.layers_outlined) { return 'الدور'; }
  if (icon == Icons.elevator_outlined) { return 'المصعد'; }
  if (icon == Icons.apartment) { return 'نطاق الوحدة'; }
  if (icon == Icons.local_parking_outlined) { return 'الموقف'; }
  if (icon == Icons.account_balance_outlined) { return 'نوع الملكية'; }
  if (icon == Icons.explore_outlined) { return 'واجهة المبنى'; }
  return 'المواصفات';
}

String _purposeLabel(String value) => value == 'rent' ? 'للإيجار' : 'للبيع';

String _typeLabel(String value) => switch (value) {
      'apartment' => 'شقة',
      'house' => 'منزل',
      'villa' => 'فيلا',
      'land' => 'أرض',
      'shop' => 'محل',
      'office' => 'مكتب',
      'farm' => 'مزرعة',
      _ => value,
    };

String _statusLabel(String value) => switch (value) {
      'pending' => 'قيد المراجعة',
      'rejected' => 'مرفوض',
      'archived' => 'مؤرشف',
      'draft' => 'مسودة',
      _ => 'غير متاح',
    };

String _formatPrice(double value) {
  final digits = value.round().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    final remaining = digits.length - index;
    buffer.write(digits[index]);
    if (remaining > 1 && remaining % 3 == 1) buffer.write(',');
  }
  return buffer.toString();
}

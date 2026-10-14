import 'package:flutter/material.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../../../core/widgets/ebroker_screen_sections.dart';
import '../../../core/theme/ebroker_design.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/local/listing_viewer_key_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../../../router/app_deep_links.dart';
import '../../account/data/auth_controller.dart';
import '../../account/data/auth_return_intent.dart';
import '../../community/presentation/listing_community_screen.dart';
import '../../messages/data/message_repository.dart';
import '../data/favorites_repository.dart';
import '../data/property_repository.dart';
import '../domain/property_details.dart';
import '../domain/property_field_options.dart';
import 'add_property_wizard_screen.dart';
import 'my_listings_screen.dart';
import 'property_market_context_card.dart';
import 'property_sai_public_line.dart';
import 'property_question_section.dart';

final propertyDetailsProvider =
    FutureProvider.autoDispose.family<PropertyDetails, int>((ref, propertyId) {
  ref.watch(propertyDataRevisionProvider);
  return ref.watch(propertyRepositoryProvider).details(propertyId);
});

class PropertyDetailsScreen extends ConsumerStatefulWidget {
  const PropertyDetailsScreen({required this.propertyId, super.key});

  final int propertyId;

  @override
  ConsumerState<PropertyDetailsScreen> createState() => _PropertyDetailsScreenState();
}

class _PropertyDetailsScreenState extends ConsumerState<PropertyDetailsScreen> {
  int _imageIndex = 0;
  bool _startingConversation = false;
  bool _changingFavorite = false;
  bool _consumingPendingFavorite = false;
  bool _viewRecorded = false;

  @override
  void didUpdateWidget(covariant PropertyDetailsScreen old) {
    super.didUpdateWidget(old);
    if (old.propertyId != widget.propertyId) { _viewRecorded = false; _imageIndex = 0; }
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
        !loaded.isOwner;

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
              tooltip: 'نسخ رابط العقار',
              onPressed: _copyShareReference,
            ),
          ],
        ),
        body: details.when(
          loading: () => const _PropertyDetailsSkeleton(),
          error: (error, _) => AppErrorState(
            message: friendlyApiError(error),
            onRetry: () => ref.invalidate(propertyDetailsProvider(widget.propertyId)),
          ),
          data: (property) => _buildContent(property, favoriteIds),
        ),
        bottomNavigationBar: showPrimaryActions
            ? _PropertyPrimaryActions(
                loading: _startingConversation,
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
    final facts = <AppPropertyFact>[
      if (property.areaValue != null)
        AppPropertyFact(
          icon: Icons.square_foot,
          label:
              '${formatPropertyAreaValue(property.areaValue!)} ${propertyAreaUnitLabel(property.areaUnit)}',
        )
      else if (property.areaM2 != null)
        AppPropertyFact(icon: Icons.square_foot, label: '${property.areaM2} م²'),
      if (property.bedrooms != null)
        AppPropertyFact(icon: Icons.bed_outlined, label: '${property.bedrooms} غرف'),
      if (property.bathrooms != null)
        AppPropertyFact(icon: Icons.bathtub_outlined, label: '${property.bathrooms} حمام'),
      if (property.hasParking == true)
        const AppPropertyFact(
          icon: Icons.local_parking_outlined,
          label: 'موقف سيارة',
        ),
      if (property.hasElevator != null)
        AppPropertyFact(icon: Icons.elevator_outlined, label: property.hasElevator! ? 'يوجد مصعد' : 'بدون مصعد'),
      if (property.tenureType != null)
        AppPropertyFact(
          icon: Icons.account_balance_outlined,
          label: property.tenureType == 'waqf' ? 'وقف' : 'حر',
        ),
      if (property.buildingFacade != null)
        AppPropertyFact(
          icon: Icons.explore_outlined,
          label: propertyFacadeLabel(property.buildingFacade),
        ),
    ];

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(propertyDetailsProvider(widget.propertyId));
        ref.invalidate(propertySaiPublicProvider(widget.propertyId));
        ref.invalidate(propertyMarketContextProvider(widget.propertyId));
        if (ref.read(authControllerProvider).asData?.value != null) {
          ref.invalidate(favoritePropertyIdsProvider);
        }
        await ref.read(propertyDetailsProvider(widget.propertyId).future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsetsDirectional.fromSTEB(
          AppLayout.compactPageGutter,
          AppSpacing.s12,
          AppLayout.compactPageGutter,
          published && !property.isOwner ? 124.0 : AppSpacing.s40,
        ),
        children: [
          _Gallery(
            images: property.images,
            index: _imageIndex,
            onChanged: (index) => setState(() => _imageIndex = index),
          ),
          EbrokerPropertyHeading(
            category: _typeLabel(property.type), title: property.title,
            purpose: _purposeLabel(property.purpose),
            price: AppPropertyPrice(price: _formatPrice(property.price), currency: property.currency),
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
          if (property.address != null) ...[
            const SizedBox(height: AppSpacing.s24),
            const AppSectionHeader(title: 'الموقع'),
            const SizedBox(height: AppSpacing.s8),
            AppSurface(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  EbrokerIcon(
                    Icons.location_on_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Expanded(child: Text(property.address!)),
                ],
              ),
            ),
          ],
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
                    decoration: BoxDecoration(color: EbrokerDesign.surface,
                      borderRadius: BorderRadius.circular(4), border: Border.all(color: EbrokerDesign.border)),
                    child: EbrokerIcon(facts[index].icon, size: 24, color: EbrokerDesign.text)),
                  SizedBox(width: 10.rw(context)),
                  Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                      EbrokerText(_factLabel(facts[index].icon), size: 12, color: EbrokerDesign.textLight, maxLines: 1),
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
          const SizedBox(height: AppSpacing.s24),
          EbrokerSectionPanel(title: 'وصف العقار',
            child: Text(
              property.description ??
                  'لم يضف المعلن وصفاً تفصيلياً لهذا العقار بعد.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
          if (published && property.availabilityStatus == 'available') ...[
            const SizedBox(height: AppSpacing.s24), PropertyQuestionSection(propertyId: property.id),
          ],
          if (published && property.advertiser != null) ...[
            const SizedBox(height: AppSpacing.s24),
            const AppSectionHeader(title: 'المعلن والثقة'),
            const SizedBox(height: AppSpacing.s8),
            _AdvertiserCard(
              property: property,
              onCommunity: () => _openCommunity(property),
            ),
          ],
          if (property.similar.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s32),
            const AppSectionHeader(title: 'عقارات مشابهة'),
            const SizedBox(height: AppSpacing.s12),
            SizedBox(
              height: 340 + (MediaQuery.textScalerOf(context).scale(14) - 14) * 8,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: property.similar.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: AppSpacing.s12),
                itemBuilder: (context, index) {
                  final item = property.similar[index];
                  final isFavorite = favoriteIds.contains(item.id);
                  return SizedBox(
                    width: 290,
                    child: AppPropertyCard(
                      categoryLabel: ebrokerPropertyTypeLabel(item.type),
                  title: item.title,
                      price: _formatPrice(item.price),
                      currency: item.currency,
                      imageUrl: item.mainImage, imageUrls: item.imageUrls, isSpotlight: item.isSpotlight,
                      location: item.address,
                      purposeLabel: _purposeLabel(item.purpose),
                      facts: [
                        if (item.areaM2 != null)
                          AppPropertyFact(
                            icon: Icons.square_foot,
                            label: '${item.areaM2} م²',
                          ),
                        if (item.bedrooms != null)
                          AppPropertyFact(
                            icon: Icons.bed_outlined,
                            label: '${item.bedrooms} غرف',
                          ),
                      ],
                      trailing: IconButton.filledTonal(
                        tooltip:
                            isFavorite ? 'إزالة من المفضلة' : 'حفظ في المفضلة',
                        icon: EbrokerIcon(
                          isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                        ),
                        onPressed: _changingFavorite || _consumingPendingFavorite
                            ? null
                            : () => _toggleFavorite(
                                  item.id,
                                  currentlyFavorite: isFavorite,
                                ),
                      ),
                      unavailable: item.status != 'published',
                      onTap: () => context.push('/properties/${item.id}'),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
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

  Future<void> _copyShareReference() async {
    final link = propertyAppDeepLink(widget.propertyId).toString();
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ رابط العقار ويمكن فتحه في التطبيق.')),
    );
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
  });

  final List<PropertyImageItem> images;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: SizedBox(
        height: 218.rs(context),
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
                        builder: (_) => _FullscreenGallery(
                          images: images,
                          initialIndex: imageIndex,
                        ),
                      ),
                    ),
                    child: AppPropertyMedia(
                      imageUrl: images[imageIndex].url,
                      height: double.infinity,
                    ),
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
                    MaterialPageRoute<void>(builder: (_) => _FullscreenGallery(images: images, initialIndex: index))),
                    child: Container(padding: EdgeInsets.symmetric(horizontal: 8.rw(context), vertical: 4.rh(context)),
                      decoration: BoxDecoration(color: EbrokerDesign.surface,
                        borderRadius: BorderRadius.circular(16), border: Border.all(color: EbrokerDesign.border)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const EbrokerImage('gallery', size: 14, color: EbrokerDesign.text),
                        SizedBox(width: 4.rw(context)),
                        EbrokerText('${images.length}', size: 12, weight: FontWeight.w600),
                      ]))))),
          ],
        ),
      ),
    );
  }
}

class _FullscreenGallery extends StatefulWidget {
  const _FullscreenGallery({required this.images, required this.initialIndex});

  final List<PropertyImageItem> images;
  final int initialIndex;

  @override
  State<_FullscreenGallery> createState() => _FullscreenGalleryState();
}

class _FullscreenGalleryState extends State<_FullscreenGallery> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              PageView.builder(
                controller: _controller,
                itemCount: widget.images.length,
                onPageChanged: (value) => setState(() => _index = value),
                itemBuilder: (context, imageIndex) => Center(
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Image.network(
                      widget.images[imageIndex].url,
                      fit: BoxFit.contain,
                      width: double.infinity,
                      errorBuilder: (_, __, ___) => const Center(
                        child: EbrokerIcon(Icons.broken_image_outlined, color: Colors.white54, size: 52),
                      ),
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const Center(child: CircularProgressIndicator());
                      },
                    ),
                  ),
                ),
              ),
              PositionedDirectional(
                top: AppSpacing.s8,
                start: AppSpacing.s8,
                child: IconButton.filled(
                  tooltip: 'إغلاق الصور',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const EbrokerIcon(Icons.close_rounded),
                ),
              ),
              PositionedDirectional(
                bottom: AppSpacing.s16,
                start: 0,
                end: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .58),
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                    child: Text(
                      '${_index + 1}/${widget.images.length} • اسحب للتنقل واضغط بإصبعين للتكبير',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdvertiserCard extends StatelessWidget {
  const _AdvertiserCard({
    required this.property,
    required this.onCommunity,
  });

  final PropertyDetails property;
  final VoidCallback onCommunity;

  @override
  Widget build(BuildContext context) {
    final advertiser = property.advertiser!;
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
          EbrokerAdvertiserCard(name: advertiser.name,
            identity: verified ? advertiser.verificationLabel : 'معلن غير موثق',
            rating: advertiser.ratingAverage, ratingCount: advertiser.ratingCount,
            verified: verified, onTap: verified ? () => context.push('/advertisers/${advertiser.id}') : onCommunity),
          const SizedBox(height: AppSpacing.s12),
          Text(
            verified
                ? 'تم التحقق من صفة المعلن داخل المنصة. إشارات الثقة أدناه مبنية على بيانات تحقق فعلية وليست شارات دعائية.'
                : 'لم يكتمل توثيق هذا المعلن داخل المنصة. استخدم المراسلة والمعاينة داخل التطبيق قبل اتخاذ أي قرار.',
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
            label: 'التعليقات والتقييم والبلاغات',
            icon: Icons.rate_review_outlined,
            style: AppButtonStyle.tonal,
            onPressed: onCommunity,
            expand: true,
          ),
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
  const _PropertyPrimaryActions({
    required this.loading,
    required this.onMessage,
  });

  final bool loading;
  final VoidCallback? onMessage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: .12),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppLayout.compactPageGutter,
            AppSpacing.s10,
            AppLayout.compactPageGutter,
            AppSpacing.s10,
          ),
          child: AppButton(
            label: loading ? 'جارٍ الفتح...' : 'تواصل مع المعلن',
            icon: Icons.forum_outlined,
            loading: loading,
            onPressed: onMessage,
            expand: true,
          ),
        ),
      ),
    );
  }
}

class _PropertyDetailsSkeleton extends StatelessWidget {
  const _PropertyDetailsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsetsDirectional.all(AppLayout.compactPageGutter),
      children: const [
        AppSkeleton(height: 260, radius: AppRadii.card),
        SizedBox(height: AppSpacing.s40),
        AppSkeleton(height: 32),
        SizedBox(height: AppSpacing.s12),
        AppSkeleton(height: 24, width: 180),
        SizedBox(height: AppSpacing.s24),
        AppSkeleton(height: 120, radius: AppRadii.card),
        SizedBox(height: AppSpacing.s16),
        AppSkeleton(height: 160, radius: AppRadii.card),
      ],
    );
  }
}

String _factLabel(IconData icon) {
  if (icon == Icons.square_foot) { return 'المساحة'; }
  if (icon == Icons.bed_outlined) { return 'غرف النوم'; }
  if (icon == Icons.bathtub_outlined) { return 'الحمامات'; }
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

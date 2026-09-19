import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/design/app_design.dart';
import '../../../router/app_deep_links.dart';
import '../../account/data/auth_controller.dart';
import '../../account/data/auth_return_intent.dart';
import '../../bookings/presentation/booking_request_sheet.dart';
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
                onViewing: () => _requestViewing(loaded),
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
      child: AppContentFrame(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsetsDirectional.fromSTEB(
            0,
            AppSpacing.s12,
            0,
            AppSpacing.s32,
          ),
          children: [
            _Gallery(
              images: property.images,
              index: _imageIndex,
              onChanged: (index) => setState(() => _imageIndex = index),
            ),
            const SizedBox(height: AppSpacing.s16),
            AppSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpacing.s8,
                    runSpacing: AppSpacing.s8,
                    children: [
                      AppStatusBadge(
                        label: _purposeLabel(property.purpose),
                        tone: AppStatusTone.info,
                        icon: property.purpose == 'rent'
                            ? Icons.key_outlined
                            : Icons.sell_outlined,
                      ),
                      AppStatusBadge(
                        label: _typeLabel(property.type),
                        tone: AppStatusTone.neutral,
                        icon: Icons.home_work_outlined,
                      ),
                      if (!published)
                        AppStatusBadge(
                          label: _statusLabel(property.status),
                          tone: property.status == 'rejected'
                              ? AppStatusTone.error
                              : AppStatusTone.warning,
                          icon: Icons.info_outline,
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  AppPropertyPrice(
                    price: _formatPrice(property.price),
                    currency: property.currency,
                    suffix: property.purpose == 'rent' ? 'للإيجار' : 'للبيع',
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          property.title,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      if (property.isOwner)
                        PopupMenuButton<String>(
                          tooltip: 'إدارة الإعلان',
                          onSelected: (action) => _ownerAction(action, property),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('تعديل الإعلان')),
                            PopupMenuItem(value: 'mine', child: Text('إعلاناتي')),
                          ],
                        ),
                    ],
                  ),
                  PropertySaiPublicLine(propertyId: property.id),
                ],
              ),
            ),
            if (!published && !property.isOwner) ...[
              const SizedBox(height: AppSpacing.s40),
              const AppUnavailableState(),
            ],
            if (property.address != null) ...[
              const SizedBox(height: AppSpacing.s24),
              AppSectionCard(
                title: 'الموقع',
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
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
              AppSectionCard(
                title: 'مواصفات العقار',
                child: AppPropertyFacts(facts: facts),
              ),
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
            AppSectionCard(
              title: 'وصف العقار',
              child: Text(
                property.description ??
                    'لم يضف المعلن وصفاً تفصيلياً لهذا العقار بعد.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            if (published && property.advertiser != null) ...[
              const SizedBox(height: AppSpacing.s24),
              const AppSectionHeader(title: 'المعلن والثقة'),
              const SizedBox(height: AppSpacing.s8),
              _AdvertiserCard(
                property: property,
                onCommunity: () => _openCommunity(property),
              ),
            ],
            if (published &&
                !property.isOwner &&
                (property.contactPhone != null ||
                    property.contactWhatsapp != null)) ...[
              const SizedBox(height: AppSpacing.s24),
              const AppSectionHeader(
                title: 'بيانات التواصل',
                subtitle:
                    'المراسلة وطلب المعاينة مثبتان أسفل الشاشة للوصول السريع.',
              ),
              const SizedBox(height: AppSpacing.s12),
              AppSurface(
                child: Column(
                  children: [
                    if (property.contactPhone != null)
                      AppListRow(
                        title: 'الهاتف',
                        subtitle: property.contactPhone,
                        leading: const Icon(Icons.phone_outlined),
                        trailing: const Icon(Icons.copy_outlined),
                        onTap: () => _copyContact(property.contactPhone!),
                      ),
                    if (property.contactWhatsapp != null)
                      AppListRow(
                        title: 'واتساب',
                        subtitle: property.contactWhatsapp,
                        leading: const Icon(Icons.chat_outlined),
                        trailing: const Icon(Icons.copy_outlined),
                        onTap: () => _copyContact(property.contactWhatsapp!),
                      ),
                  ],
                ),
              ),
            ],
            if (property.similar.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s32),
              const AppSectionHeader(title: 'عقارات مشابهة'),
              const SizedBox(height: AppSpacing.s12),
              AppPropertyRail(
                itemCount: property.similar.length,
                itemBuilder: (context, index) {
                  final item = property.similar[index];
                  final isFavorite = favoriteIds.contains(item.id);
                  return AppPropertyCard(
                    title: item.title,
                    price: _formatPrice(item.price),
                    currency: item.currency,
                    imageUrl: item.mainImage,
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
                      icon: Icon(
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
                  );
                },
              ),
            ],
          ],
        ),
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

  Future<void> _requestViewing(PropertyDetails property) async {
    final user = ref.read(authControllerProvider).asData?.value;
    if (user == null) {
      await context.push('/auth');
      return;
    }
    if (!user.isActive) {
      await context.push('/verify-phone');
      return;
    }
    final booking = await BookingRequestSheet.showForProperty(
      context,
      propertyId: property.id,
      title: property.title,
    );
    if (!mounted || booking == null) return;
    final threadId = booking.messageThreadId;
    if (threadId != null) {
      ref.read(messageDataRevisionProvider.notifier).state++;
      await context.push('/messages/$threadId');
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'تم إرسال طلب المعاينة ويمكن متابعته من صفحة المعاينات.',
        ),
      ),
    );
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

  Future<void> _copyContact(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ الرقم.')),
    );
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: _PropertyGalleryFrame(
            child: images.isEmpty
                ? const AppPropertyMedia(height: double.infinity)
                : PageView.builder(
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
          ),
        ),
        if (images.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s12),
          Row(
            children: [
              const Icon(Icons.fullscreen_rounded),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Text('تكبير الصور', style: Theme.of(context).textTheme.labelLarge),
              ),
              const SizedBox(width: AppSpacing.s8),
              AppStatusBadge(label: '${index + 1}/${images.length}'),
            ],
          ),
        ],
      ],
    );
  }
}

/// Shared by the real gallery and its loading placeholder.
class _PropertyGalleryFrame extends StatelessWidget {
  const _PropertyGalleryFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final maxHeight = (MediaQuery.sizeOf(context).height *
                  AppLayout.galleryViewportHeightFraction)
              .clamp(0.0, AppSizes.propertyGalleryMaxHeight);
          return SizedBox(
            width: double.infinity,
            height: (constraints.maxWidth / AppLayout.propertyGalleryAspectRatio)
                .clamp(0.0, maxHeight),
            child: child,
          );
        },
      );
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
                        child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 52),
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
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
              PositionedDirectional(
                bottom: AppSpacing.s16,
                start: 0,
                end: 0,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height *
                          AppLayout.galleryCaptionMaxHeightFraction,
                    ),
                    child: SingleChildScrollView(
                      primary: false,
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.s12),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: AppOpacity.mediaScrim),
                          borderRadius: BorderRadius.circular(AppRadii.card),
                        ),
                        child: Text(
                          '${_index + 1}/${widget.images.length} • اسحب للتنقل واضغط بإصبعين للتكبير',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.white),
                        ),
                      ),
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

    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIdentityMark(
                icon: verified ? Icons.verified_user_outlined : Icons.person_outline,
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      advertiser.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      verified ? advertiser.verificationLabel : 'معلن غير موثق',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    AppStatusBadge(
                      label: verified ? 'موثق' : 'غير موثق',
                      tone: verified ? AppStatusTone.success : AppStatusTone.warning,
                      icon: verified ? Icons.verified_outlined : Icons.info_outline,
                    ),
                  ],
                ),
              ),
            ],
          ),
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
                    (signal) => AppStatusBadge(
                      icon: signal.icon,
                      label: signal.label,
                      tone: AppStatusTone.success,
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          const SizedBox(height: AppSpacing.s12),
          Wrap(
            spacing: AppSpacing.s16,
            runSpacing: AppSpacing.s8,
            children: [
              Text(
                advertiser.ratingCount == 0
                    ? 'لا توجد تقييمات للمعلن بعد'
                    : 'التقييم ${advertiser.ratingAverage.toStringAsFixed(1)} من 5 (${advertiser.ratingCount})',
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
      ),
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
    required this.onViewing,
  });

  final bool loading;
  final VoidCallback? onMessage;
  final VoidCallback onViewing;

  @override
  Widget build(BuildContext context) {
    return AppActionDock(
      child: AppFieldPair(
        first: AppButton(
          label: loading ? 'جارٍ الفتح...' : 'مراسلة',
          icon: Icons.forum_outlined,
          loading: loading,
          onPressed: onMessage,
          expand: true,
        ),
        second: AppButton(
          label: 'طلب معاينة',
          icon: Icons.event_available_outlined,
          style: AppButtonStyle.tonal,
          onPressed: onViewing,
          expand: true,
        ),
      ),
    );
  }
}

class _PropertyDetailsSkeleton extends StatelessWidget {
  const _PropertyDetailsSkeleton();

  @override
  Widget build(BuildContext context) {
    return AppContentFrame(
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
        children: const [
          _PropertyGalleryFrame(child: AppSkeleton(height: double.infinity, radius: AppRadii.card)),
          SizedBox(height: AppSpacing.s16),
          AppSkeleton(height: 32),
          SizedBox(height: AppSpacing.s12),
          AppSkeleton(height: 24, width: 180),
          SizedBox(height: AppSpacing.s24),
          AppSkeleton(height: 120, radius: AppRadii.card),
          SizedBox(height: AppSpacing.s16),
          AppSkeleton(height: 160, radius: AppRadii.card),
        ],
      ),
    );
  }
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

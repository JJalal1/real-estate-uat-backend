import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../../../router/app_deep_links.dart';
import '../../account/data/auth_controller.dart';
import '../../bookings/presentation/booking_request_sheet.dart';
import '../../community/presentation/listing_community_screen.dart';
import '../../messages/data/message_repository.dart';
import '../data/favorites_repository.dart';
import '../data/property_repository.dart';
import '../domain/property_details.dart';
import '../domain/property_field_options.dart';
import 'add_property_wizard_screen.dart';
import 'my_listings_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    final details = ref.watch(propertyDetailsProvider(widget.propertyId));
    final user = ref.watch(authControllerProvider).asData?.value;
    final favoriteIds = user == null
        ? const <int>{}
        : ref.watch(favoritePropertyIdsProvider).maybeWhen(
              data: (value) => value,
              orElse: () => const <int>{},
            );
    final loaded = details.asData?.value;

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
                onPressed: _changingFavorite
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
      ),
    );
  }

  Widget _buildContent(PropertyDetails property, Set<int> favoriteIds) {
    final published = property.status == 'published';
    final facts = <AppPropertyFact>[
      if (property.areaValue != null)
        AppPropertyFact(
          icon: Icons.square_foot,
          label: '${formatPropertyAreaValue(property.areaValue!)} ${propertyAreaUnitLabel(property.areaUnit)}',
        )
      else if (property.areaM2 != null)
        AppPropertyFact(icon: Icons.square_foot, label: '${property.areaM2} م²'),
      if (property.bedrooms != null)
        AppPropertyFact(icon: Icons.bed_outlined, label: '${property.bedrooms} غرف'),
      if (property.bathrooms != null)
        AppPropertyFact(icon: Icons.bathtub_outlined, label: '${property.bathrooms} حمام'),
      if (property.hasParking == true)
        const AppPropertyFact(icon: Icons.local_parking_outlined, label: 'موقف سيارة'),
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
        if (ref.read(authControllerProvider).asData?.value != null) {
          ref.invalidate(favoritePropertyIdsProvider);
        }
        await ref.read(propertyDetailsProvider(widget.propertyId).future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppLayout.compactPageGutter,
          AppSpacing.s12,
          AppLayout.compactPageGutter,
          AppSpacing.s40,
        ),
        children: [
          _Gallery(
            images: property.images,
            index: _imageIndex,
            onChanged: (index) => setState(() => _imageIndex = index),
          ),
          const SizedBox(height: AppSpacing.s20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(property.title, style: Theme.of(context).textTheme.headlineSmall),
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
          const SizedBox(height: AppSpacing.s8),
          AppPropertyPrice(
            price: _formatPrice(property.price),
            currency: property.currency,
            suffix: property.purpose == 'rent' ? 'للإيجار' : 'للبيع',
          ),
          const SizedBox(height: AppSpacing.s12),
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: [
              AppStatusBadge(
                label: _purposeLabel(property.purpose),
                tone: AppStatusTone.info,
                icon: property.purpose == 'rent' ? Icons.key_outlined : Icons.sell_outlined,
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
          if (!published && !property.isOwner) ...[
            const SizedBox(height: AppSpacing.s20),
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
                  Icon(Icons.location_on_outlined, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: AppSpacing.s8),
                  Expanded(child: Text(property.address!)),
                ],
              ),
            ),
          ],
          if (facts.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s24),
            const AppSectionHeader(title: 'مواصفات العقار'),
            const SizedBox(height: AppSpacing.s8),
            AppSurface(child: AppPropertyFacts(facts: facts)),
          ],
          const SizedBox(height: AppSpacing.s24),
          const AppSectionHeader(title: 'وصف العقار'),
          const SizedBox(height: AppSpacing.s8),
          AppSurface(
            child: Text(
              property.description ?? 'لم يضف المعلن وصفاً تفصيلياً لهذا العقار بعد.',
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
          if (published && !property.isOwner) ...[
            const SizedBox(height: AppSpacing.s24),
            const AppSectionHeader(
              title: 'تواصل وحدد المعاينة',
              subtitle: 'كل تواصل يبدأ من هذا العقار حتى يبقى السياق واضحاً للطرفين.',
            ),
            const SizedBox(height: AppSpacing.s12),
            AppButton(
              label: _startingConversation ? 'جارٍ فتح المحادثة...' : 'مراسلة المعلن',
              icon: Icons.forum_outlined,
              loading: _startingConversation,
              onPressed: () => _startConversation(property),
              expand: true,
            ),
            const SizedBox(height: AppSpacing.s8),
            AppButton(
              label: 'طلب موعد معاينة',
              icon: Icons.event_available_outlined,
              style: AppButtonStyle.outlined,
              onPressed: () => _requestViewing(property),
              expand: true,
            ),
            if (property.contactPhone != null || property.contactWhatsapp != null) ...[
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
          ],
          if (property.similar.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s32),
            const AppSectionHeader(title: 'عقارات مشابهة'),
            const SizedBox(height: AppSpacing.s12),
            SizedBox(
              height: 340,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: property.similar.length,
                separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.s12),
                itemBuilder: (context, index) {
                  final item = property.similar[index];
                  final isFavorite = favoriteIds.contains(item.id);
                  return SizedBox(
                    width: 260,
                    child: AppPropertyCard(
                      title: item.title,
                      price: _formatPrice(item.price),
                      currency: item.currency,
                      imageUrl: item.mainImage,
                      location: item.address,
                      purposeLabel: _purposeLabel(item.purpose),
                      facts: [
                        if (item.areaM2 != null)
                          AppPropertyFact(icon: Icons.square_foot, label: '${item.areaM2} م²'),
                        if (item.bedrooms != null)
                          AppPropertyFact(icon: Icons.bed_outlined, label: '${item.bedrooms} غرف'),
                      ],
                      trailing: IconButton.filledTonal(
                        tooltip: isFavorite ? 'إزالة من المفضلة' : 'حفظ في المفضلة',
                        icon: Icon(
                          isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        ),
                        onPressed: _changingFavorite
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
    var user = ref.read(authControllerProvider).asData?.value;
    final wasAnonymous = user == null;
    if (user == null) {
      await context.push('/auth');
      if (!mounted) return;
      user = ref.read(authControllerProvider).asData?.value;
      if (user == null) return;
    }
    if (!user.isActive) {
      await context.push('/verify-phone');
      return;
    }
    if (_changingFavorite) return;

    setState(() => _changingFavorite = true);
    try {
      final repository = ref.read(favoritesRepositoryProvider);
      if (wasAnonymous || !currentlyFavorite) {
        await repository.add(propertyId);
      } else {
        await repository.remove(propertyId);
      }
      ref.read(favoriteDataRevisionProvider.notifier).state++;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasAnonymous || !currentlyFavorite
                ? 'تم حفظ العقار في المفضلة.'
                : 'تمت إزالة العقار من المفضلة.',
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
      const SnackBar(content: Text('تم إرسال طلب المعاينة ويمكن متابعته من صفحة المعاينات.')),
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
      final thread = await ref.read(messageRepositoryProvider).startForProperty(property.id);
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
      if (mounted) ref.invalidate(propertyDetailsProvider(widget.propertyId));
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
  const _Gallery({required this.images, required this.index, required this.onChanged});

  final List<PropertyImageItem> images;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (images.isEmpty)
              const AppPropertyMedia(height: double.infinity)
            else
              PageView.builder(
                itemCount: images.length,
                onPageChanged: onChanged,
                itemBuilder: (context, imageIndex) => AppPropertyMedia(
                  imageUrl: images[imageIndex].url,
                  height: double.infinity,
                ),
              ),
            if (images.isNotEmpty)
              PositionedDirectional(
                bottom: AppSpacing.s12,
                end: AppSpacing.s12,
                child: Container(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: AppSpacing.s12,
                    vertical: AppSpacing.s4,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.inverseSurface.withValues(alpha: .86),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text(
                    '${index + 1}/${images.length}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onInverseSurface,
                        ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AdvertiserCard extends StatelessWidget {
  const _AdvertiserCard({required this.property, required this.onCommunity});

  final PropertyDetails property;
  final VoidCallback onCommunity;

  @override
  Widget build(BuildContext context) {
    final advertiser = property.advertiser!;
    final verified = advertiser.verificationStatus == 'approved';
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                child: Icon(verified ? Icons.verified_outlined : Icons.person_outline),
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(advertiser.name, style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      verified ? advertiser.verificationLabel : 'معلن',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (verified)
                const AppStatusBadge(
                  label: 'موثق',
                  tone: AppStatusTone.success,
                  icon: Icons.verified_outlined,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          Text(
            advertiser.ratingCount == 0
                ? 'لا توجد تقييمات للمعلن بعد'
                : 'التقييم ${advertiser.ratingAverage.toStringAsFixed(1)} من 5 (${advertiser.ratingCount})',
          ),
          Text('${property.commentsCount} تعليق ظاهر'),
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

class _PropertyDetailsSkeleton extends StatelessWidget {
  const _PropertyDetailsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsetsDirectional.all(AppLayout.compactPageGutter),
      children: const [
        AppSkeleton(height: 260, radius: AppRadii.card),
        SizedBox(height: AppSpacing.s20),
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

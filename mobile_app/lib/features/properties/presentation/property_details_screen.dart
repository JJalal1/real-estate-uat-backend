import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../account/data/auth_controller.dart';
import '../../bookings/presentation/booking_request_sheet.dart';
import '../../community/presentation/listing_community_screen.dart';
import '../../messages/data/message_repository.dart';
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
  const PropertyDetailsScreen({
    required this.propertyId,
    super.key,
  });

  final int propertyId;

  @override
  ConsumerState<PropertyDetailsScreen> createState() =>
      _PropertyDetailsScreenState();
}

class _PropertyDetailsScreenState extends ConsumerState<PropertyDetailsScreen> {
  int _imageIndex = 0;
  bool _startingConversation = false;

  @override
  Widget build(BuildContext context) {
    final details = ref.watch(propertyDetailsProvider(widget.propertyId));

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F8F7),
        appBar: AppBar(
          title: const Text('تفاصيل العقار'),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: 'إعلاناتي',
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const MyListingsScreen(),
                ),
              ),
              icon: const Icon(Icons.inventory_2_outlined),
            ),
          ],
        ),
        body: details.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => _ErrorState(
            onRetry: () =>
                ref.invalidate(propertyDetailsProvider(widget.propertyId)),
          ),
          data: (property) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(propertyDetailsProvider(widget.propertyId));
              await ref.read(propertyDetailsProvider(widget.propertyId).future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _buildGallery(property),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        property.title,
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                      ),
                    ),
                    if (property.isOwner)
                      PopupMenuButton<String>(
                        onSelected: (action) => _ownerAction(action, property),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                              value: 'edit', child: Text('تعديل الإعلان')),
                          PopupMenuItem(value: 'mine', child: Text('إعلاناتي')),
                          PopupMenuItem(
                              value: 'delete', child: Text('حذف الإعلان')),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '${_formatPrice(property.price)} ${property.currency}',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: const Color(0xFF00796B),
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoChip(
                      icon: Icons.sell_outlined,
                      label: _purposeLabel(property.purpose),
                    ),
                    _InfoChip(
                      icon: Icons.home_work_outlined,
                      label: _typeLabel(property.type),
                    ),
                    if (property.status != 'published')
                      _InfoChip(
                        icon: Icons.info_outline,
                        label: _statusLabel(property.status),
                      ),
                  ],
                ),
                if (property.address != null) ...[
                  const SizedBox(height: 20),
                  _SectionCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.location_on_outlined),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'الموقع',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 4),
                              Text(property.address!),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (property.areaM2 != null ||
                    property.areaValue != null ||
                    property.bedrooms != null ||
                    property.bathrooms != null ||
                    property.hasParking != null ||
                    property.buildingFacade != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    'مواصفات العقار',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      if (property.areaValue != null)
                        _SpecItem(
                          icon: Icons.square_foot,
                          value:
                              '${formatPropertyAreaValue(property.areaValue!)} ${propertyAreaUnitLabel(property.areaUnit)}',
                          label: 'المساحة',
                        )
                      else if (property.areaM2 != null)
                        _SpecItem(
                          icon: Icons.square_foot,
                          value: '${property.areaM2} م²',
                          label: 'المساحة',
                        ),
                      if (property.bedrooms != null)
                        _SpecItem(
                          icon: Icons.bed_outlined,
                          value: '${property.bedrooms}',
                          label: 'غرف النوم',
                        ),
                      if (property.bathrooms != null)
                        _SpecItem(
                          icon: Icons.bathtub_outlined,
                          value: '${property.bathrooms}',
                          label: 'الحمامات',
                        ),
                      if (property.hasParking != null)
                        _SpecItem(
                          icon: Icons.local_parking_outlined,
                          value: property.hasParking! ? 'يوجد' : 'لا يوجد',
                          label: 'موقف سيارة',
                        ),
                      if (property.buildingFacade != null)
                        _SpecItem(
                          icon: Icons.explore_outlined,
                          value: propertyFacadeLabel(property.buildingFacade),
                          label: 'واجهة البناء',
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 22),
                Text(
                  'وصف العقار',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 8),
                _SectionCard(
                  child: Text(
                    property.description ??
                        'لم يضف المعلن وصفاً تفصيلياً لهذا العقار بعد.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          height: 1.7,
                        ),
                  ),
                ),
                if (property.status == 'published' && !property.isOwner) ...[
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => BookingRequestSheet.showForProperty(
                      context,
                      propertyId: property.id,
                      title: property.title,
                    ),
                    icon: const Icon(Icons.event_available_outlined),
                    label: const Text('طلب موعد معاينة'),
                  ),
                ],
                if (property.status == 'published' &&
                    property.advertiser != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    'المجتمع والثقة',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 10),
                  _SectionCard(
                    child: Column(
                      children: [
                        if (property.advertiser!.verificationStatus == 'approved') ...[
                          Row(
                            children: [
                              const Icon(Icons.verified_outlined),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      property.advertiser!.verificationLabel,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                      ),
                                    ),
                                    Text(property.advertiser!.name),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (property.advertiser!
                              .verificationFlag('identity_reviewed'))
                            const _VerificationLine('الهوية تمت مراجعتها'),
                          if (property.advertiser!
                              .verificationFlag('relationship_document_reviewed'))
                            const _VerificationLine(
                                'مستند العلاقة بالعقار تمت مراجعته'),
                          if (property.advertiser!
                              .verificationFlag('professional_document_reviewed'))
                            const _VerificationLine(
                                'الوثيقة المهنية تمت مراجعتها'),
                          if (property.advertiser!
                              .verificationFlag('commercial_register_reviewed'))
                            const _VerificationLine(
                                'السجل التجاري تمت مراجعته'),
                          if (property.advertiser!
                              .verificationFlag('office_documents_reviewed'))
                            const _VerificationLine(
                                'مستندات المكتب المهنية تمت مراجعتها'),
                          if (property.advertiser!
                              .verificationFlag('office_location_registered'))
                            const _VerificationLine('موقع المكتب مسجل'),
                          const Divider(height: 24),
                        ],
                        Row(
                          children: [
                            const Icon(Icons.star_outline),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                property.advertiser!.ratingCount == 0
                                    ? 'لا توجد تقييمات للمعلن بعد'
                                    : 'تقييم ${property.advertiser!.name}: '
                                        '${property.advertiser!.ratingAverage.toStringAsFixed(1)} / 5 '
                                        '(${property.advertiser!.ratingCount})',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.forum_outlined),
                            const SizedBox(width: 10),
                            Text('${property.commentsCount} تعليق ظاهر'),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonalIcon(
                            onPressed: () => _openCommunity(property),
                            icon: const Icon(Icons.rate_review_outlined),
                            label:
                                const Text('التعليقات وتقييم المعلن والبلاغات'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (property.status == 'published' && !property.isOwner) ...[
                  const SizedBox(height: 20),
                  Text(
                    'التواصل مع المعلن',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 10),
                  _SectionCard(
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _startingConversation
                                ? null
                                : () => _startConversation(property),
                            icon: _startingConversation
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.forum_outlined),
                            label: Text(
                              _startingConversation
                                  ? 'جارٍ فتح المحادثة...'
                                  : 'مراسلة المعلن داخل التطبيق',
                            ),
                          ),
                        ),
                        if (property.contactPhone != null ||
                            property.contactWhatsapp != null)
                          const Divider(height: 28),
                        if (property.contactPhone != null)
                          _ContactRow(
                            icon: Icons.phone_outlined,
                            label: 'الهاتف',
                            value: property.contactPhone!,
                            onCopy: () => _copyContact(property.contactPhone!),
                          ),
                        if (property.contactPhone != null &&
                            property.contactWhatsapp != null)
                          const Divider(),
                        if (property.contactWhatsapp != null)
                          _ContactRow(
                            icon: Icons.chat_outlined,
                            label: 'واتساب',
                            value: property.contactWhatsapp!,
                            onCopy: () =>
                                _copyContact(property.contactWhatsapp!),
                          ),
                      ],
                    ),
                  ),
                ],
                if (property.similar.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(
                    'عقارات مشابهة',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 205,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: property.similar.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, index) => _SimilarCard(
                        property: property.similar[index],
                        onTap: () =>
                            Navigator.of(context).pushReplacement<void, void>(
                          MaterialPageRoute<void>(
                            builder: (_) => PropertyDetailsScreen(
                              propertyId: property.similar[index].id,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGallery(PropertyDetails property) {
    final images = property.images;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: 270,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (images.isEmpty)
              const _ImageFallback()
            else
              PageView.builder(
                itemCount: images.length,
                onPageChanged: (index) => setState(() => _imageIndex = index),
                itemBuilder: (context, index) => Image.network(
                  images[index].url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const _ImageFallback(),
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) {
                      return child;
                    }
                    return const _ImageFallback(showLoader: true);
                  },
                ),
              ),
            if (images.isNotEmpty)
              PositionedDirectional(
                bottom: 12,
                end: 12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0x99000000),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text(
                      '${_imageIndex + 1}/${images.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCommunity(PropertyDetails property) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ListingCommunityScreen(
          propertyId: property.id,
          advertiserId: property.advertiser!.id,
          advertiserName: property.advertiser!.name,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    ref.invalidate(propertyDetailsProvider(widget.propertyId));
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
    if (_startingConversation) {
      return;
    }

    setState(() => _startingConversation = true);
    try {
      final thread = await ref
          .read(messageRepositoryProvider)
          .startForProperty(property.id);
      ref.read(messageDataRevisionProvider.notifier).state++;
      if (!mounted) {
        return;
      }
      await context.push('/messages/${thread.id}');
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyApiError(error))),
      );
    } finally {
      if (mounted) {
        setState(() => _startingConversation = false);
      }
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
      }
      return;
    }

    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('حذف الإعلان؟'),
              content: const Text(
                  'لا يمكن التراجع عن حذف الإعلان بعد تأكيد العملية.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('حذف'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed || !mounted) {
        return;
      }

      try {
        await ref.read(propertyRepositoryProvider).deleteListing(property.id);
        ref.read(propertyDataRevisionProvider.notifier).state++;
        if (mounted) {
          Navigator.of(context).pop();
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyApiError(error))),
          );
        }
      }
    }
  }

  Future<void> _copyContact(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ الرقم.')),
    );
  }
}

class _VerificationLine extends StatelessWidget {
  const _VerificationLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            const Icon(Icons.check_circle, size: 18),
            const SizedBox(width: 6),
            Expanded(child: Text(text)),
          ],
        ),
      );
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onCopy,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF00796B)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        IconButton(
          tooltip: 'نسخ',
          onPressed: onCopy,
          icon: const Icon(Icons.copy_outlined),
        ),
      ],
    );
  }
}

class _SimilarCard extends StatelessWidget {
  const _SimilarCard({required this.property, required this.onTap});

  final PropertySummary property;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 110,
                width: double.infinity,
                child: property.mainImage == null
                    ? const ColoredBox(
                        color: Color(0xFFE7F5F1),
                        child: Icon(Icons.home_work_outlined, size: 42),
                      )
                    : Image.network(
                        property.mainImage!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const ColoredBox(
                          color: Color(0xFFE7F5F1),
                          child: Icon(Icons.home_work_outlined, size: 42),
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      property.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${_formatPrice(property.price)} ${property.currency}',
                      style: const TextStyle(
                        color: Color(0xFF00796B),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 54),
            const SizedBox(height: 12),
            const Text('تعذر تحميل تفاصيل العقار'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback({this.showLoader = false});

  final bool showLoader;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFE2F4F1),
      child: Center(
        child: showLoader
            ? const CircularProgressIndicator()
            : const Icon(
                Icons.home_work_outlined,
                size: 72,
                color: Color(0xFF00796B),
              ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      side: BorderSide.none,
      backgroundColor: const Color(0xFFE2F4F1),
    );
  }
}

class _SpecItem extends StatelessWidget {
  const _SpecItem(
      {required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 110,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E9E8)),
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF00796B)),
          const SizedBox(height: 7),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E9E8)),
      ),
      child: child,
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
      _ => value,
    };

String _formatPrice(double value) {
  final digits = value.round().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    final remaining = digits.length - index;
    buffer.write(digits[index]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write(',');
    }
  }
  return buffer.toString();
}

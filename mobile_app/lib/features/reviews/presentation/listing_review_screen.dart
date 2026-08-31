import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../account/data/auth_controller.dart';
import '../../properties/domain/property_field_options.dart';
import '../data/listing_review_repository.dart';
import '../domain/listing_review_models.dart';

final reviewQueueProvider =
    FutureProvider.autoDispose<List<ReviewListingItem>>((ref) {
  return ref.watch(listingReviewRepositoryProvider).queue();
});
final publicationBlocksProvider =
    FutureProvider.autoDispose<List<PublicationBlockItem>>((ref) {
  return ref.watch(listingReviewRepositoryProvider).blocks();
});

class ListingReviewScreen extends ConsumerWidget {
  const ListingReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).asData?.value;
    final canLift = user?.hasPermission('listings.manage_blocks') ?? false;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('مراجعة الإعلانات والعقارات'),
            bottom: const TabBar(
              tabs: [Tab(text: 'قائمة المراجعة'), Tab(text: 'حظر النشر')],
            ),
          ),
          body: TabBarView(
            children: [_Queue(), _Blocks(canLift: canLift)],
          ),
        ),
      ),
    );
  }
}

class _Queue extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(reviewQueueProvider);
    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Center(
        child: FilledButton(
          onPressed: () => ref.invalidate(reviewQueueProvider),
          child: const Text('إعادة المحاولة'),
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const Center(child: Text('لا توجد إعلانات بانتظار المراجعة.'));
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(reviewQueueProvider);
            await ref.read(reviewQueueProvider.future);
          },
          child: ListView.separated(
            padding: const EdgeInsets.all(14),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, index) => _ReviewCard(item: items[index]),
          ),
        );
      },
    );
  }
}

class _ReviewCard extends ConsumerWidget {
  const _ReviewCard({required this.item});
  final ReviewListingItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.title,
                style:
                    const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            Text('المعلن: ${item.ownerName}'),
            Text('نوع الحساب: ${_verificationType(item.ownerVerificationType)} • التحقق: ${_verificationStatus(item.ownerVerificationStatus)}'),
            Text(
              'الحالة: ${_status(item.reviewStatus)} • مستندات الإثبات: ${item.proofCount}',
            ),
            if (item.tenureType != null)
              Text('نوع الملكية: ${item.tenureType == 'waqf' ? 'وقف' : 'حر'}'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => _ReviewDetailsDialog(listingId: item.id),
                  ),
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('عرض التفاصيل والأدلة'),
                ),
                if (item.reviewStatus == 'submitted')
                  FilledButton.tonal(
                    onPressed: () => _run(
                      context,
                      ref,
                      () => ref
                          .read(listingReviewRepositoryProvider)
                          .start(item.id),
                    ),
                    child: const Text('بدء المراجعة'),
                  ),
                FilledButton(
                  onPressed: () => _run(
                    context,
                    ref,
                    () => ref
                        .read(listingReviewRepositoryProvider)
                        .approve(item.id),
                  ),
                  child: const Text('قبول ونشر'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    final reason =
                        await _reason(context, 'سبب الإرجاع للتصحيح');
                    if (reason == null || !context.mounted) {
                      return;
                    }
                    await _run(
                      context,
                      ref,
                      () => ref
                          .read(listingReviewRepositoryProvider)
                          .returnForCorrection(item.id, reason),
                    );
                  },
                  child: const Text('إرجاع للتصحيح'),
                ),
                FilledButton.tonal(
                  onPressed: () async {
                    final reason =
                        await _reason(context, 'سبب الرفض النهائي والحظر');
                    if (reason == null || !context.mounted) {
                      return;
                    }
                    await _run(
                      context,
                      ref,
                      () => ref
                          .read(listingReviewRepositoryProvider)
                          .rejectFinal(item.id, reason),
                    );
                  },
                  child: const Text('رفض نهائي وحظر'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
  ) async {
    try {
      await action();
      ref.invalidate(reviewQueueProvider);
      ref.invalidate(publicationBlocksProvider);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(error))),
        );
      }
    }
  }
}

class _ReviewDetailsDialog extends ConsumerWidget {
  const _ReviewDetailsDialog({required this.listingId});
  final int listingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dialog(
      insetPadding: const EdgeInsets.all(14),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
        child: FutureBuilder<ReviewListingDetail>(
          future: ref.read(listingReviewRepositoryProvider).detail(listingId),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('تعذر تحميل تفاصيل الإعلان.'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('إغلاق'),
                    ),
                  ],
                ),
              );
            }
            final item = snapshot.data!;
            return Column(
              children: [
                ListTile(
                  title: Text(item.title,
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text('الحالة: ${_status(item.reviewStatus)}'),
                  trailing: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text('المعلن: ${item.ownerName}'),
                      Text('نوع الحساب: ${_verificationType(item.ownerVerificationType)}'),
                      Text('حالة التحقق: ${_verificationStatus(item.ownerVerificationStatus)}'),
                      if (item.ownerIdentityReviewed)
                        const Text('✓ الهوية تمت مراجعتها'),
                      Text('البريد: ${item.ownerEmail}'),
                      Text('الهاتف: ${item.ownerPhone}'),
                      Text(
                          'الغرض: ${item.purpose == 'sale' ? 'بيع' : 'إيجار'}'),
                      Text('النوع: ${item.type}'),
                      if (item.tenureType != null)
                        Text('نوع الملكية: ${item.tenureType == 'waqf' ? 'وقف' : 'حر'}'),
                      Text('السعر: ${item.price.toStringAsFixed(0)}'),
                      Text('العنوان: ${item.address}'),
                      Text(
                        'الموقع: ${item.latitude.toStringAsFixed(6)}, ${item.longitude.toStringAsFixed(6)}',
                      ),
                      if (item.areaValue != null || item.areaM2 != null)
                        Text(
                          'المساحة: ${formatPropertyAreaValue(item.areaValue ?? item.areaM2!.toDouble())} ${propertyAreaUnitLabel(item.areaUnit ?? 'sqm')}',
                        ),
                      if (item.bedrooms != null)
                        Text('غرف النوم: ${item.bedrooms}'),
                      if (item.bathrooms != null)
                        Text('دورات المياه: ${item.bathrooms}'),
                      if (item.hasParking != null)
                        Text(
                            'موقف سيارة: ${item.hasParking! ? 'يوجد' : 'لا يوجد'}'),
                      if (item.buildingFacade != null)
                        Text(
                            'واجهة البناء: ${propertyFacadeLabel(item.buildingFacade)}'),
                      if (item.description.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(item.description),
                      ],
                      if (item.reason != null) ...[
                        const SizedBox(height: 8),
                        Text('آخر ملاحظة مراجعة: ${item.reason}'),
                      ],
                      if (item.ownerVerificationType == 'owner') ...[
                        const SizedBox(height: 16),
                        const Text('علاقة المالك بهذا العقار',
                            style: TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 6),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('نوع المستند: ${_ownershipDocumentType(item.ownershipDocumentType)}'),
                                Text('الاسم في المستند: ${item.documentOwnerName ?? '-'}'),
                                Text('صفة صاحب الحساب: ${_relationshipType(item.ownerRelationshipType)}'),
                                if (item.ownerRelationshipNote != null)
                                  Text('التوضيح: ${item.ownerRelationshipNote}'),
                                Text(item.ownershipDocumentPresent
                                    ? '✓ مستند العلاقة بالعقار مرفوع'
                                    : '✗ مستند العلاقة بالعقار غير موجود'),
                                if (item.ownerNameMatchesDocument != null)
                                  Text(item.ownerNameMatchesDocument!
                                      ? '✓ الاسم المدخل يطابق اسم الحساب'
                                      : 'تنبيه: الاسم المدخل لا يطابق اسم الحساب؛ يجب مراجعة الصفة والتفويض/الإرث/الشراكة.'),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      Text('صور الإعلان (${item.images.length})',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      if (item.images.isEmpty)
                        const Text('لا توجد صور.')
                      else
                        ...item.images.map(
                          (media) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _ProtectedReviewImage(url: media.url),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Text('مستندات الإثبات (${item.proofDocuments.length})',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      if (item.proofDocuments.isEmpty)
                        const Text('لا توجد مستندات إثبات.')
                      else
                        ...item.proofDocuments.map(
                          (media) => Card(
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(_proofDocumentLabel(media),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800)),
                                  if (media.name != null)
                                    Text(media.name!,
                                        style: const TextStyle(
                                            color: Colors.black54)),
                                  const SizedBox(height: 8),
                                  _ProtectedReviewImage(url: media.url),
                                ],
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      Text('سجل المراجعات (${item.reviewHistory.length})',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      if (item.reviewHistory.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text('لا توجد مراجعات سابقة.'),
                        )
                      else
                        ...item.reviewHistory.map(
                          (entry) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.history),
                            title: Text(entry.action),
                            subtitle: Text([
                              if (entry.actorName != null) entry.actorName!,
                              if (entry.fromStatus != null ||
                                  entry.toStatus != null)
                                '${entry.fromStatus ?? '-'} ← ${entry.toStatus ?? '-'}',
                              if (entry.reason != null) entry.reason!,
                              if (entry.createdAt != null)
                                entry.createdAt!.toLocal().toString(),
                            ].join('\n')),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

String _verificationType(String? value) => switch (value) {
      'owner' => 'مالك',
      'broker' => 'دلال',
      'office' => 'مكتب عقارات',
      _ => 'حساب أساسي',
    };

String _verificationStatus(String value) => switch (value) {
      'approved' => 'موثق',
      'pending' => 'قيد المراجعة',
      'needs_more_info' => 'يحتاج معلومات إضافية',
      'rejected' => 'مرفوض',
      _ => 'غير موثق',
    };

String _ownershipDocumentType(String? value) => switch (value) {
      'purchase_deed' => 'بصيرة شراء',
      'registry_record' => 'سند / قيد سجل عقاري',
      'partition_deed' => 'فصل قسمة',
      'court_judgment' => 'حكم قضائي',
      'inheritance_document' => 'مستند إرث',
      'ownership_contract' => 'عقد تمليك',
      'other' => 'مستند آخر',
      _ => '-',
    };

String _relationshipType(String? value) => switch (value) {
      'owner' => 'مالك مباشر',
      'agent' => 'وكيل',
      'heir' => 'وارث',
      'co_owner' => 'شريك في الملكية',
      'other' => 'صفة أخرى',
      _ => '-',
    };

String _proofDocumentLabel(ReviewMediaItem media) {
  return switch (media.kind) {
    'owner_id_front' => 'صورة البطاقة الأمامية',
    'owner_id_back' => 'صورة البطاقة الخلفية',
    'owner_selfie' => 'صورة سلفي لصاحب العقار',
    'ownership_proof' => 'إثبات ملكية العقار',
    'ownership_or_authorization' => 'إثبات ملكية أو تفويض (قديم)',
    _ => 'مستند إثبات',
  };
}

class _ProtectedReviewImage extends ConsumerWidget {
  const _ProtectedReviewImage({required this.url});
  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: ref.read(listingReviewRepositoryProvider).protectedImage(url),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return const SizedBox(
            height: 100,
            child: Center(child: Text('تعذر عرض الصورة.')),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(
            snapshot.data!,
            height: 220,
            fit: BoxFit.contain,
          ),
        );
      },
    );
  }
}

class _Blocks extends ConsumerWidget {
  const _Blocks({required this.canLift});
  final bool canLift;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(publicationBlocksProvider);
    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Center(
        child: FilledButton(
          onPressed: () => ref.invalidate(publicationBlocksProvider),
          child: const Text('إعادة المحاولة'),
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const Center(child: Text('لا توجد عقارات محظورة حالياً.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(14),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final block = items[index];
            return Card(
              child: ListTile(
                title: Text(
                  'العقار #${block.propertyAssetId} • ${block.purpose == 'sale' ? 'بيع' : 'إيجار'}',
                ),
                subtitle: Text(block.reason),
                trailing: canLift
                    ? TextButton(
                        onPressed: () async {
                          final reason =
                              await _reason(context, 'سبب رفع الحظر');
                          if (reason == null || !context.mounted) {
                            return;
                          }
                          try {
                            await ref
                                .read(listingReviewRepositoryProvider)
                                .liftBlock(block.id, reason);
                            ref.invalidate(publicationBlocksProvider);
                          } catch (error) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(friendlyApiError(error)),
                                ),
                              );
                            }
                          }
                        },
                        child: const Text('رفع الحظر'),
                      )
                    : null,
              ),
            );
          },
        );
      },
    );
  }
}

Future<String?> _reason(BuildContext context, String title) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        maxLines: 4,
        decoration: const InputDecoration(border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
          child: const Text('تأكيد'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (result == null || result.trim().isEmpty) {
    return null;
  }
  return result.trim();
}

String _status(String status) => switch (status) {
      'submitted' => 'مرفوع للدعم',
      'under_review' => 'قيد المراجعة',
      'returned_for_correction' => 'مُعاد للتصحيح',
      'approved' => 'مقبول',
      'rejected_blocked' => 'مرفوض ومحظور',
      _ => status,
    };

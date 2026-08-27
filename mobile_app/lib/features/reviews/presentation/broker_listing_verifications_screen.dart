import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../properties/domain/property_field_options.dart';
import '../data/listing_review_repository.dart';
import '../domain/listing_review_models.dart';

final brokerVerificationQueueProvider =
    FutureProvider.autoDispose<List<BrokerVerificationQueueItem>>((ref) {
  return ref.watch(listingReviewRepositoryProvider).brokerVerifications();
});

class BrokerListingVerificationsScreen extends ConsumerWidget {
  const BrokerListingVerificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(brokerVerificationQueueProvider);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('طلبات تحقق العقارات')),
        body: state.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(friendlyApiError(error), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () =>
                        ref.invalidate(brokerVerificationQueueProvider),
                    icon: const Icon(Icons.refresh),
                    label: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          ),
          data: (items) {
            if (items.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'لا توجد طلبات تحقق معلقة في مربعك حالياً.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(brokerVerificationQueueProvider);
                await ref.read(brokerVerificationQueueProvider.future);
              },
              child: ListView.separated(
                padding: const EdgeInsets.all(14),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) =>
                    _VerificationCard(item: items[index]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _VerificationCard extends ConsumerWidget {
  const _VerificationCard({required this.item});
  final BrokerVerificationQueueItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final area = item.areaValue ?? item.areaM2?.toDouble();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.listingTitle,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text('المربع: ${item.geoCellName ?? 'غير محدد'}'),
            Text('العنوان: ${item.address}'),
            Text('الغرض: ${item.purpose == 'sale' ? 'بيع' : 'إيجار'}'),
            if (area != null)
              Text(
                'المساحة: ${formatPropertyAreaValue(area)} ${propertyAreaUnitLabel(item.areaUnit ?? 'sqm')}',
              ),
            if (item.verification.requestNote != null) ...[
              const SizedBox(height: 8),
              Text('ملاحظة الدعم: ${item.verification.requestNote}'),
            ],
            const SizedBox(height: 10),
            const Text(
              'مهم: دورك هنا التحقق من حالة العقار فقط. لا تظهر لك مستندات إثبات الملكية ولا تملك اعتماد الإعلان أو نشره.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => _respond(context, ref, 'available'),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('العقار متاح'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _respond(context, ref, 'unavailable'),
                  icon: const Icon(Icons.block_outlined),
                  label: const Text('العقار غير متاح'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _respond(context, ref, 'unable_to_verify'),
                  icon: const Icon(Icons.help_outline),
                  label: const Text('لا أستطيع التأكد'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _respond(
      BuildContext context, WidgetRef ref, String status) async {
    String? note;
    if (status != 'available') {
      note = await _noteDialog(
        context,
        status == 'unavailable'
            ? 'وضح سبب أن العقار غير متاح'
            : 'اكتب ما يمنعك من التأكد',
      );
      if (note == null || !context.mounted) return;
    }
    try {
      await ref.read(listingReviewRepositoryProvider).respondBrokerVerification(
            item.verification.id,
            status,
            note: note,
          );
      ref.invalidate(brokerVerificationQueueProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال نتيجة التحقق إلى الدعم.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(error))),
        );
      }
    }
  }
}

Future<String?> _noteDialog(BuildContext context, String title) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        maxLines: 4,
        decoration: const InputDecoration(
          hintText: 'اكتب ملاحظة واضحة للدعم',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
          child: const Text('إرسال'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (result == null || result.trim().isEmpty) return null;
  return result.trim();
}

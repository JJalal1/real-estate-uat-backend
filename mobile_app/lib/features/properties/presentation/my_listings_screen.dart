import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/platform/stage5_media_picker.dart';
import '../data/property_repository.dart';
import '../domain/property_details.dart';
import 'add_property_wizard_screen.dart';

final myListingsProvider =
    FutureProvider.autoDispose<List<PropertyDetails>>((ref) async {
  ref.watch(propertyDataRevisionProvider);
  return ref.watch(propertyRepositoryProvider).myListings();
});

class MyListingsScreen extends ConsumerWidget {
  const MyListingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listings = ref.watch(myListingsProvider);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('إعلاناتي'), centerTitle: true),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            await Navigator.of(context).push<void>(MaterialPageRoute<void>(
                builder: (_) => const AddPropertyWizardScreen()));
            ref.invalidate(myListingsProvider);
          },
          icon: const Icon(Icons.add_home_work_outlined),
          label: const Text('إضافة عقار'),
        ),
        body: listings.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(
              child: FilledButton.icon(
                  onPressed: () => ref.invalidate(myListingsProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'))),
          data: (items) => items.isEmpty
              ? const Center(child: Text('لم تضف أي إعلان بعد.'))
              : RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(myListingsProvider);
                    await ref.read(myListingsProvider.future);
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return _ListingCard(
                        property: item,
                        onEdit: item.canEdit
                            ? () => _edit(context, ref, item)
                            : null,
                        onProof: item.canEdit
                            ? () => _addProof(context, ref, item)
                            : null,
                        onSubmit: item.canSubmit
                            ? () => _submit(context, ref, item)
                            : null,
                        onDelete: () => _delete(context, ref, item),
                      );
                    },
                  ),
                ),
        ),
      ),
    );
  }

  Future<void> _edit(
      BuildContext context, WidgetRef ref, PropertyDetails item) async {
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
        builder: (_) => AddPropertyWizardScreen(existingProperty: item)));
    ref.invalidate(myListingsProvider);
  }

  Future<void> _addProof(
      BuildContext context, WidgetRef ref, PropertyDetails item) async {
    const picker = Stage5MediaPicker();
    try {
      final paths = await picker.pickImages();
      if (paths.isEmpty) {
        return;
      }
      await ref
          .read(propertyRepositoryProvider)
          .uploadProofDocuments(item.id, paths.take(5).toList());
      await picker.clearTemporaryFiles(paths);
      ref.read(propertyDataRevisionProvider.notifier).state++;
      ref.invalidate(myListingsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم رفع مستند الإثبات للمراجعة.')));
      }
    } on PlatformException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تعذر فتح معرض الصور.')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
    }
  }

  Future<void> _submit(
      BuildContext context, WidgetRef ref, PropertyDetails item) async {
    final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
                    title: const Text('إرسال للمراجعة؟'),
                    content: const Text(
                        'بعد الإرسال لن تستطيع تعديل الإعلان حتى يعيده الدعم للتصحيح أو يصدر قراراً.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('إلغاء')),
                      FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('إرسال'))
                    ])) ??
        false;
    if (!confirmed || !context.mounted) {
      return;
    }
    try {
      await ref.read(propertyRepositoryProvider).submitListing(item.id);
      ref.read(propertyDataRevisionProvider.notifier).state++;
      ref.invalidate(myListingsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم رفع الإعلان للدعم للمراجعة.')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
    }
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, PropertyDetails item) async {
    final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
                    title: const Text('حذف الإعلان؟'),
                    content: const Text(
                        'سيتم حذف سجل الإعلان وملفاته المرفوعة، بينما تبقى هوية العقار وقرارات الحظر محفوظة عند وجودها.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('إلغاء')),
                      FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('حذف'))
                    ])) ??
        false;
    if (!confirmed || !context.mounted) {
      return;
    }
    try {
      await ref.read(propertyRepositoryProvider).deleteListing(item.id);
      ref.read(propertyDataRevisionProvider.notifier).state++;
      ref.invalidate(myListingsProvider);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
    }
  }
}

class _ListingCard extends StatelessWidget {
  const _ListingCard(
      {required this.property,
      required this.onEdit,
      required this.onProof,
      required this.onSubmit,
      required this.onDelete});
  final PropertyDetails property;
  final VoidCallback? onEdit;
  final VoidCallback? onProof;
  final VoidCallback? onSubmit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: SizedBox(
                width: 64,
                height: 64,
                child: property.mainImage == null
                    ? const ColoredBox(
                        color: Color(0xFFE7F5F1),
                        child: Icon(Icons.home_work_outlined))
                    : Image.network(property.mainImage!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.home_work_outlined))),
            title: Text(property.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 4),
              Text('${_formatPrice(property.price)} ${property.currency}',
                  style: const TextStyle(
                      color: Color(0xFF00796B), fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              _StatusChip(status: property.reviewStatus),
              Text('مستندات الإثبات: ${property.proofDocumentCount}')
            ]),
          ),
          if (property.lastReviewReason != null)
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text('ملاحظة المراجعة: ${property.lastReviewReason}',
                        style: const TextStyle(color: Colors.deepOrange)))),
          const Divider(height: 1),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              if (onEdit != null)
                TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('تعديل')),
              if (onProof != null)
                TextButton.icon(
                    onPressed: onProof,
                    icon: const Icon(Icons.verified_user_outlined),
                    label: const Text('إثبات')),
              if (onSubmit != null)
                FilledButton.tonalIcon(
                    onPressed: onSubmit,
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('إرسال للمراجعة')),
              TextButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('حذف')),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      'draft' => 'مسودة',
      'submitted' => 'قيد المراجعة',
      'under_review' => 'قيد المراجعة',
      'returned_for_correction' => 'مُعاد للتصحيح',
      'approved' => 'مقبول ومنشور',
      'rejected_blocked' => 'مرفوض ومحظور',
      'legacy_rejected' => 'مرفوض قديم',
      _ => status,
    };
    return Chip(label: Text(label));
  }
}

String _formatPrice(double value) {
  final digits = value.round().toString();
  final output = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    final remaining = digits.length - index;
    output.write(digits[index]);
    if (remaining > 1 && remaining % 3 == 1) {
      output.write(',');
    }
  }
  return output.toString();
}

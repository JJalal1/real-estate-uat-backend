import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
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
        appBar: const AppAppBar(title: 'إعلاناتي'),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _create(context, ref),
          icon: const Icon(Icons.add_home_work_outlined),
          label: const Text('إضافة عقار'),
        ),
        body: listings.when(
          loading: () => const AppLoadingState(label: 'جارٍ تحميل إعلاناتك...'),
          error: (error, _) => AppErrorState(
            message: friendlyApiError(error),
            onRetry: () => ref.invalidate(myListingsProvider),
          ),
          data: (items) {
            if (items.isEmpty) {
              return AppEmptyState(
                title: 'لا توجد إعلانات بعد',
                message: 'ابدأ بإضافة عقار، احفظه كمسودة، ثم أرسله للمراجعة عندما يكتمل.',
                icon: Icons.inventory_2_outlined,
                actionLabel: 'إضافة عقار',
                onAction: () => _create(context, ref),
              );
            }

            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(myListingsProvider);
                await ref.read(myListingsProvider.future);
              },
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppLayout.compactPageGutter,
                  AppSpacing.s12,
                  AppLayout.compactPageGutter,
                  112,
                ),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.s12),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _ListingCard(
                    property: item,
                    onOpen: () => context.push('/properties/${item.id}'),
                    onEdit: item.canEdit ? () => _edit(context, ref, item) : null,
                    onSubmit: item.canSubmit
                        ? () => _submit(context, ref, item)
                        : null,
                    onDelete: item.canEdit
                        ? () => _delete(context, ref, item)
                        : null,
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const AddPropertyWizardScreen()),
    );
    ref.invalidate(myListingsProvider);
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    PropertyDetails item,
  ) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AddPropertyWizardScreen(existingProperty: item),
      ),
    );
    ref.invalidate(myListingsProvider);
  }

  Future<void> _submit(
    BuildContext context,
    WidgetRef ref,
    PropertyDetails item,
  ) async {
    final confirmed = await AppDialog.show<bool>(
          context,
          title: item.reviewStatus == 'returned_for_correction'
              ? 'إعادة إرسال الإعلان؟'
              : 'إرسال الإعلان للمراجعة؟',
          content: Text(
            item.reviewStatus == 'returned_for_correction'
                ? 'تأكد أنك عالجت ملاحظة فريق الدعم. سيعود نفس الإعلان إلى قائمة المراجعة.'
                : 'بعد الإرسال لن تستطيع تعديل الإعلان أثناء المراجعة. يمكنك حفظه كمسودة حتى يصبح جاهزاً.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                item.reviewStatus == 'returned_for_correction'
                    ? 'إعادة الإرسال'
                    : 'إرسال',
              ),
            ),
          ],
        ) ??
        false;
    if (!confirmed || !context.mounted) return;

    try {
      await ref.read(propertyRepositoryProvider).submitListing(item.id);
      ref.read(propertyDataRevisionProvider.notifier).state++;
      ref.invalidate(myListingsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال الإعلان لفريق المراجعة.')),
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

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    PropertyDetails item,
  ) async {
    final confirmed = await AppDialog.show<bool>(
          context,
          title: 'حذف الإعلان؟',
          content: const Text(
            'سيتم حذف الإعلان وملفاته. لا يمكن حذف إعلان أثناء المراجعة أو بعد رفض نهائي محظور.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف'),
            ),
          ],
        ) ??
        false;
    if (!confirmed || !context.mounted) return;

    try {
      await ref.read(propertyRepositoryProvider).deleteListing(item.id);
      ref.read(propertyDataRevisionProvider.notifier).state++;
      ref.invalidate(myListingsProvider);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(error))),
        );
      }
    }
  }
}

class _ListingCard extends StatelessWidget {
  const _ListingCard({
    required this.property,
    required this.onOpen,
    required this.onEdit,
    required this.onSubmit,
    required this.onDelete,
  });

  final PropertyDetails property;
  final VoidCallback onOpen;
  final VoidCallback? onEdit;
  final VoidCallback? onSubmit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final state = _listingState(property.reviewStatus);

    return AppSurface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsetsDirectional.all(AppLayout.surfacePadding),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.control),
                    child: SizedBox.square(
                      dimension: 76,
                      child: property.mainImage == null
                          ? ColoredBox(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              child: const Icon(Icons.home_work_outlined),
                            )
                          : Image.network(
                              property.mainImage!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Center(
                                child: Icon(Icons.home_work_outlined),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          property.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.s4),
                        Text(
                          '${_formatPrice(property.price)} ${property.currency}',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                        const SizedBox(height: AppSpacing.s8),
                        AppStatusBadge(
                          label: state.$1,
                          tone: state.$2,
                        ),
                        const SizedBox(height: AppSpacing.s4),
                        Text(
                          'مستندات الإثبات: ${property.proofDocumentCount}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (property.reviewStatus == 'returned_for_correction' &&
              property.lastReviewReason != null)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppLayout.surfacePadding,
                0,
                AppLayout.surfacePadding,
                AppSpacing.s12,
              ),
              child: AppInlineMessage(
                title: 'ملاحظة فريق المراجعة',
                message: property.lastReviewReason!,
                tone: AppStatusTone.warning,
              ),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsetsDirectional.all(AppSpacing.s8),
            child: Wrap(
              spacing: AppSpacing.s4,
              runSpacing: AppSpacing.s4,
              alignment: WrapAlignment.start,
              children: [
                TextButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('عرض'),
                ),
                if (onEdit != null)
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(
                      property.reviewStatus == 'returned_for_correction'
                          ? 'تصحيح الإعلان'
                          : 'تعديل',
                    ),
                  ),
                if (onSubmit != null)
                  FilledButton.tonalIcon(
                    onPressed: onSubmit,
                    icon: const Icon(Icons.send_outlined),
                    label: Text(
                      property.reviewStatus == 'returned_for_correction'
                          ? 'إعادة الإرسال'
                          : 'إرسال للمراجعة',
                    ),
                  ),
                if (onDelete != null)
                  TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('حذف'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

(String, AppStatusTone) _listingState(String status) => switch (status) {
      'draft' => ('مسودة', AppStatusTone.neutral),
      'submitted' => ('بانتظار المراجعة', AppStatusTone.info),
      'under_review' => ('تحت المراجعة', AppStatusTone.info),
      'returned_for_correction' => ('يحتاج تصحيح', AppStatusTone.warning),
      'approved' => ('منشور', AppStatusTone.success),
      'rejected_blocked' => ('مرفوض', AppStatusTone.error),
      'legacy_rejected' => ('مرفوض سابقاً', AppStatusTone.error),
      _ => (status, AppStatusTone.neutral),
    };

String _formatPrice(double value) {
  final digits = value.round().toString();
  final output = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    final remaining = digits.length - index;
    output.write(digits[index]);
    if (remaining > 1 && remaining % 3 == 1) output.write(',');
  }
  return output.toString();
}

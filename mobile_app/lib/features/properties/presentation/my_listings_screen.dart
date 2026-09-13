import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../../financial/data/financial_repository.dart';
import '../data/property_repository.dart';
import '../domain/property_details.dart';
import 'add_property_wizard_screen.dart';
import 'property_sai_configuration_sheet.dart';

final myListingsProvider =
    FutureProvider.autoDispose<List<PropertyDetails>>((ref) async {
  ref.watch(propertyDataRevisionProvider);
  return ref.watch(propertyRepositoryProvider).myListings();
});

class MyListingsScreen extends ConsumerStatefulWidget {
  const MyListingsScreen({super.key});

  @override
  ConsumerState<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends ConsumerState<MyListingsScreen> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
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
          loading: () => const _MyListingsSkeleton(),
          error: (error, _) => AppErrorState(
            message: friendlyApiError(error),
            onRetry: () => ref.invalidate(myListingsProvider),
          ),
          data: (items) {
            if (items.isEmpty) {
              return AppEmptyState(
                title: 'لا توجد إعلانات بعد',
                message:
                    'ابدأ بإضافة عقار، احفظه كمسودة، ثم أرسله للمراجعة عندما يكتمل.',
                icon: Icons.inventory_2_outlined,
                actionLabel: 'إضافة عقار',
                onAction: () => _create(context, ref),
              );
            }

            final filtered = _applyFilter(items);
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(myListingsProvider);
                await ref.read(myListingsProvider.future);
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        AppLayout.compactPageGutter,
                        AppSpacing.s12,
                        AppLayout.compactPageGutter,
                        0,
                      ),
                      child: _ListingsOverview(items: items),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        AppLayout.compactPageGutter,
                        AppSpacing.s16,
                        AppLayout.compactPageGutter,
                        AppSpacing.s8,
                      ),
                      child: _LifecycleFilterBar(
                        selected: _filter,
                        items: items,
                        onChanged: (value) => setState(() => _filter = value),
                      ),
                    ),
                  ),
                  if (filtered.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: AppEmptyState(
                        title: 'لا توجد إعلانات في هذه الحالة',
                        message: 'اختر حالة ثانية لعرض بقية إعلاناتك.',
                        icon: Icons.filter_alt_off_outlined,
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        AppLayout.compactPageGutter,
                        AppSpacing.s4,
                        AppLayout.compactPageGutter,
                        112,
                      ),
                      sliver: SliverList.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: AppSpacing.s12),
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          return _ListingCard(
                            property: item,
                            onOpen: () =>
                                context.push('/properties/${item.id}'),
                            onEdit: item.canEdit
                                ? () => _edit(context, ref, item)
                                : null,
                            onSubmit: item.canSubmit
                                ? () => _submit(context, ref, item)
                                : null,
                            onDelete: item.canEdit
                                ? () => _delete(context, ref, item)
                                : null,
                            onAttest: item.saiAttestationRequired
                                ? () => _attestSai(context, ref, item)
                                : null,
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  List<PropertyDetails> _applyFilter(List<PropertyDetails> items) {
    return switch (_filter) {
      'action' => items.where(_needsAction).toList(growable: false),
      'review' => items.where(_inReview).toList(growable: false),
      'published' => items
          .where((item) => item.reviewStatus == 'approved')
          .toList(growable: false),
      _ => items,
    };
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
                ? 'تأكد أنك عالجت ملاحظة فريق الدعم. قبل إعادة الإرسال ستؤكد شروط السعي الإلزامية.'
                : 'قبل الإرسال ستؤكد شروط السعي والطرف الذي يتحمله. بعد الإرسال لن تستطيع تعديل الإعلان أثناء المراجعة.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('متابعة'),
            ),
          ],
        ) ??
        false;
    if (!confirmed || !context.mounted) return;

    final repository = ref.read(propertyRepositoryProvider);
    try {
      final saiReady = await showPropertySaiConfigurationSheet(
        context,
        repository: repository,
        propertyId: item.id,
        purpose: item.purpose,
      );
      if (!context.mounted) return;
      if (!saiReady) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'لم يتم إرسال الإعلان. يجب تأكيد شروط السعي المطلوبة أولاً.',
            ),
          ),
        );
        return;
      }

      await repository.submitListing(item.id);
      ref.read(propertyDataRevisionProvider.notifier).state++;
      ref.invalidate(myListingsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تأكيد السعي وإرسال الإعلان لفريق المراجعة.'),
          ),
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

  Future<void> _attestSai(
    BuildContext context,
    WidgetRef ref,
    PropertyDetails item,
  ) async {
    const oath =
        'أقسم بالله أنني إذا تمت الصفقة عن طريق المنصة فسأقوم بسداد مستحقات المنصة من السعي حسب الشروط التي وافقت عليها عند نشر الإعلان.';
    final confirmed = await AppDialog.show<bool>(
          context,
          title: 'إقرار السعي للإعلان المنشور',
          content: const Text(oath),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('ليس الآن')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('أقسم بذلك')),
          ],
        ) ??
        false;
    if (!confirmed || !context.mounted) return;
    try {
      await ref.read(financialRepositoryProvider).attestSai(item.id);
      ref.read(propertyDataRevisionProvider.notifier).state++;
      ref.invalidate(myListingsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تم تسجيل إقرار السعي لهذا الإعلان.')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
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

class _ListingsOverview extends StatelessWidget {
  const _ListingsOverview({required this.items});

  final List<PropertyDetails> items;

  @override
  Widget build(BuildContext context) {
    final action = items.where(_needsAction).length;
    final review = items.where(_inReview).length;
    final published =
        items.where((item) => item.reviewStatus == 'approved').length;
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ملخص إعلاناتك', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.s4),
          Text(
            action > 0
                ? 'عندك $action إعلان يحتاج إجراء منك الآن.'
                : 'كل الإعلانات تسير بدون إجراء مطلوب منك حاليًا.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: AppSpacing.s16),
          Row(
            children: [
              Expanded(
                child: _OverviewMetric(
                  icon: Icons.priority_high_rounded,
                  value: action,
                  label: 'تحتاج إجراء',
                  tone: action > 0
                      ? AppStatusTone.warning
                      : AppStatusTone.neutral,
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: _OverviewMetric(
                  icon: Icons.fact_check_outlined,
                  value: review,
                  label: 'قيد المراجعة',
                  tone: AppStatusTone.info,
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: _OverviewMetric(
                  icon: Icons.verified_outlined,
                  value: published,
                  label: 'منشورة',
                  tone: AppStatusTone.success,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({
    required this.icon,
    required this.value,
    required this.label,
    required this.tone,
  });

  final IconData icon;
  final int value;
  final String label;
  final AppStatusTone tone;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: AppSpacing.s4),
        Text(
          '$value',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: AppSpacing.s4),
        AppStatusBadge(label: label, tone: tone),
      ],
    );
  }
}

class _LifecycleFilterBar extends StatelessWidget {
  const _LifecycleFilterBar({
    required this.selected,
    required this.items,
    required this.onChanged,
  });

  final String selected;
  final List<PropertyDetails> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{
      'all': items.length,
      'action': items.where(_needsAction).length,
      'review': items.where(_inReview).length,
      'published':
          items.where((item) => item.reviewStatus == 'approved').length,
    };
    final labels = <String, String>{
      'all': 'الكل',
      'action': 'تحتاج إجراء',
      'review': 'قيد المراجعة',
      'published': 'منشورة',
    };
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.s8),
        itemBuilder: (context, index) {
          final key = labels.keys.elementAt(index);
          return ChoiceChip(
            selected: selected == key,
            label: Text('${labels[key]} (${counts[key]})'),
            onSelected: (_) => onChanged(key),
          );
        },
      ),
    );
  }
}

class _ListingCard extends StatelessWidget {
  const _ListingCard({
    required this.property,
    required this.onOpen,
    required this.onEdit,
    required this.onSubmit,
    required this.onDelete,
    required this.onAttest,
  });

  final PropertyDetails property;
  final VoidCallback onOpen;
  final VoidCallback? onEdit;
  final VoidCallback? onSubmit;
  final VoidCallback? onDelete;
  final VoidCallback? onAttest;

  @override
  Widget build(BuildContext context) {
    final state = _listingState(property.reviewStatus);
    final nextAction = _nextAction(property);

    return AppSurface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onOpen,
            child: Padding(
              padding:
                  const EdgeInsetsDirectional.all(AppLayout.surfacePadding),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.control),
                    child: SizedBox.square(
                      dimension: 82,
                      child: property.mainImage == null
                          ? ColoredBox(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
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
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: AppSpacing.s8),
                        Wrap(
                          spacing: AppSpacing.s8,
                          runSpacing: AppSpacing.s4,
                          children: [
                            AppStatusBadge(
                              label: state.$1,
                              tone: state.$2,
                            ),
                            AppStatusBadge(
                              label: '${property.proofDocumentCount} إثبات',
                              tone: AppStatusTone.neutral,
                              icon: Icons.description_outlined,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (nextAction != null)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppLayout.surfacePadding,
                0,
                AppLayout.surfacePadding,
                AppSpacing.s12,
              ),
              child: AppInlineMessage(
                title: nextAction.$1,
                message: nextAction.$2,
                tone: nextAction.$3,
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
                if (onAttest != null)
                  FilledButton.tonalIcon(
                    onPressed: onAttest,
                    icon: const Icon(Icons.verified_user_outlined),
                    label: const Text('إقرار السعي'),
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

class _MyListingsSkeleton extends StatelessWidget {
  const _MyListingsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsetsDirectional.all(AppLayout.compactPageGutter),
      children: const [
        AppSkeleton(height: 172, radius: AppRadii.card),
        SizedBox(height: AppSpacing.s16),
        AppSkeleton(height: 42),
        SizedBox(height: AppSpacing.s12),
        AppSkeleton(height: 190, radius: AppRadii.card),
        SizedBox(height: AppSpacing.s12),
        AppSkeleton(height: 190, radius: AppRadii.card),
      ],
    );
  }
}

bool _needsAction(PropertyDetails item) =>
    item.saiAttestationRequired ||
    item.reviewStatus == 'draft' ||
    item.reviewStatus == 'returned_for_correction';

bool _inReview(PropertyDetails item) =>
    item.reviewStatus == 'submitted' || item.reviewStatus == 'under_review';

(String, String, AppStatusTone)? _nextAction(PropertyDetails property) {
  if (property.saiAttestationRequired) {
    return (
      'مطلوب إقرار السعي',
      'الإعلان منشور. أكمل إقرار السعي المسجل على نفس نسخة الشروط.',
      AppStatusTone.warning
    );
  }
  return switch (property.reviewStatus) {
    'draft' => (
        'الخطوة التالية',
        'أكمل بيانات الإعلان والإثباتات ثم أرسله للمراجعة.',
        AppStatusTone.info,
      ),
    'returned_for_correction' => (
        'مطلوب منك إجراء',
        'صحح الملاحظة ثم أعد إرسال نفس الإعلان للمراجعة.',
        AppStatusTone.warning,
      ),
    'submitted' => (
        'بانتظار فريق المراجعة',
        'تم الاستلام ولا يوجد إجراء مطلوب منك الآن.',
        AppStatusTone.info,
      ),
    'under_review' => (
        'تحت المراجعة',
        'الفريق يراجع الإعلان حاليًا. لا تعدّل البيانات حتى انتهاء المراجعة.',
        AppStatusTone.info,
      ),
    'approved' => (
        'الإعلان منشور',
        'يمكن للباحثين العثور عليه والتواصل وطلب المعاينة.',
        AppStatusTone.success,
      ),
    _ => null,
  };
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

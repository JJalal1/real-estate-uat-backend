import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/ebroker_card_actions.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../../../router/app_deep_links.dart';
import '../../account/data/auth_controller.dart';
import '../../broker/presentation/broker_workspaces.dart';
import '../../financial/data/financial_repository.dart';
import '../data/my_listings_pages.dart';
import '../data/property_repository.dart';
import '../domain/property_details.dart';
import 'add_property_wizard_screen.dart';
import 'property_sai_configuration_sheet.dart';
import 'publish_listing.dart';
import 'property_summary_card.dart';

export '../data/my_listings_pages.dart';

final myListingsProvider =
    FutureProvider.autoDispose<List<PropertyDetails>>((ref) async {
  ref.watch(propertyDataRevisionProvider);
  ref.watch(authControllerProvider.select((state) => state.asData?.value?.id));
  return ref.watch(propertyRepositoryProvider).myListings();
});

class MyListingsScreen extends ConsumerStatefulWidget {
  const MyListingsScreen({this.initiallyShowCorrections = false, super.key});

  final bool initiallyShowCorrections;

  @override
  ConsumerState<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends ConsumerState<MyListingsScreen> {
  late _ListingFilter _filter = widget.initiallyShowCorrections
      ? _ListingFilter.rejected
      : _ListingFilter.all;
  late bool _onlyCorrections = widget.initiallyShowCorrections;
  final Set<int> _updating = {};

  Future<void> _updateListing(PropertyDetails item) async {
    if (_updating.contains(item.id)) return;
    setState(() => _updating.add(item.id));
    try {
      await showBrokerListingUpdate(context, ref, item);
    } finally {
      if (mounted) setState(() => _updating.remove(item.id));
    }
  }

  Future<void> _share(PropertyDetails item) async {
    await Clipboard.setData(ClipboardData(text: '${item.title}\n${propertyAppDeepLink(item.id)}'));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ رابط العقار للمشاركة.')));
  }

  @override
  Widget build(BuildContext context) {
    final listings = ref.watch(myListingsPagesProvider);
    final controller = ref.read(myListingsPagesProvider.notifier);
    final items = listings.items.where((item) => item.reviewStatus != 'draft')
        .toList(growable: false);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: const AppAppBar(title: 'عقاراتي'),
        floatingActionButton: items.isNotEmpty ? EbrokerButton(
          onPressed: () => _create(context, ref),
          icon: const EbrokerIcon(Icons.add_home_work_outlined),
          child: const Text('إضافة عقار'),
        ) : null,
        body: Column(children: [
          _LifecycleFilterBar(
            selected: _filter,
            onChanged: (filter) => setState(() {
              _filter = filter;
              _onlyCorrections = false;
            }),
            onDrafts: () => context.push('/add-property?drafts=1'),
          ),
          if (listings.page != null && (listings.loading || listings.error != null))
            AppRefreshStatus(loading: listings.loading,
              error: listings.error == null ? null : friendlyApiError(listings.error!),
              onRetry: controller.refresh),
          Expanded(child: _body(listings, controller, items)),
        ]),
      ),
    );
  }

  Widget _body(
    MyListingsPagesState listings,
    MyListingsPagesController controller,
    List<PropertyDetails> items,
  ) {
    if (listings.page == null) {
      if (listings.loading) return const _MyListingsSkeleton();
      if (listings.error != null) {
        return AppErrorState(message: friendlyApiError(listings.error!), onRetry: controller.refresh);
      }
    }
    final hasMore = listings.page?.hasMore ?? false;
    if (items.isEmpty && !hasMore) {
      return AppEmptyState(
        title: 'لا توجد إعلانات بعد',
        message: 'أضف عقارك واحفظه كمسودة أو انشره عندما تكتمل تفاصيله.',
        icon: Icons.inventory_2_outlined,
        actionLabel: 'إضافة عقار',
        onAction: () => _create(context, ref),
      );
    }

    final filtered = _applyFilter(items);
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: CustomScrollView(
        key: ValueKey((controller, _filter, _onlyCorrections)),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (filtered.isEmpty)
            SliverToBoxAdapter(
              child: AppEmptyState(
                title: hasMore ? 'لا توجد إعلانات مطابقة ضمن المحمّل حتى الآن'
                  : 'لا توجد إعلانات في هذه الحالة',
                message: hasMore ? 'حمّل المزيد لمتابعة بقية الإعلانات.'
                  : 'اختر حالة ثانية لعرض بقية إعلاناتك.',
                icon: Icons.filter_alt_off_outlined,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppLayout.compactPageGutter,
                AppSpacing.s4,
                AppLayout.compactPageGutter,
                AppSpacing.s12,
              ),
              sliver: SliverList.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.s12),
                itemBuilder: (context, index) {
                  final item = filtered[index];
                  return _ListingCard(
                    key: ValueKey('owner-listing-${item.id}'),
                    property: item,
                    showStatus: _filter == _ListingFilter.all,
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
                    onUpdate: _updating.contains(item.id) ? null : () => _updateListing(item),
                    onShare: () => _share(item),
                  );
                },
              ),
            ),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppLayout.compactPageGutter, AppSpacing.s12,
              AppLayout.compactPageGutter, 112),
            child: listings.loadingMore
              ? const AppRefreshStatus(loading: true)
              : listings.pageError != null
                ? AppRefreshStatus(
                    key: const ValueKey('my-listings-page-error'),
                    error: friendlyApiError(listings.pageError!),
                    onRetry: controller.loadMore)
                : hasMore ? AppButton(
                    key: const ValueKey('my-listings-more'),
                    label: 'تحميل المزيد',
                    onPressed: listings.loading || listings.error != null
                      ? null : controller.loadMore)
                  : const SizedBox.shrink(),
          )),
        ],
      ),
    );
  }

  void _reloadListings(WidgetRef ref) {
    ref.invalidate(myListingsProvider);
    ref.invalidate(myListingsPagesProvider);
  }

  List<PropertyDetails> _applyFilter(List<PropertyDetails> items) {
    if (_onlyCorrections) {
      return items.where(_needsCorrection).toList(growable: false);
    }
    return switch (_filter) {
      _ListingFilter.all => items,
      _ListingFilter.published => items.where(_published).toList(growable: false),
      _ListingFilter.review => items.where(_inReview).toList(growable: false),
      _ListingFilter.rejected => items
          .where((item) => _rejected(item) || _needsCorrection(item))
          .toList(growable: false),
    };
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    await context.push<void>('/add-property');
    if (mounted) _reloadListings(ref);
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
    if (mounted) _reloadListings(ref);
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
              : 'نشر الإعلان؟',
          content: Text(
            item.reviewStatus == 'returned_for_correction'
                ? 'تأكد أنك عالجت ملاحظة فريق الدعم. قبل إعادة الإرسال ستؤكد شروط السعي الإلزامية.'
                : 'راجع شروط السعي والطرف الذي يتحمله قبل نشر الإعلان.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            EbrokerFilledButton(
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
        basis: item.purpose == 'rent' ? (item.monthlyRent ?? item.editablePrice) : item.editablePrice,
        professionalAdvertiser: ref.read(authControllerProvider).asData?.value?.hasMarketplaceProfessionalProfile == true,
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

      final published = await publishListing(context, ref, item.id);
      if (!context.mounted) return;
      if (published == null) {
        await _edit(context, ref, item);
        return;
      }
      ref.read(propertyDataRevisionProvider.notifier).state++;
      _reloadListings(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(publicationMessage(published))),
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
    final oath = item.saiAttestationText ??
        'ألتزم بسداد مستحق المنصة من السعي عند إتمام صفقة جاءت من عميل عبر المنصة، وفق نسبة المنصة الموضحة.';
    final confirmed = await AppDialog.show<bool>(
          context,
          title: 'إقرار السعي للإعلان المنشور',
          content: Text(oath),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('ليس الآن')),
            EbrokerFilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('أوافق على الإقرار')),
          ],
        ) ??
        false;
    if (!confirmed || !context.mounted) return;
    try {
      await ref.read(financialRepositoryProvider).attestSai(item.id);
      ref.read(propertyDataRevisionProvider.notifier).state++;
      _reloadListings(ref);
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
            EbrokerFilledButton(
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
      _reloadListings(ref);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(error))),
        );
      }
    }
  }
}

enum _ListingFilter {
  all('الكل', 5),
  published('منشورة', 6),
  review('قيد المراجعة', 10),
  rejected('مرفوضة', 6);

  const _ListingFilter(this.label, this.flex);
  final String label;
  final int flex;
}

class _LifecycleFilterBar extends StatelessWidget {
  const _LifecycleFilterBar({
    required this.selected,
    required this.onChanged,
    required this.onDrafts,
  });

  final _ListingFilter selected;
  final ValueChanged<_ListingFilter> onChanged;
  final VoidCallback onDrafts;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 8, 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final labelScale = MediaQuery.textScalerOf(context).scale(12) / 12;
          final rowWidth = (304 * labelScale)
              .clamp(constraints.maxWidth, double.infinity)
              .toDouble();
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: rowWidth,
              child: Row(
                children: [
                  for (final filter in _ListingFilter.values) ...[
                    Expanded(
                      flex: filter.flex,
                      child: _ListingFilterChip(
                        key: ValueKey('my-listings-filter-${filter.name}'),
                        label: filter.label,
                        selected: selected == filter,
                        onTap: () => onChanged(filter),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    flex: 8,
                    child: _ListingFilterChip(
                      key: const ValueKey('my-saved-listing-drafts'),
                      label: 'مسوداتي',
                      icon: Icons.drafts_outlined,
                      onTap: onDrafts,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ListingFilterChip extends StatelessWidget {
  const _ListingFilterChip({
    required this.label,
    required this.onTap,
    this.selected = false,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = selected ? scheme.primary : scheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Center(
              child: Ink(
                decoration: BoxDecoration(
                  color: selected ? scheme.primaryContainer : scheme.surface,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  border: Border.all(
                    color: selected ? scheme.primary : scheme.outlineVariant,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: foreground,
                            fontSize: 12,
                          )),
                      if (icon != null) ...[
                        const SizedBox(width: 4),
                        Icon(icon, size: 14, color: foreground),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ListingCard extends StatelessWidget {
  const _ListingCard({
    required this.property,
    required this.showStatus,
    required this.onOpen,
    required this.onEdit,
    required this.onSubmit,
    required this.onDelete,
    required this.onAttest,
    this.onUpdate,
    this.onShare,
    super.key,
  });

  final PropertyDetails property;
  final bool showStatus;
  final VoidCallback onOpen;
  final VoidCallback? onEdit, onSubmit, onDelete, onAttest;
  final VoidCallback? onUpdate, onShare;

  List<EbrokerCardAction> _actions({required bool inlineEdit}) {
    final published = property.status == 'published';
    final availability = property.availabilityStatus;
    return [
      if (onSubmit != null)
        EbrokerCardAction(
          _needsCorrection(property) ? 'إعادة الإرسال' : 'نشر الإعلان',
          onSubmit,
          icon: Icons.send_outlined,
        ),
      if (onAttest != null)
        EbrokerCardAction('إقرار السعي', onAttest,
            icon: Icons.verified_user_outlined),
      if (canUpdateBrokerListing(property))
        EbrokerCardAction('تحديث حالة الإعلان', onUpdate, icon: Icons.update_rounded),
      if (published && availability == 'available')
        EbrokerCardAction('مشاركة', onShare, icon: Icons.share_outlined),
      if (onEdit != null && !inlineEdit)
        EbrokerCardAction('تعديل', onEdit, icon: Icons.edit_outlined),
      if (onDelete != null)
        EbrokerCardAction('حذف', onDelete, icon: Icons.delete_outline),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final state = showStatus ? _listingState(property) : null;
    final correction = _needsCorrection(property);
    final reviewIssue = correction || _rejected(property);
    final inlineEdit = reviewIssue && onEdit != null;
    final reason = reviewIssue ? property.lastReviewReason?.trim() : null;
    final actions = _actions(inlineEdit: inlineEdit);
    return ListingPropertyCard(
      property: property.toSummary(),
      price: property.price.toString(),
      onTap: onOpen,
      authenticatedImages: property.status != 'published',
      actionsMenu: actions.isEmpty ? null : ListingCardActionsMenu(actions: actions),
      badge: state == null ? null : AppStatusBadge(label: state.$1, tone: state.$2),
      footer: inlineEdit || reason?.isNotEmpty == true
          ? _ListingReviewRow(
              reason: reason,
              correction: correction,
              onEdit: inlineEdit ? onEdit : null,
            )
          : null,
    );
  }
}

class _ListingReviewRow extends StatelessWidget {
  const _ListingReviewRow({
    required this.reason,
    required this.correction,
    required this.onEdit,
  });

  final String? reason;
  final bool correction;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reviewText = reason?.isNotEmpty == true
        ? '${correction ? 'ملاحظة المراجعة' : 'سبب الرفض'}: $reason'
        : null;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        key: const ValueKey('listing-review-row'),
        children: [
          Expanded(
            child: reviewText == null
                ? const SizedBox.shrink()
                : Tooltip(
                    message: reviewText,
                    excludeFromSemantics: true,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 5),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                size: 15, color: scheme.onErrorContainer),
                            const SizedBox(width: 4),
                            Expanded(
                                child: Text(
                              reviewText,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onErrorContainer,
                                fontSize: 11,
                              ),
                            )),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
          if (onEdit != null) ...[
            const SizedBox(width: 6),
            Flexible(
              child: OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 15),
                label: const Text('تعديل الإعلان'),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  minimumSize: const Size(0, 34),
                  textStyle:
                      theme.textTheme.labelMedium?.copyWith(fontSize: 11),
                  side: BorderSide(color: scheme.primary),
                ),
              ),
            ),
          ],
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

bool _needsCorrection(PropertyDetails item) =>
    item.reviewStatus == 'returned_for_correction';

bool _rejected(PropertyDetails item) => const {
      'rejected',
      'rejected_blocked',
      'rejected_duplicate',
      'legacy_rejected',
    }.contains(item.reviewStatus);

bool _inReview(PropertyDetails item) =>
    item.reviewStatus == 'submitted' || item.reviewStatus == 'under_review';

bool _published(PropertyDetails item) =>
    item.reviewStatus == 'approved' &&
    item.status == 'published' &&
    item.availabilityStatus == 'available';

(String, AppStatusTone)? _listingState(PropertyDetails property) {
  if (_needsCorrection(property)) return ('يحتاج تصحيح', AppStatusTone.warning);
  if (_rejected(property)) return ('مرفوض', AppStatusTone.error);
  if (_inReview(property)) return ('قيد المراجعة', AppStatusTone.info);
  return listingStatus(property.status, property.availabilityStatus, published: _published(property));
}

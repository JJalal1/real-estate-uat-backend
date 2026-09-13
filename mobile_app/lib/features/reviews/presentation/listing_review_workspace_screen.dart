import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../../account/data/auth_controller.dart';
import '../../properties/domain/property_field_options.dart';
import '../data/listing_review_repository.dart';
import '../domain/listing_duplicate_candidate.dart';
import '../domain/listing_review_models.dart';

final reviewQueueProvider =
    FutureProvider.autoDispose<List<ReviewListingItem>>((ref) {
  return ref.watch(listingReviewRepositoryProvider).queue();
});

final publicationBlocksProvider =
    FutureProvider.autoDispose<List<PublicationBlockItem>>((ref) {
  return ref.watch(listingReviewRepositoryProvider).blocks();
});

class ListingReviewWorkspaceScreen extends ConsumerWidget {
  const ListingReviewWorkspaceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).asData?.value;
    final canLift = user?.hasPermission('listings.manage_blocks') ?? false;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: const AppAppBar(title: 'تحقيق الإعلانات'),
          body: Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(text: 'طلبات التحقيق'),
                  Tab(text: 'حظر النشر'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _ReviewQueue(),
                    _PublicationBlocks(canLift: canLift),
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

class _ReviewQueue extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(reviewQueueProvider);
    return state.when(
      loading: () => const AppLoadingState(label: 'جارٍ تحميل طلبات التحقيق...'),
      error: (error, _) => AppErrorState(
        message: friendlyApiError(error),
        onRetry: () => ref.invalidate(reviewQueueProvider),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const AppEmptyState(
            title: 'لا توجد طلبات معلقة',
            message: 'طلبات الإعلانات الجديدة ستظهر هنا حتى يستلمها موظف دعم مؤهل.',
            icon: Icons.fact_check_outlined,
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(reviewQueueProvider);
            await ref.read(reviewQueueProvider.future);
          },
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsetsDirectional.all(AppLayout.compactPageGutter),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.s12),
            itemBuilder: (context, index) => _ReviewQueueCard(item: items[index]),
          ),
        );
      },
    );
  }
}

class _ReviewQueueCard extends ConsumerStatefulWidget {
  const _ReviewQueueCard({required this.item});

  final ReviewListingItem item;

  @override
  ConsumerState<_ReviewQueueCard> createState() => _ReviewQueueCardState();
}

class _ReviewQueueCardState extends ConsumerState<_ReviewQueueCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final claimed = item.reviewStatus == 'under_review';

    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.s4),
                    Text('المعلن: ${item.ownerName}'),
                    Text('نوع الحساب: ${_verificationType(item.ownerVerificationType)}'),
                    Text('مستندات الإثبات: ${item.proofCount}'),
                  ],
                ),
              ),
              AppStatusBadge(
                label: claimed ? 'تم الاستلام - قيد التحقيق' : 'بانتظار الاستلام',
                tone: claimed ? AppStatusTone.info : AppStatusTone.warning,
              ),
            ],
          ),
          if (item.reason != null && item.reason!.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s8),
            AppInlineMessage(
              message: item.reason!,
              tone: AppStatusTone.warning,
            ),
          ],
          const SizedBox(height: AppSpacing.s12),
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: [
              if (item.reviewStatus == 'submitted')
                AppButton(
                  label: 'استلام الطلب',
                  icon: Icons.assignment_ind_outlined,
                  loading: _busy,
                  onPressed: _busy ? null : _claim,
                ),
              AppButton(
                label: claimed ? 'متابعة التحقيق' : 'عرض التفاصيل',
                icon: Icons.fact_check_outlined,
                style: AppButtonStyle.outlined,
                onPressed: _busy ? null : _openReview,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _claim() async {
    setState(() => _busy = true);
    try {
      await ref.read(listingReviewRepositoryProvider).start(widget.item.id);
      ref.invalidate(reviewQueueProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم استلام الطلب. أصبحت قرارات التحقيق الحساسة مرتبطة بك.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openReview() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ListingReviewCaseScreen(listingId: widget.item.id),
      ),
    );
    if (changed == true) {
      ref.invalidate(reviewQueueProvider);
      ref.invalidate(publicationBlocksProvider);
    }
  }
}

class ListingReviewCaseScreen extends ConsumerStatefulWidget {
  const ListingReviewCaseScreen({super.key, required this.listingId});

  final int listingId;

  @override
  ConsumerState<ListingReviewCaseScreen> createState() =>
      _ListingReviewCaseScreenState();
}

class _ListingReviewCaseScreenState
    extends ConsumerState<ListingReviewCaseScreen> {
  late Future<_ReviewBundle> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ReviewBundle> _load() async {
    final repository = ref.read(listingReviewRepositoryProvider);
    final detail = await repository.detail(widget.listingId);
    final duplicates = await repository.duplicateCandidates(widget.listingId);
    return _ReviewBundle(detail: detail, duplicates: duplicates);
  }

  void _reload() {
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: const AppAppBar(title: 'تحقيق الإعلان'),
        body: FutureBuilder<_ReviewBundle>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const AppLoadingState(label: 'جارٍ تحميل الأدلة...');
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return AppErrorState(
                message: snapshot.error == null
                    ? 'تعذر تحميل التحقيق.'
                    : friendlyApiError(snapshot.error!),
                onRetry: _reload,
              );
            }
            return _body(snapshot.data!);
          },
        ),
      ),
    );
  }

  Widget _body(_ReviewBundle bundle) {
    final item = bundle.detail;
    final isClaimed = item.reviewStatus == 'under_review';

    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppLayout.compactPageGutter,
        AppSpacing.s12,
        AppLayout.compactPageGutter,
        AppSpacing.s32,
      ),
      children: [
        AppSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(item.title, style: Theme.of(context).textTheme.titleLarge),
                  ),
                  AppStatusBadge(
                    label: isClaimed ? 'تم الاستلام - قيد التحقيق' : _reviewStatus(item.reviewStatus),
                    tone: isClaimed ? AppStatusTone.info : AppStatusTone.warning,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s8),
              _InfoRow(label: 'المعلن', value: item.ownerName),
              _InfoRow(label: 'نوع الحساب', value: _verificationType(item.ownerVerificationType)),
              _InfoRow(label: 'حالة التحقق', value: _verificationStatus(item.ownerVerificationStatus)),
              _InfoRow(label: 'الغرض', value: item.purpose == 'sale' ? 'بيع' : 'إيجار'),
              _InfoRow(label: 'النوع', value: item.type),
              _InfoRow(label: 'السعر', value: item.price.toStringAsFixed(0)),
              _InfoRow(label: 'العنوان', value: item.address),
              _InfoRow(
                label: 'الموقع',
                value: '${item.latitude.toStringAsFixed(6)}, ${item.longitude.toStringAsFixed(6)}',
              ),
              if (item.areaValue != null || item.areaM2 != null)
                _InfoRow(
                  label: 'المساحة',
                  value:
                      '${formatPropertyAreaValue(item.areaValue ?? item.areaM2!.toDouble())} ${propertyAreaUnitLabel(item.areaUnit ?? 'sqm')}',
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s16),
        if (item.ownerVerificationType == 'owner') ...[
          const AppSectionHeader(
            title: 'علاقة المالك بهذا العقار',
            subtitle: 'هذه الأدلة خاصة ولا تظهر للعامة.',
          ),
          const SizedBox(height: AppSpacing.s8),
          AppSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(label: 'نوع المستند', value: _ownershipDocumentType(item.ownershipDocumentType)),
                _InfoRow(label: 'الاسم في المستند', value: item.documentOwnerName ?? '—'),
                _InfoRow(label: 'صفة الحساب', value: _relationshipType(item.ownerRelationshipType)),
                if (item.ownerRelationshipNote != null)
                  _InfoRow(label: 'التوضيح', value: item.ownerRelationshipNote!),
                AppStatusBadge(
                  label: item.ownershipDocumentPresent ? 'مستند العلاقة مرفوع' : 'مستند العلاقة مفقود',
                  tone: item.ownershipDocumentPresent
                      ? AppStatusTone.success
                      : AppStatusTone.error,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s16),
        ],
        AppSectionHeader(title: 'صور الإعلان (${item.images.length})'),
        const SizedBox(height: AppSpacing.s8),
        if (item.images.isEmpty)
          const AppInlineMessage(
            message: 'لا توجد صور للإعلان.',
            tone: AppStatusTone.error,
          )
        else
          SizedBox(
            height: 170,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: item.images.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.s8),
              itemBuilder: (_, index) => SizedBox(
                width: 220,
                child: _ProtectedImage(url: item.images[index].url),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.s16),
        AppSectionHeader(title: 'مستندات الإثبات (${item.proofDocuments.length})'),
        const SizedBox(height: AppSpacing.s8),
        if (item.proofDocuments.isEmpty)
          const AppInlineMessage(
            message: 'لا توجد مستندات إثبات.',
            tone: AppStatusTone.warning,
          )
        else
          ...item.proofDocuments.map(
            (media) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s8),
              child: AppSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(media.name ?? 'مستند إثبات'),
                    const SizedBox(height: AppSpacing.s8),
                    SizedBox(height: 190, child: _ProtectedImage(url: media.url)),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.s16),
        _duplicateSection(bundle.duplicates),
        const SizedBox(height: AppSpacing.s16),
        AppSectionHeader(title: 'سجل المراجعة (${item.reviewHistory.length})'),
        const SizedBox(height: AppSpacing.s8),
        AppSurface(
          padding: EdgeInsets.zero,
          child: item.reviewHistory.isEmpty
              ? const Padding(
                  padding: EdgeInsetsDirectional.all(AppLayout.surfacePadding),
                  child: Text('لا توجد مراجعات سابقة.'),
                )
              : Column(
                  children: [
                    for (var i = 0; i < item.reviewHistory.length; i++) ...[
                      AppListRow(
                        title: item.reviewHistory[i].action,
                        subtitle: [
                          if (item.reviewHistory[i].actorName != null)
                            item.reviewHistory[i].actorName!,
                          if (item.reviewHistory[i].reason != null)
                            item.reviewHistory[i].reason!,
                        ].join('\n'),
                        leading: const Icon(Icons.history),
                      ),
                      if (i != item.reviewHistory.length - 1) const Divider(height: 1),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: AppSpacing.s20),
        if (!isClaimed)
          AppInlineMessage(
            title: 'استلم الطلب أولاً',
            message: 'قرارات القبول والإرجاع والرفض لا تتاح لموظف الدعم قبل امتلاك المهمة.',
            tone: AppStatusTone.warning,
          )
        else
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: [
              AppButton(
                label: 'قبول ونشر',
                icon: Icons.check_circle_outline,
                loading: _busy,
                onPressed: _busy ? null : () => _approve(bundle.duplicates),
              ),
              AppButton(
                label: 'إرجاع للتصحيح',
                icon: Icons.edit_note_outlined,
                style: AppButtonStyle.outlined,
                onPressed: _busy ? null : _returnForCorrection,
              ),
              AppButton(
                label: 'رفض نهائي وحظر',
                icon: Icons.block_outlined,
                style: AppButtonStyle.tonal,
                onPressed: _busy ? null : _reject,
              ),
            ],
          ),
      ],
    );
  }

  Widget _duplicateSection(List<ListingDuplicateCandidate> duplicates) {
    if (duplicates.isEmpty) {
      return const AppInlineMessage(
        title: 'فحص التكرار',
        message: 'لم تظهر مرشحات تشابه قوية وفق الموقع والعنوان والمواصفات الحالية. يبقى فحص هوية العقار الخادمي فعالاً عند النشر.',
        tone: AppStatusTone.success,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionHeader(
          title: 'اشتباه تكرار (${duplicates.length})',
          subtitle: 'هذه إشارات للمراجعة البشرية وليست رفضاً آلياً. افحص المرشحات قبل القرار.',
        ),
        const SizedBox(height: AppSpacing.s8),
        for (final candidate in duplicates)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s8),
            child: AppSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(candidate.title, style: Theme.of(context).textTheme.titleMedium),
                      ),
                      AppStatusBadge(
                        label: candidate.severityLabel,
                        tone: candidate.score >= 8
                            ? AppStatusTone.warning
                            : AppStatusTone.info,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  _InfoRow(label: 'رقم الإعلان', value: candidate.listingId.toString()),
                  _InfoRow(label: 'هوية العقار', value: candidate.propertyAssetId.toString()),
                  _InfoRow(label: 'المسافة', value: '${candidate.distanceM} متر'),
                  if (candidate.address != null)
                    _InfoRow(label: 'العنوان', value: candidate.address!),
                  Wrap(
                    spacing: AppSpacing.s4,
                    runSpacing: AppSpacing.s4,
                    children: candidate.signalLabels
                        .map((signal) => AppStatusBadge(label: signal, tone: AppStatusTone.neutral))
                        .toList(growable: false),
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  AppButton(
                    label: 'ربط الإعلان بهوية هذا العقار',
                    icon: Icons.link,
                    style: AppButtonStyle.outlined,
                    onPressed: _busy ? null : () => _linkCandidate(candidate),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _approve(List<ListingDuplicateCandidate> duplicates) async {
    String? reviewReason;
    String? duplicateReason;

    final accepted = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            final reviewController = TextEditingController();
            final duplicateController = TextEditingController();
            return AlertDialog(
              title: const Text('اعتماد الإعلان ونشره'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (duplicates.isNotEmpty) ...[
                      AppInlineMessage(
                        title: 'يوجد اشتباه تكرار',
                        message: 'راجع ${duplicates.length} مرشحاً أعلاه. إذا تأكدت أنها عقارات مختلفة، سجل سبب القرار هنا. لا تستخدم هذا الحقل لتجاوز تكرار مؤكد.',
                        tone: AppStatusTone.warning,
                      ),
                      const SizedBox(height: AppSpacing.s12),
                      TextField(
                        controller: duplicateController,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'سبب اعتبار الإعلان غير مكرر *',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s12),
                    ],
                    TextField(
                      controller: reviewController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'ملاحظة اعتماد (اختياري)',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () {
                    if (duplicates.isNotEmpty && duplicateController.text.trim().length < 10) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(content: Text('اكتب سبباً واضحاً من 10 أحرف على الأقل بعد مراجعة مرشحات التكرار.')),
                      );
                      return;
                    }
                    reviewReason = reviewController.text.trim();
                    duplicateReason = duplicateController.text.trim();
                    Navigator.pop(dialogContext, true);
                  },
                  child: const Text('اعتماد ونشر'),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!accepted || !mounted) return;

    await _runDecision(() => ref.read(listingReviewRepositoryProvider).approve(
          widget.listingId,
          reason: reviewReason,
          duplicateReviewReason: duplicateReason,
        ));
  }

  Future<void> _returnForCorrection() async {
    final reason = await _askReason(
      title: 'إرجاع الإعلان للتصحيح',
      hint: 'اكتب للمعلن تحديداً ما الذي يجب تعديله.',
      minLength: 5,
    );
    if (reason == null) return;
    await _runDecision(
      () => ref.read(listingReviewRepositoryProvider).returnForCorrection(widget.listingId, reason),
    );
  }

  Future<void> _reject() async {
    final reason = await _askReason(
      title: 'رفض نهائي وحظر النشر',
      hint: 'اكتب سبباً واضحاً. هذا القرار ينشئ حظر نشر لهوية العقار لهذا الغرض.',
      minLength: 10,
    );
    if (reason == null) return;
    await _runDecision(
      () => ref.read(listingReviewRepositoryProvider).rejectFinal(widget.listingId, reason),
    );
  }

  Future<void> _linkCandidate(ListingDuplicateCandidate candidate) async {
    final reason = await _askReason(
      title: 'ربط بهوية العقار رقم ${candidate.propertyAssetId}',
      hint: 'اشرح دليل أن الإعلانين يعودان لنفس العقار الفيزيائي.',
      minLength: 5,
    );
    if (reason == null) return;

    setState(() => _busy = true);
    try {
      await ref.read(listingReviewRepositoryProvider).linkPropertyAsset(
            widget.listingId,
            candidate.propertyAssetId,
            reason,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم ربط الإعلان بهوية العقار المختارة وتسجيل القرار.')),
        );
        _reload();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askReason({
    required String title,
    required String hint,
    required int minLength,
  }) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final reason = controller.text.trim();
              if (reason.length < minLength) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(content: Text('اكتب سبباً واضحاً من $minLength أحرف على الأقل.')),
                );
                return;
              }
              Navigator.pop(dialogContext, reason);
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> _runDecision(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(reviewQueueProvider);
      ref.invalidate(publicationBlocksProvider);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _PublicationBlocks extends ConsumerWidget {
  const _PublicationBlocks({required this.canLift});

  final bool canLift;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(publicationBlocksProvider);
    return state.when(
      loading: () => const AppLoadingState(),
      error: (error, _) => AppErrorState(
        message: friendlyApiError(error),
        onRetry: () => ref.invalidate(publicationBlocksProvider),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const AppEmptyState(
            title: 'لا توجد عمليات حظر نشطة',
            message: 'الحظر النهائي يظهر هنا ويمكن رفعه فقط بالصلاحية المناسبة.',
            icon: Icons.verified_outlined,
          );
        }
        return ListView.separated(
          padding: const EdgeInsetsDirectional.all(AppLayout.compactPageGutter),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.s8),
          itemBuilder: (context, index) {
            final item = items[index];
            return AppSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('هوية العقار #${item.propertyAssetId}', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.s4),
                  Text(item.reason),
                  if (canLift) ...[
                    const SizedBox(height: AppSpacing.s8),
                    AppButton(
                      label: 'رفع الحظر',
                      style: AppButtonStyle.outlined,
                      onPressed: () => _lift(context, ref, item),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _lift(
    BuildContext context,
    WidgetRef ref,
    PublicationBlockItem item,
  ) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('رفع حظر النشر'),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(labelText: 'سبب رفع الحظر'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.length >= 10) Navigator.pop(dialogContext, value);
            },
            child: const Text('رفع الحظر'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || !context.mounted) return;

    try {
      await ref.read(listingReviewRepositoryProvider).liftBlock(item.id, reason);
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

class _ProtectedImage extends ConsumerWidget {
  const _ProtectedImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<Uint8List>(
      future: ref.read(listingReviewRepositoryProvider).protectedImage(url),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || snapshot.data == null) {
          return const Center(child: Icon(Icons.broken_image_outlined));
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.control),
          child: Image.memory(snapshot.data!, fit: BoxFit.cover),
        );
      },
    );
  }
}

class _ReviewBundle {
  const _ReviewBundle({required this.detail, required this.duplicates});

  final ReviewListingDetail detail;
  final List<ListingDuplicateCandidate> duplicates;
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 108, child: Text(label, style: Theme.of(context).textTheme.labelLarge)),
          const SizedBox(width: AppSpacing.s8),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

String _reviewStatus(String value) => switch (value) {
      'submitted' => 'بانتظار الاستلام',
      'under_review' => 'تحت التحقيق',
      'returned_for_correction' => 'أعيد للتصحيح',
      'approved' => 'معتمد',
      'rejected_blocked' => 'مرفوض ومحظور',
      _ => value,
    };

String _verificationType(String? value) => switch (value) {
      'owner' => 'مالك',
      'broker' => 'دلال',
      'office' => 'مكتب عقاري',
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
      'registry_record' => 'سجل عقاري',
      'partition_deed' => 'فصل قسمة',
      'court_judgment' => 'حكم قضائي',
      'inheritance_document' => 'مستند إرث',
      'ownership_contract' => 'عقد تمليك',
      'other' => 'مستند آخر',
      _ => 'غير محدد',
    };

String _relationshipType(String? value) => switch (value) {
      'owner' => 'مالك مباشر',
      'agent' => 'وكيل',
      'heir' => 'وارث',
      'co_owner' => 'شريك',
      'other' => 'صفة أخرى',
      _ => 'غير محددة',
    };

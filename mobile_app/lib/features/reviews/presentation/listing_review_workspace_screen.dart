import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/local/stage6_secure_session_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../../account/data/auth_controller.dart';
import '../../account/data/account_request_scope.dart';
import '../../account/presentation/actor_scoped_page.dart';
import '../../map/presentation/aqer_map.dart';
import '../../properties/domain/property_field_options.dart';
import '../../properties/presentation/property_location_preview.dart';
import '../data/listing_review_repository.dart';
import '../domain/listing_duplicate_candidate.dart';
import '../domain/listing_review_models.dart';
import 'listing_duplicate_notice.dart';
import 'review_protected_photo.dart';
import 'review_photo_viewer.dart';
import 'listing_review_comparison_screen.dart';

final reviewQueueProvider = StateNotifierProvider.autoDispose<
    ReviewPageController<ReviewListingItem>, ReviewPageState<ReviewListingItem>>((ref) =>
  _reviewPages<ReviewListingItem>(ref, load: (repository, page) => repository.queue(page: page),
    idOf: (item) => item.id, onSessionChange: ref.invalidateSelf));

final publicationBlocksProvider = StateNotifierProvider.autoDispose<
    ReviewPageController<PublicationBlockItem>, ReviewPageState<PublicationBlockItem>>((ref) =>
  _reviewPages<PublicationBlockItem>(ref, load: (repository, page) => repository.blocks(page: page),
    idOf: (item) => item.id, onSessionChange: ref.invalidateSelf));

ReviewPageController<T> _reviewPages<T>(Ref ref, {
  required Future<ReviewWorkspacePage<T>> Function(ListingReviewRepository, int) load,
  required int Function(T) idOf,
  required VoidCallback onSessionChange,
}) {
  final session = ref.watch(authControllerProvider.select((state) => (
    state.asData?.value?.id,
    Stage6SecureSessionStore.instance.sessionEpoch,
  )));
  var alive = true;
  ref.onDispose(() => alive = false);
  ref.listen(authControllerProvider, (_, next) {
    if (session == (next.asData?.value?.id,
        Stage6SecureSessionStore.instance.sessionEpoch)) { return; }
    // Observe every boundary, even logout then the same account before a frame.
    alive = false;
    onSessionChange();
  });
  final repository = ref.watch(listingReviewRepositoryProvider);
  return ReviewPageController<T>(
    load: (page) => load(repository, page), idOf: idOf,
    signedIn: session.$1 != null,
    isCurrent: () => alive && session == (
      ref.read(authControllerProvider).asData?.value?.id,
      Stage6SecureSessionStore.instance.sessionEpoch,
    ),
    onSessionChange: onSessionChange,
  );
}

class ReviewPageState<T> {
  const ReviewPageState({this.page, this.loading = false,
    this.loadingMore = false, this.error, this.pageError});

  final ReviewWorkspacePage<T>? page;
  final bool loading;
  final bool loadingMore;
  final Object? error;
  final Object? pageError;
  List<T> get items => page?.items ?? const [];
}

class ReviewPageController<T> extends StateNotifier<ReviewPageState<T>> {
  ReviewPageController({required Future<ReviewWorkspacePage<T>> Function(int) load,
    required int Function(T) idOf, required bool signedIn,
    required bool Function() isCurrent, required VoidCallback onSessionChange})
      : _load = load, _idOf = idOf,
        _isCurrent = isCurrent, _onSessionChange = onSessionChange,
        super(signedIn ? ReviewPageState<T>(loading: true)
          : ReviewPageState<T>(error: StateError('AUTH_REQUIRED'))) {
    if (signedIn) unawaited(refresh());
  }

  final Future<ReviewWorkspacePage<T>> Function(int) _load;
  final int Function(T) _idOf;
  final bool Function() _isCurrent;
  final VoidCallback _onSessionChange;
  int _request = 0;

  Future<void> refresh() => _fetchPage(1);

  Future<void> loadMore() async {
    if (!mounted) return;
    if (!_isCurrent()) {
      _resetSession();
      return;
    }
    if (state.loading || state.loadingMore || state.error != null ||
        !(state.page?.hasMore ?? false)) { return; }
    await _fetchPage(state.page!.currentPage + 1, append: true);
  }

  void _resetSession() {
    // An epoch can change before auth emits (for example during logout).
    // Remove private rows now and rebuild from page one, never append page two
    // to a replacement session or leave a discarded request's spinner active.
    state = ReviewPageState<T>(loading: true);
    _onSessionChange();
  }

  Future<void> _fetchPage(int page, {bool append = false}) async {
    if (!mounted) return;
    if (!_isCurrent()) {
      _resetSession();
      return;
    }
    final request = ++_request;
    final previous = state.page;
    state = ReviewPageState<T>(page: previous, loading: !append, loadingMore: append);
    bool current() {
      if (!mounted || request != _request) return false;
      if (_isCurrent()) return true;
      _resetSession();
      return false;
    }
    try {
      final result = await _load(page);
      if (!current()) return;
      // Queue membership can move while pages load. Update repeated IDs in
      // place; a refresh still replaces the complete accumulated snapshot.
      final items = <int, T>{
        if (append && previous != null)
          for (final item in previous.items) _idOf(item): item,
        for (final item in result.items) _idOf(item): item,
      }.values.toList(growable: false);
      state = ReviewPageState<T>(page: ReviewWorkspacePage<T>(items: items,
        currentPage: result.currentPage, lastPage: result.lastPage, total: result.total));
    } catch (error) {
      if (!current()) return;
      final retained = isTransientApiFailure(error) ? previous : null;
      state = ReviewPageState<T>(page: retained,
        error: append && retained != null ? null : error,
        pageError: append && retained != null ? error : null);
    }
  }
}

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
    final controller = ref.read(reviewQueueProvider.notifier);
    if (state.items.isEmpty && state.loading) {
      return const AppLoadingState(label: 'جارٍ تحميل طلبات التحقيق...');
    }
    if (state.items.isEmpty && state.error != null) {
      return AppErrorState(message: friendlyApiError(state.error!),
        onRetry: () => ref.invalidate(reviewQueueProvider));
    }
    if (state.items.isEmpty) {
      return AppEmptyState(
        title: 'لا توجد طلبات معلقة',
        message: 'طلبات الإعلانات الجديدة ستظهر هنا حتى يستلمها موظف دعم مؤهل.',
        icon: Icons.fact_check_outlined,
        actionLabel: 'تحديث',
        onAction: controller.refresh,
      );
    }
    final hasHeader = state.loading || state.error != null;
    final hasFooter = state.page!.hasMore;
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView.separated(
        key: ObjectKey(controller),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsetsDirectional.all(AppLayout.compactPageGutter),
        itemCount: state.items.length + (hasHeader ? 1 : 0) + (hasFooter ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.s12),
        itemBuilder: (context, index) {
          if (hasHeader && index == 0) {
            return AppRefreshStatus(loading: state.loading,
              error: state.error == null ? null : friendlyApiError(state.error!),
              onRetry: controller.refresh);
          }
          final itemIndex = index - (hasHeader ? 1 : 0);
          if (itemIndex < state.items.length) {
            final item = state.items[itemIndex];
            return _ReviewQueueCard(key: ValueKey(item.id), item: item);
          }
          if (state.loadingMore || state.pageError != null) {
            return AppRefreshStatus(key: const ValueKey('review-queue-page-status'),
              loading: state.loadingMore,
              error: state.pageError == null ? null : friendlyApiError(state.pageError!),
              onRetry: controller.loadMore);
          }
          return TextButton.icon(key: const ValueKey('review-queue-more'),
            onPressed: state.loading || state.error != null ? null : controller.loadMore,
            icon: const Icon(Icons.expand_more), label: const Text('المزيد من الطلبات'));
        },
      ),
    );
  }
}

class _ReviewQueueCard extends ConsumerStatefulWidget {
  const _ReviewQueueCard({super.key, required this.item});

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
    final duplicateDetection = item.duplicateDetection;

    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.s4),
          AppStatusBadge(
            label: claimed ? 'تم الاستلام - قيد التحقيق' : 'بانتظار الاستلام',
            tone: claimed ? AppStatusTone.info : AppStatusTone.warning,
          ),
          const SizedBox(height: AppSpacing.s8),
          Text('المعلن: ${item.ownerName}'),
          Text('نوع الحساب: ${_verificationType(item.ownerVerificationType)}'),
          Text('مستندات الإثبات: ${item.proofCount}'),
          if (duplicateDetection != null) ...[
            const SizedBox(height: AppSpacing.s8),
            ListingDuplicateNotice(detection: duplicateDetection),
          ],
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
    final actor = ref.read(authControllerProvider).asData?.value?.id;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ListingReviewCaseScreen(listingId: widget.item.id, actorId: actor),
      ),
    );
    if (changed == true && mounted) {
      ref.invalidate(reviewQueueProvider);
      ref.invalidate(publicationBlocksProvider);
    }
  }
}

class ListingReviewCaseScreen extends StatelessWidget {
  const ListingReviewCaseScreen({super.key, required this.listingId, this.actorId});

  final int listingId;
  final int? actorId;
  @override
  Widget build(BuildContext context) => ActorBoundPage(title: 'تحقيق الإعلان', actorId: actorId,
    builder: (_) => _ListingReviewCasePage(listingId: listingId));
}

class _ListingReviewCasePage extends ConsumerStatefulWidget {
  const _ListingReviewCasePage({required this.listingId});

  final int listingId;

  @override
  ConsumerState<_ListingReviewCasePage> createState() =>
      _ListingReviewCaseScreenState();
}

class _ListingReviewCaseScreenState
    extends ConsumerState<_ListingReviewCasePage> {
  late Future<_ReviewBundle> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AqerMap.warmUpGoogle();
    });
    _future = _load(); _future.ignore();
  }

  Future<_ReviewBundle> _load() async {
    final repository = ref.read(listingReviewRepositoryProvider);
    final evidence = await repository.evidence(widget.listingId);
    return _ReviewBundle(detail: evidence.$1, duplicates: evidence.$2);
  }

  void _reload() {
    setState(() { _future = _load(); _future.ignore(); });
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
    final rejectedPhotos = item.images.where((image) => image.relevance == 'unrelated').length;
    final needsDuplicateReason = item.duplicateCheckStatus == 'needs_support' ||
        item.duplicateDetection != null || bundle.duplicates.isNotEmpty;
    final hasConfirmedPublicDuplicate = item.duplicateCheckStatus == 'confirmed_duplicate' &&
        bundle.duplicates.any((candidate) => candidate.canRejectAsDuplicate);

    return Column(
      children: [
        Expanded(
          child: ListView(
            key: PageStorageKey<String>('listing-review-${item.id}'),
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppLayout.compactPageGutter, AppSpacing.s12,
              AppLayout.compactPageGutter, AppSpacing.s16,
            ),
            children: [
              _listingSummary(item, isClaimed, hasCandidates: bundle.duplicates.isNotEmpty),
              if (bundle.duplicates.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.s12),
                _duplicateSection(bundle, isClaimed),
              ],
              const SizedBox(height: AppSpacing.s16),
              AppSectionHeader(title: 'صور الإعلان (${arabicDigits('${item.images.length}')})'),
              const SizedBox(height: AppSpacing.s8),
              if (item.images.isEmpty)
                const AppInlineMessage(message: 'لا توجد صور للإعلان.', tone: AppStatusTone.error)
              else ...[
                ReviewPhotoPreview(
                  photo: item.images.first,
                  height: 210,
                  onOpen: () => _openGallery(item.images, 0, canReject: isClaimed),
                ),
                if (item.images.length > 1) ...[
                  const SizedBox(height: AppSpacing.s8),
                  SizedBox(
                    height: 74,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: item.images.length,
                      separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.s8),
                      itemBuilder: (_, index) => SizedBox(
                        width: 78,
                        child: ReviewPhotoPreview(
                          photo: item.images[index],
                          height: 74,
                          onOpen: () => _openGallery(item.images, index, canReject: isClaimed),
                          showExpand: false,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
              if (rejectedPhotos > 0) ...[
                const SizedBox(height: AppSpacing.s8),
                AppInlineMessage(
                  message: 'صور تحتاج تصحيحًا: ${arabicDigits('$rejectedPhotos')}. افتح الصورة لقراءة السبب.',
                  tone: AppStatusTone.error,
                ),
              ],
              const SizedBox(height: AppSpacing.s16),
              _details(item),
              if (item.proofDocuments.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.s8),
                _section('مستندات الإثبات (${arabicDigits('${item.proofDocuments.length}')})', [
                  for (final (index, media) in item.proofDocuments.indexed)
                    ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: Text(media.name ?? 'مستند إثبات'),
                      trailing: const Icon(Icons.open_in_new),
                      onTap: () => _openGallery(item.proofDocuments, index, title: 'مستند الإثبات'),
                    ),
                ]),
              ],
              if (!isClaimed) ...[
                const SizedBox(height: AppSpacing.s12),
                const AppInlineMessage(
                  title: 'استلم الطلب أولًا',
                  message: 'تتوفر إجراءات المراجعة بعد الاستلام.',
                  tone: AppStatusTone.info,
                ),
              ],
            ],
          ),
        ),
        if (isClaimed)
          Material(
            color: Theme.of(context).colorScheme.surface,
            elevation: 3,
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpacing.s8,
                    runSpacing: AppSpacing.s4,
                    children: [
                      AppButton(
                        label: 'قبول ونشر',
                        loading: _busy,
                        onPressed: _busy || rejectedPhotos > 0 ? null : () => _approve(needsDuplicateReason),
                      ),
                      AppButton(
                        label: 'إرجاع للتصحيح',
                        style: AppButtonStyle.outlined,
                        onPressed: _busy ? null : () => _chooseCorrection(bundle),
                      ),
                      if (!hasConfirmedPublicDuplicate)
                        PopupMenuButton<String>(
                          tooltip: 'المزيد',
                          enabled: !_busy,
                          onSelected: (_) => _reject(),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'block', child: Text('رفض نهائي وحظر')),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _listingSummary(ReviewListingDetail item, bool isClaimed, {required bool hasCandidates}) {
    final area = item.areaValue != null && item.areaUnit != null
        ? item.areaValue : item.areaM2?.toDouble();
    final areaUnit = item.areaValue != null && item.areaUnit != null ? item.areaUnit! : 'sqm';
    final identityHint = hasCandidates ? null : switch (item.duplicateCheckStatus) {
      'pending' || 'check_failed' => 'فحص هوية العقار قيد التحقق. حدّث المهمة قبل الاعتماد.',
      'needs_support' || 'confirmed_duplicate' => 'تحتاج هوية العقار إلى تحقق.',
      _ => null,
    };
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(item.title, style: Theme.of(context).textTheme.titleLarge),
              AppStatusBadge(
                label: isClaimed ? 'قيد التحقيق' : _reviewStatus(item.reviewStatus),
                tone: isClaimed ? AppStatusTone.info : AppStatusTone.neutral,
              ),
            ],
          ),
          if (identityHint != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s4),
              child: Text(identityHint, style: Theme.of(context).textTheme.bodySmall),
            ),
          const SizedBox(height: AppSpacing.s8),
          Wrap(
            spacing: AppSpacing.s8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(item.ownerName),
              AppStatusBadge(
                label: [
                  _verificationType(item.ownerVerificationType),
                  _verificationStatus(item.ownerVerificationStatus),
                ].join(' · '),
                tone: AppStatusTone.neutral,
              ),
            ],
          ),
          const Divider(),
          _InfoRow(
            label: 'السعر',
            value: item.currency == null ? formatMoneyAmount(item.price) : moneyLabel(item.price, item.currency!),
          ),
          if (area != null)
            _InfoRow(
              label: 'المساحة',
              value: '${formatPropertyAreaValue(area)} ${propertyAreaUnitLabel(areaUnit)}',
            ),
          if (item.address.isNotEmpty)
            Text(item.address, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (item.latitude.isFinite && item.longitude.isFinite &&
              item.latitude.abs() <= 90 && item.longitude.abs() <= 180 &&
              (item.latitude != 0 || item.longitude != 0))
            TextButton.icon(
              icon: const Icon(Icons.place_outlined),
              label: const Text('عرض على الخريطة'),
              onPressed: () => _openPrivatePage<void>('موقع العقار', (_) =>
                PropertyLocationScreen(
                  latitude: item.latitude,
                  longitude: item.longitude,
                  listingTitle: item.title,
                )),
            ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => AppSurface(
    padding: EdgeInsets.zero,
    child: ExpansionTile(title: Text(title), children: children),
  );

  Widget _details(ReviewListingDetail item) => _section('تفاصيل الإعلان', [
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoRow(label: 'الغرض', value: item.purpose == 'sale' ? 'بيع' : 'إيجار'),
          _InfoRow(label: 'النوع', value: propertyTypeLabels[item.type] ?? 'غير محدد'),
          if (item.address.isNotEmpty) _InfoRow(label: 'العنوان', value: item.address),
          if (item.description.isNotEmpty) _InfoRow(label: 'الوصف', value: item.description),
          if (item.ownerVerificationType == 'owner') ...[
            const Divider(),
            const Text('علاقة المالك بهذا العقار'),
            _InfoRow(label: 'نوع المستند', value: _ownershipDocumentType(item.ownershipDocumentType)),
            _InfoRow(label: 'الاسم في المستند', value: item.documentOwnerName ?? '—'),
            _InfoRow(label: 'صفة الحساب', value: _relationshipType(item.ownerRelationshipType)),
            if (item.ownerRelationshipNote case final note?)
              _InfoRow(label: 'التوضيح', value: note),
            AppStatusBadge(
              label: item.ownershipDocumentPresent ? 'مستند العلاقة مرفوع' : 'مستند العلاقة مفقود',
              tone: item.ownershipDocumentPresent ? AppStatusTone.success : AppStatusTone.warning,
            ),
          ],
        ],
      ),
    ),
  ]);

  Widget _duplicateSection(_ReviewBundle bundle, bool isClaimed) {
    final detection = bundle.detail.duplicateDetection;
    final candidates = bundle.duplicates;
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            title: 'إعلانات مشابهة (${arabicDigits('${candidates.length}')})',
          ),
          if (detection != null) ...[
            const SizedBox(height: AppSpacing.s4),
            ListingDuplicateNotice(detection: detection),
          ],
          for (final candidate in candidates)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(candidates.length == 1 ? 'قارن الإعلانين' : candidate.title),
              subtitle: Text(candidates.length == 1
                  ? '${candidate.title} · ${arabicDigits('${candidate.distanceM}')} متر'
                  : '${arabicDigits('${candidate.distanceM}')} متر'),
              trailing: const Icon(Icons.compare_arrows),
              onTap: _busy ? null : () => _openComparison(bundle.detail, candidate, isClaimed),
            ),
        ],
      ),
    );
  }

  Future<T?> _openPrivatePage<T>(String title, WidgetBuilder builder) {
    final actor = ref.read(authControllerProvider).asData?.value?.id;
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    final scope = ref.read(accountRequestScopeProvider);
    if (actor == null || !scope.isCurrent) return Future<T?>.value();
    return Navigator.of(context).push<T>(MaterialPageRoute<T>(
      builder: (_) => ActorBoundPage(
        title: title,
        actorId: actor,
        sessionEpoch: epoch,
        requestScope: scope,
        builder: builder,
      ),
    ));
  }

  Future<void> _openGallery(List<ReviewMediaItem> photos, int index, {
    bool canReject = false, String title = 'صورة الإعلان',
  }) async {
    final scope = ref.read(accountRequestScopeProvider);
    final result = await _openPrivatePage<(ReviewMediaItem, String)>(title, (_) =>
      ReviewPhotoViewer(photos: photos, initialIndex: index, title: title, canReject: canReject));
    if (result != null && mounted && scope.isCurrent) {
      await _rejectPhoto(result.$1, result.$2);
    }
  }

  Future<void> _openComparison(
    ReviewListingDetail listing, ListingDuplicateCandidate candidate, bool isClaimed,
  ) async {
    final scope = ref.read(accountRequestScopeProvider);
    final decision = await _openPrivatePage<ListingComparisonAction>('مقارنة الإعلانين', (_) =>
      ListingReviewComparisonScreen(
        listing: listing,
        candidate: candidate,
        canDecide: isClaimed,
        onPhoto: (photo) => _openGallery([photo], 0),
      ));
    if (!mounted || !scope.isCurrent) return;

    switch (decision) {
      case ListingComparisonAction.link:
        await _linkCandidate(candidate);
      case ListingComparisonAction.reject:
        await _rejectDuplicate(candidate);
      case ListingComparisonAction.returnForCorrection:
        await _returnForCorrection(candidate: candidate);
      case ListingComparisonAction.openPrevious:
        await context.push('/properties/${candidate.listingId}');
      case null:
        break;
    }
  }

  Future<void> _approve(bool needsDuplicateReason) async {
    String? reviewReason;
    String? duplicateReason;

    final accepted = await showActorDialog<bool>(ref: ref,
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('اعتماد الإعلان ونشره'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (needsDuplicateReason) ...[
                      AppInlineMessage(
                        title: 'يوجد اشتباه تكرار',
                        message: 'راجع أدلة التشابه. سجّل سبب اعتبار العقار مختلفًا بعد التحقق.',
                        tone: AppStatusTone.warning,
                      ),
                      const SizedBox(height: AppSpacing.s12),
                      TextField(
                        onChanged: (value) => duplicateReason = value.trim(),
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'سبب اعتبار الإعلان غير مكرر *',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s12),
                    ],
                    TextField(
                      onChanged: (value) => reviewReason = value.trim(),
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
                EbrokerFilledButton(
                  onPressed: () {
                    if (needsDuplicateReason && (duplicateReason?.length ?? 0) < 10) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(content: Text('اكتب سبباً واضحاً من 10 أحرف على الأقل بعد مراجعة مرشحات التكرار.')),
                      );
                      return;
                    }
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

  Future<void> _chooseCorrection(_ReviewBundle bundle) async {
    final candidates = bundle.duplicates.where((item) => item.canRejectAsDuplicate).toList();
    if (candidates.isEmpty) {
      await _returnForCorrection();
      return;
    }
    final scope = ref.read(accountRequestScopeProvider);
    final selected = await showActorDialog<int>(
      ref: ref,
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('سبب إرجاع الإعلان'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 0),
            child: const Text('تصحيح محتوى الإعلان'),
          ),
          for (final candidate in candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, candidate.listingId),
              child: Text('تشابه مع ${candidate.title} · #${candidate.listingId}'),
            ),
        ],
      ),
    );
    if (!mounted || !scope.isCurrent || selected == null) return;
    if (selected == 0) {
      await _returnForCorrection();
      return;
    }
    await _openComparison(bundle.detail,
      candidates.firstWhere((item) => item.listingId == selected), true);
  }

  Future<void> _returnForCorrection({ListingDuplicateCandidate? candidate}) async {
    final reason = await _askReason(
      title: 'إرجاع الإعلان للتصحيح',
      hint: candidate == null
          ? 'اكتب للمعلن تحديداً ما الذي يجب تعديله.'
          : 'وضّح للمعلن وجه التشابه مع الإعلان رقم ${candidate.listingId} وما الذي يمكن توضيحه أو تصحيحه.',
      minLength: 5,
    );
    if (reason == null || !mounted) return;
    await _runDecision(() {
      final repository = ref.read(listingReviewRepositoryProvider);
      return candidate == null
          ? repository.returnForCorrection(widget.listingId, reason)
          : repository.returnForCorrectionAgainst(widget.listingId, candidate.listingId, reason);
    });
  }

  Future<void> _reject() async {
    final reason = await _askReason(
      title: 'رفض نهائي وحظر النشر',
      hint: 'اكتب سبباً واضحاً. هذا القرار ينشئ حظر نشر لهوية العقار لهذا الغرض.',
      minLength: 10,
    );
    if (reason == null || !mounted) return;
    await _runDecision(
      () => ref.read(listingReviewRepositoryProvider).rejectFinal(widget.listingId, reason),
    );
  }

  Future<void> _rejectDuplicate(ListingDuplicateCandidate candidate) async {
    final reason = await _askReason(
      title: 'رفض الإعلان الجديد كمكرر',
      hint: 'اذكر للمعلن سبب التكرار مقارنةً بالإعلان رقم ${candidate.listingId}.',
      minLength: 10,
    );
    if (reason == null || !mounted) return;
    await _runDecision(
      () => ref.read(listingReviewRepositoryProvider).rejectDuplicate(
        widget.listingId,
        candidate.listingId,
        reason,
      ),
    );
  }

  Future<void> _linkCandidate(ListingDuplicateCandidate candidate) async {
    final reason = await _askReason(
      title: 'ربط بهوية العقار رقم ${candidate.propertyAssetId}',
      hint: 'اشرح دليل أن الإعلانين يعودان لنفس العقار الفيزيائي.',
      minLength: 5,
    );
    if (reason == null || !mounted) return;

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
  }) {
    var reason = '';
    return showActorDialog<String>(ref: ref,
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          onChanged: (value) => reason = value.trim(),
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          EbrokerFilledButton(
            onPressed: () {
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
  }

  Future<void> _rejectPhoto(ReviewMediaItem image, String reason) async {
    final token = image.relevanceToken;
    if (_busy || token == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(listingReviewRepositoryProvider).reviewMedia(
        widget.listingId, image.id, token, 'unrelated', reason,
      );
      if (mounted) {
        _reload();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('حُفظ سبب رفض الصورة.')),
        );
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runDecision(Future<void> Function() action) async {
    if (!mounted) return;
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
    final controller = ref.read(publicationBlocksProvider.notifier);
    if (state.items.isEmpty && state.loading) return const AppLoadingState();
    if (state.items.isEmpty && state.error != null) {
      return AppErrorState(message: friendlyApiError(state.error!),
        onRetry: () => ref.invalidate(publicationBlocksProvider));
    }
    if (state.items.isEmpty) {
      return AppEmptyState(
        title: 'لا توجد عمليات حظر نشطة',
        message: 'الحظر النهائي يظهر هنا ويمكن رفعه فقط بالصلاحية المناسبة.',
        icon: Icons.verified_outlined,
        actionLabel: 'تحديث', onAction: controller.refresh,
      );
    }
    final hasHeader = state.loading || state.error != null;
    final hasFooter = state.page!.hasMore;
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView.separated(
        key: ObjectKey(controller),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsetsDirectional.all(AppLayout.compactPageGutter),
        itemCount: state.items.length + (hasHeader ? 1 : 0) + (hasFooter ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.s8),
        itemBuilder: (context, index) {
          if (hasHeader && index == 0) {
            return AppRefreshStatus(loading: state.loading,
              error: state.error == null ? null : friendlyApiError(state.error!),
              onRetry: controller.refresh);
          }
          final itemIndex = index - (hasHeader ? 1 : 0);
          if (itemIndex >= state.items.length) {
            if (state.loadingMore || state.pageError != null) {
              return AppRefreshStatus(key: const ValueKey('publication-blocks-page-status'),
                loading: state.loadingMore,
                error: state.pageError == null ? null : friendlyApiError(state.pageError!),
                onRetry: controller.loadMore);
            }
            return TextButton.icon(key: const ValueKey('publication-blocks-more'),
              onPressed: state.loading || state.error != null ? null : controller.loadMore,
              icon: const Icon(Icons.expand_more), label: const Text('المزيد من عمليات الحظر'));
          }
          final item = state.items[itemIndex];
          return AppSurface(
            key: ValueKey(item.id),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('هوية العقار #${item.propertyAssetId}', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.s4),
                Text(item.reason),
                if (canLift) ...[
                  const SizedBox(height: AppSpacing.s8),
                  AppButton(label: 'رفع الحظر', style: AppButtonStyle.outlined,
                    onPressed: () => _lift(context, ref, item)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _lift(
    BuildContext context,
    WidgetRef ref,
    PublicationBlockItem item,
  ) async {
    final actor = ref.read(authControllerProvider).asData?.value?.id;
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    final repository = ref.read(listingReviewRepositoryProvider);
    final reason = await showActorDialog<String>(
      context: context, ref: ref,
      builder: (_) => const _LiftBlockReasonDialog(),
    );
    if (reason == null || !context.mounted ||
        actor != ref.read(authControllerProvider).asData?.value?.id ||
        epoch != Stage6SecureSessionStore.instance.sessionEpoch) { return; }

    try {
      await repository.liftBlock(item.id, reason);
      if (!context.mounted ||
          actor != ref.read(authControllerProvider).asData?.value?.id ||
          epoch != Stage6SecureSessionStore.instance.sessionEpoch) { return; }
      ref.invalidate(publicationBlocksProvider);
    } catch (error) {
      if (context.mounted &&
          actor == ref.read(authControllerProvider).asData?.value?.id &&
          epoch == Stage6SecureSessionStore.instance.sessionEpoch) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(error))),
        );
      }
    }
  }
}

class _LiftBlockReasonDialog extends StatefulWidget {
  const _LiftBlockReasonDialog();

  @override
  State<_LiftBlockReasonDialog> createState() => _LiftBlockReasonDialogState();
}

class _LiftBlockReasonDialogState extends State<_LiftBlockReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('رفع حظر النشر'),
    content: TextField(
      controller: _controller,
      minLines: 3,
      maxLines: 6,
      decoration: const InputDecoration(labelText: 'سبب رفع الحظر'),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
      EbrokerFilledButton(
        onPressed: () {
          final value = _controller.text.trim();
          if (value.length >= 10) Navigator.pop(context, value);
        },
        child: const Text('رفع الحظر'),
      ),
    ],
  );
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
      'rejected_duplicate' => 'مرفوض لتكرار الإعلان',
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

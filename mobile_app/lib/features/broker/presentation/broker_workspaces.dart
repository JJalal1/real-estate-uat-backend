import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/local/stage6_secure_session_store.dart';
import '../../../core/offline/offline_connection.dart';
import '../../account/data/account_request_scope.dart';
import '../../account/data/private_collection.dart';
import '../../account/presentation/actor_scoped_page.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import 'broker_achievement_carousel.dart';
import 'broker_activity.dart';
import '../../account/data/auth_controller.dart';
import '../../messages/data/message_repository.dart';
import '../../messages/presentation/unread_inbox_badge.dart';
import '../../properties/data/property_repository.dart';
import '../../properties/domain/property_details.dart';
import '../data/broker_repository.dart';
import '../domain/broker_models.dart';

void refreshBrokerData(WidgetRef ref) {
  ref.invalidate(brokerWorkspaceProvider);
  ref.invalidate(brokerAvailabilityProvider);
  ref.invalidate(brokerAvailabilityPagesProvider);
  ref.invalidate(brokerFinanceProvider);
  ref.invalidate(brokerThreadDealProvider);
  ref.invalidate(brokerDirectoryProvider);
  ref.read(messageDataRevisionProvider.notifier).state++;
  ref.read(propertyDataRevisionProvider.notifier).state++;
}

enum _ListingCloseSource { appCustomer, external }
enum _ListingUpdateChoice { available, closed }

bool canUpdateBrokerListing(PropertyDetails property) {
  final paused = property.availabilityStatus == 'paused' ||
      property.availabilityStatus == 'confirmation_paused';
  final published = property.status == 'published' ||
      (property.isOwner && property.status == 'unavailable' && paused);
  return published && property.reviewStatus == 'approved' &&
      (property.availabilityStatus == 'available' || paused);
}

Future<void> showBrokerListingUpdate(
  BuildContext context,
  WidgetRef ref,
  PropertyDetails property,
) async {
  final scope = ref.read(accountRequestScopeProvider);
  final choice = await showActorDialog<_ListingUpdateChoice>(
    context: context,
    ref: ref,
    builder: (dialog) => AlertDialog(
      title: const Text('تحديث حالة الإعلان'),
      content: SingleChildScrollView(
        child: _ListingUpdateOptions(
          title: property.title,
          purpose: property.purpose,
          onAvailable: () => Navigator.pop(dialog, _ListingUpdateChoice.available),
          onClosed: () => Navigator.pop(dialog, _ListingUpdateChoice.closed),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('رجوع')),
      ],
    ),
  );
  if (choice == null || !context.mounted || !scope.isCurrent) return;

  final repository = ref.read(brokerRepositoryProvider);
  Future<void> update(String state) async {
    await repository.updateAvailability([property.id], state);
    if (!context.mounted || !scope.isCurrent) return;
    refreshBrokerData(ref);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم تحديث حالة الإعلان.')),
    );
  }

  try {
    if (choice == _ListingUpdateChoice.available) {
      await update('available');
      return;
    }
    await closeBrokerListing(
      context,
      ref,
      propertyId: property.id,
      purpose: property.purpose,
      onExternal: update,
    );
  } catch (error) {
    if (context.mounted && scope.isCurrent) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyApiError(error))),
      );
    }
  }
}

Future<bool> closeBrokerListing(
  BuildContext context,
  WidgetRef ref, {
  required int propertyId,
  required String purpose,
  required Future<void> Function(String state) onExternal,
  bool openResult = true,
}) async {
  final scope = ref.read(accountRequestScopeProvider);
  final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
  bool current() => scope.isCurrent &&
      epoch == Stage6SecureSessionStore.instance.sessionEpoch;

  final source = await showActorDialog<_ListingCloseSource>(
    context: context,
    ref: ref,
    builder: (dialog) => AlertDialog(
      title: const Text('كيف تمت الصفقة؟'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppButton(
            label: 'مع عميل من التطبيق',
            onPressed: () => Navigator.pop(dialog, _ListingCloseSource.appCustomer),
            expand: true,
          ),
          const SizedBox(height: 8),
          AppButton(
            label: 'خارج التطبيق',
            style: AppButtonStyle.outlined,
            onPressed: () => Navigator.pop(dialog, _ListingCloseSource.external),
            expand: true,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('رجوع')),
      ],
    ),
  );
  if (source == null || !context.mounted || !current()) return false;
  if (source == _ListingCloseSource.external) {
    await onExternal(purpose == 'rent' ? 'rented' : 'sold');
    return current();
  }

  final actor = ref.read(authControllerProvider).asData?.value?.id;
  final customer = await Navigator.of(context).push<BrokerCustomer>(
    MaterialPageRoute(builder: (_) => ActorBoundPage(
      title: 'اختر عميل الصفقة',
      actorId: actor,
      sessionEpoch: epoch,
      requestScope: scope,
      builder: (_) => BrokerCustomersScreen(propertyId: propertyId, selectForDeal: true),
    )),
  );
  if (customer == null || !context.mounted || !current()) return false;
  return reportBrokerDeal(
    context, ref, customer.threadId, propertyId: propertyId, openResult: openResult,
  );
}

class _ListingUpdateOptions extends StatelessWidget {
  const _ListingUpdateOptions({
    required this.title,
    required this.purpose,
    required this.onAvailable,
    required this.onClosed,
    this.availableKey,
    this.closedKey,
    this.selected = false,
  });

  final String title;
  final String purpose;
  final VoidCallback? onAvailable;
  final VoidCallback? onClosed;
  final Key? availableKey, closedKey;
  final bool selected;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 4),
      const Text('هل ما زال العقار متوفرًا؟'),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          Semantics(
            selected: selected,
            child: AppButton(
              key: availableKey,
              label: 'نعم، ما زال متوفرًا',
              style: selected ? AppButtonStyle.tonal : AppButtonStyle.outlined,
              icon: selected ? Icons.check_rounded : null,
              onPressed: onAvailable,
            ),
          ),
          AppButton(
            key: closedKey,
            label: purpose == 'rent' ? 'تم تأجيره' : 'تم بيعه',
            style: AppButtonStyle.outlined,
            onPressed: onClosed,
          ),
        ],
      ),
    ],
  );
}

class BrokerScaffold extends StatelessWidget {
  const BrokerScaffold({required this.body, this.appBar, this.bottomNavigationBar, super.key});
  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;
  @override
  Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl,
    child: Scaffold(appBar: appBar, body: body, bottomNavigationBar: bottomNavigationBar));
}

class BrokerPanel extends StatelessWidget {
  const BrokerPanel({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(22), border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.secondary.withValues(alpha: .03), blurRadius: 16, offset: const Offset(0, 6))]),
    child: child,
  );
}

class BrokerDashboardScreen extends ConsumerWidget {
  const BrokerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).asData?.value;
    final isOffice = user?.isOffice == true;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return BrokerScaffold(
      appBar: AppAppBar(
        title: isOffice ? 'لوحة المكتب' : 'لوحة الدلال',
        actions: [
          IconButton(
            tooltip: 'الإشعارات',
            onPressed: () => context.push('/notifications'),
            icon: const PlatformNotificationUnreadBadge(
              child: EbrokerImage('notification', size: 22),
            ),
          ),
        ],
      ),
      body: ref.watch(brokerWorkspaceProvider).when(
        loading: () => const AppLoadingState(),
        error: (error, _) => AppErrorState(
          message: friendlyApiError(error),
          onRetry: () => ref.invalidate(brokerWorkspaceProvider),
        ),
        data: (data) {
          final rawProfile = data['broker_profile'];
          final profile = rawProfile is Map
              ? BrokerProfile.fromJson(brokerMap(rawProfile))
              : null;
          final photoUrl = profile?.photoUrl;
          final region = profile?.governorate;
          final accountType = profile?.typeLabel ?? (isOffice ? 'مكتب عقاري' : 'دلال');
          final verified = profile?.verified == true;
          final listings = brokerMap(data['listings']);
          final activity = brokerMap(data['customer_activity']);
          final attention = brokerMap(data['needs_attention']);
          final achievementData = brokerMap(data['achievements']);
          final activeListings = profile?.activeListings ?? brokerInt(listings['published']);
          final completedDeals = brokerInt(activity['completed_deals']);
          final firstDealValue = achievementData['first_confirmed_deal'];
          final firstDeal = firstDealValue is bool ? firstDealValue : completedDeals > 0;
          final replies = brokerInt(achievementData['customers_replied_to_this_week']);
          final ratings = brokerInt(achievementData['customer_ratings_count'] ?? profile?.ratingCount);
          final inquiries = brokerInt(achievementData['listing_inquiries_this_month']);
          final availability = brokerInt(attention['availability_count']);
          final unseenDeals = brokerInt(attention['unseen_deal_count']);
          final receivables = brokerInt(attention['outstanding_receivables_count']);
          final achievements = <BrokerAchievement>[
            if (firstDeal)
              BrokerAchievement(BrokerAchievementKind.firstDeal, 1,
                detail: completedDeals > 1 ? 'الصفقات المؤكدة: $completedDeals' : null),
            if (replies > 0)
              BrokerAchievement(BrokerAchievementKind.replies, replies, detail: 'هذا الأسبوع'),
            if (ratings > 0)
              BrokerAchievement(BrokerAchievementKind.ratings, ratings,
                onTap: profile != null && profile.id > 0
                    ? () => context.push('/advertisers/${profile.id}')
                    : null),
            if (inquiries > 0)
              BrokerAchievement(BrokerAchievementKind.inquiries, inquiries, detail: 'هذا الشهر'),
          ];
          final tools = <({String label, IconData icon, int badge, VoidCallback? action})>[
            (label: 'عقاراتي', icon: Icons.home_work_outlined, badge: 0,
              action: () => context.push('/my-listings')),
            (label: 'الصفقات', icon: Icons.handshake_outlined, badge: unseenDeals,
              action: () => context.push('/broker/activity')),
            (label: 'التحديثات', icon: Icons.update, badge: availability,
              action: () => context.push('/broker/availability?due=1')),
            (label: 'المستحقات', icon: Icons.account_balance_wallet_outlined, badge: receivables,
              action: () => context.push('/broker/finance')),
            (label: 'الإحصاءات', icon: Icons.bar_chart_outlined, badge: 0,
              action: () => _statistics(context, profile, listings, activity)),
            (label: 'ملفي العام', icon: Icons.badge_outlined, badge: 0,
              action: profile == null ? null : () => context.push('/advertisers/${profile.id}')),
          ];
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(brokerWorkspaceProvider);
              try {
                await ref.read(brokerWorkspaceProvider.future);
              } catch (_) {
                // The page renders the error and retry action.
              }
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                BrokerPanel(
                  key: const ValueKey('broker-dashboard-profile'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        ClipOval(
                          child: photoUrl == null
                              ? const EbrokerImage('defaultProfileIcon', size: 44)
                              : Image.network(
                                  photoUrl, width: 44, height: 44, fit: BoxFit.cover, cacheWidth: 160,
                                  errorBuilder: (_, __, ___) => const EbrokerImage('defaultProfileIcon', size: 44),
                                ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(profile?.name ?? user?.name ?? 'مرحبًا بك', style: theme.textTheme.titleMedium),
                            Text(
                              '$accountType${verified ? ' موثق' : ''}${region == null ? '' : ' · $region'}',
                              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        )),
                      ]),
                      const SizedBox(height: 8),
                      Text(
                        '$activeListings إعلان نشط',
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                BrokerAchievementCarousel(
                  key: ValueKey(user?.id),
                  achievements: achievements,
                ),
                const SizedBox(height: 12),
                Text('أدوات عملك', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                LayoutBuilder(builder: (context, size) {
                  const gap = 10.0;
                  final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                  final columns = scale > 1.7 || size.maxWidth < 320 ? 1 : 2;
                  final width = (size.maxWidth - (columns - 1) * gap) / columns;
                  return Wrap(spacing: gap, runSpacing: gap, children: [
                    for (final tool in tools)
                      SizedBox(
                        width: width,
                        child: AppSurface(
                          key: ValueKey('broker-tool-${tool.label}'),
                          onTap: tool.action,
                          child: Row(children: [
                            _BrokerToolIcon(count: tool.badge, label: tool.label, icon: tool.icon),
                            const SizedBox(width: 10),
                            Expanded(child: Text(tool.label, style: theme.textTheme.labelMedium)),
                          ]),
                        ),
                      ),
                  ]);
                }),
              ],
            ),
          );
        },
      ),
    );
  }

  void _statistics(BuildContext context, BrokerProfile? profile, Map<String, dynamic> listings, Map<String, dynamic> activity) {
    AppBottomSheet.show<void>(context, builder: (_) => Padding(padding: const EdgeInsets.all(18), child: Column(mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start, children: [Text('إحصاءات عملك', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 12),
        for (final metric in <({int count, String label})>[
          (count: profile?.activeListings ?? brokerInt(listings['published']), label: 'عقارات نشطة'),
          (count: brokerInt(activity['new_customers_this_week']), label: 'عملاء جدد هذا الأسبوع'),
          (count: brokerInt(activity['completed_deals']), label: 'صفقات مكتملة مؤكدة'),
        ]) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [Expanded(child: Text(metric.label)), Text('${metric.count}')])),
      ])));
  }
}

class _BrokerToolIcon extends StatelessWidget {
  const _BrokerToolIcon({required this.count, required this.label, required this.icon});

  final int count;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconTile = Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, size: 23, color: scheme.secondary),
    );
    if (count < 1) return iconTile;
    return Badge(
      key: ValueKey('broker-tool-badge-$label'),
      label: Text('$count'),
      child: iconTile,
    );
  }
}

class BrokerCustomersScreen extends ConsumerWidget {
  const BrokerCustomersScreen({
    this.propertyId,
    this.selectForDeal = false,
    this.initialFilter = 'all',
    this.includeOtherThreads = false,
    super.key,
  });

  final int? propertyId;
  final bool selectForDeal;
  final bool includeOtherThreads;
  final String initialFilter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(authControllerProvider).asData?.value?.id;
    final scope = ref.watch(accountRequestScopeProvider);
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    if (actor == null) {
      return const Scaffold(body: Center(child: Text('سجّل الدخول للمتابعة.')));
    }
    return _BrokerCustomersBody(
      key: ValueKey((scope, epoch, actor, propertyId, initialFilter, selectForDeal, includeOtherThreads)),
      propertyId: propertyId,
      selectForDeal: selectForDeal,
      initialFilter: initialFilter,
      includeOtherThreads: includeOtherThreads,
    );
  }
}

class _BrokerCustomersBody extends ConsumerStatefulWidget {
  const _BrokerCustomersBody({
    this.propertyId,
    required this.selectForDeal,
    required this.initialFilter,
    required this.includeOtherThreads,
    super.key,
  });

  final int? propertyId;
  final bool selectForDeal;
  final bool includeOtherThreads;
  final String initialFilter;

  @override
  ConsumerState<_BrokerCustomersBody> createState() => _BrokerCustomersState();
}

class _BrokerCustomersState extends ConsumerState<_BrokerCustomersBody> {
  static const _statusChips = <String?, String>{
    null: 'كل الحالات',
    'appointment_set': 'تم تحديد موعد',
    'unclassified': 'بلا تصنيف',
    'reserved': 'تم حجز القطع',
    'not_interested': 'غير مهتم',
    'completed': 'تمت الصفقة',
  };
  final _items = <BrokerCustomer>[];
  bool _loading = true, _moreBusy = false, _failedMore = false;
  bool _active = true, _refreshScheduled = false;
  String? _stage, _error, _query;
  late String _filter;
  int _page = 1, _lastPage = 1, _request = 0;

  @override
  void initState() {
    super.initState();
    _filter = const ['unread', 'followup_due'].contains(widget.initialFilter)
        ? widget.initialFilter
        : 'all';
    ref.listenManual(messageDataRevisionProvider, (_, __) => _refreshVisible());
    ref.listenManual(offlineResumeRevisionProvider, (_, __) => _refreshVisible());
    Future.microtask(_load);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final wasActive = _active;
    _active = TickerMode.of(context);
    if (!wasActive) _refreshVisible();
  }

  void _refreshVisible() {
    if (!mounted || !_active || _refreshScheduled) return;
    _refreshScheduled = true;
    unawaited(Future<void>.microtask(() async {
      _refreshScheduled = false;
      if (_active) await _load();
    }));
  }

  @override
  void dispose() {
    _request++;
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (!mounted || (more && (_loading || _moreBusy || _page >= _lastPage))) return;
    final request = ++_request;
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    final scope = ref.read(accountRequestScopeProvider);
    bool current() => mounted && request == _request && scope.isCurrent &&
        epoch == Stage6SecureSessionStore.instance.sessionEpoch;
    final query = '${widget.propertyId}:$_stage:$_filter';
    _failedMore = more;
    setState(() {
      if (_query != query) {
        _items.clear();
        _page = 1;
        _lastPage = 1;
      }
      _query = query;
      _error = null;
      _moreBusy = more;
      if (!more) _loading = true;
    });
    try {
      final result = await ref.read(brokerRepositoryProvider).customers(
        stage: _stage,
        propertyId: widget.propertyId,
        filter: _filter,
        page: more ? _page + 1 : 1,
        includeOtherThreads: widget.includeOtherThreads && !widget.selectForDeal,
      );
      if (!current()) return;
      setState(() {
        final merged = <int, BrokerCustomer>{
          if (more) for (final item in _items) item.threadId: item,
          for (final item in result.items) item.threadId: item,
        };
        _items..clear()..addAll(merged.values);
        _page = result.page;
        _lastPage = result.lastPage;
        _loading = false;
        _moreBusy = false;
      });
    } catch (error) {
      if (!current()) return;
      setState(() {
        if (!isTransientApiFailure(error)) {
          _items.clear();
          _page = 1;
          _lastPage = 1;
          _failedMore = false;
        }
        _error = friendlyApiError(error);
        _loading = false;
        _moreBusy = false;
      });
    }
  }

  void _selectStage(String? stage) {
    if (stage == _stage && _filter == 'all') return;
    setState(() {
      _stage = stage;
      _filter = 'all';
    });
    unawaited(_load());
  }

  Future<void> _openConversation(BrokerCustomer item) async {
    await context.push('/messages/${item.threadId}');
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => BrokerScaffold(
    appBar: AppAppBar(title: widget.selectForDeal ? 'اختر عميل الصفقة' : 'الرسائل'),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (!widget.selectForDeal) ...[
            _filters(context),
            const SizedBox(height: 8),
          ],
          if (_loading && _items.isEmpty)
            const AppLoadingState()
          else if (_error != null && _items.isEmpty)
            AppErrorState(message: _error!, onRetry: () => _load(more: _failedMore))
          else if (_items.isEmpty)
            BrokerPanel(child: Text(switch (_filter) {
              'unread' => 'لا توجد رسائل غير مقروءة.',
              'followup_due' => 'لا توجد متابعات مستحقة حاليًا.',
              _ => _stage == null ? 'لا توجد محادثات بعد.' : 'لا توجد محادثات بهذه الحالة.',
            })),
          if (_items.isNotEmpty && (_loading || (_error != null && !_failedMore)))
            AppRefreshStatus(loading: _loading, error: _error, onRetry: _load),
          for (final item in _items)
            Padding(
              key: ValueKey('broker-customer-${item.threadId}'),
              padding: const EdgeInsets.only(bottom: 8),
              child: widget.selectForDeal
                  ? _dealCustomerCard(context, item)
                  : _BrokerMessageCard(item: item, onTap: () => _openConversation(item)),
            ),
          if (_items.isNotEmpty && (_moreBusy || (_error != null && _failedMore)))
            AppRefreshStatus(
              key: const ValueKey('broker-customers-page-status'),
              loading: _moreBusy,
              error: _failedMore ? _error : null,
              onRetry: () => _load(more: true),
            )
          else if (_page < _lastPage)
            AppButton(
              key: const ValueKey('broker-customers-more'),
              label: 'تحميل المزيد',
              onPressed: _loading || _error != null ? null : () => _load(more: true),
            ),
        ],
      ),
    ),
  );

  Widget _filters(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SingleChildScrollView(
      key: const ValueKey('broker-message-status-filters'),
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final entry in _statusChips.entries)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 6),
            child: ChoiceChip(
              key: ValueKey('broker-message-filter-${entry.key ?? 'all'}'),
              label: Text(entry.value),
              selected: _stage == entry.key,
              onSelected: (_) => _selectStage(entry.key),
              showCheckmark: false,
              labelStyle: theme.textTheme.labelSmall?.copyWith(
                color: _stage == entry.key ? scheme.onPrimaryContainer : scheme.onSurface,
              ),
              labelPadding: const EdgeInsets.symmetric(horizontal: 6),
              materialTapTargetSize: MaterialTapTargetSize.padded,
              visualDensity: VisualDensity.compact,
              shape: const StadiumBorder(),
              side: BorderSide(
                color: _stage == entry.key ? scheme.primary.withValues(alpha: .55) : scheme.outlineVariant,
              ),
              selectedColor: scheme.primaryContainer,
            ),
          ),
      ]),
    );
  }

  Widget _dealCustomerCard(BuildContext context, BrokerCustomer item) {
    final textTheme = Theme.of(context).textTheme;
    final completed = item.followupStage == 'completed';
    final status = completed ? item.stageLabel : item.deal?.statusLabel ?? item.stageLabel;
    return BrokerPanel(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.customerName, style: textTheme.titleSmall),
        Text(item.propertyTitle, style: textTheme.bodySmall),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 4, children: [
          if (status != null)
            AppStatusBadge(label: status, tone: completed ? AppStatusTone.success : AppStatusTone.info),
          if (item.unreadCount > 0)
            AppStatusBadge(label: '${item.unreadCount} غير مقروءة', tone: AppStatusTone.info),
        ]),
        const SizedBox(height: 8),
        AppButton(
          label: 'الصفقة مع هذا العميل',
          expand: true,
          onPressed: () => Navigator.of(context).pop(item),
        ),
      ],
    ));
  }
}

class _BrokerMessageCard extends StatelessWidget {
  const _BrokerMessageCard({required this.item, required this.onTap});

  final BrokerCustomer item;
  final VoidCallback onTap;

  static final _spaces = RegExp(r'\s+');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final message = item.lastMessagePreview?.replaceAll(_spaces, ' ').trim() ?? '';
    final preview = item.lastMessageIsMine && message.isNotEmpty ? 'أنت: $message' : message;
    final lastMessage = item.lastMessageAt;
    final secondary = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    return Material(
      color: theme.brightness == Brightness.dark ? scheme.surfaceContainerLow : scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 76),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Expanded(child: Text(
                    item.customerName,
                    style: theme.textTheme.titleSmall?.copyWith(fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )),
                  if (item.unreadCount > 0)
                    Badge(
                      key: ValueKey('broker-message-unread-${item.threadId}'),
                      label: Text('${item.unreadCount}', semanticsLabel: '${item.unreadCount} رسالة غير مقروءة'),
                      backgroundColor: const Color(0xffb91c1c),
                      textColor: Colors.white,
                    ),
                ],
              ),
              if (preview.isNotEmpty || lastMessage != null) ...[
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: Text(
                      preview,
                      style: secondary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )),
                    if (lastMessage != null) ...[
                      const SizedBox(width: 10),
                      Text(
                        _messageDateLabel(lastMessage),
                        style: secondary?.copyWith(fontSize: 11),
                        textDirection: TextDirection.ltr,
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _messageDateLabel(DateTime sentAt) {
    final local = sentAt.toLocal();
    final now = DateTime.now();
    final days = DateTime.utc(now.year, now.month, now.day)
        .difference(DateTime.utc(local.year, local.month, local.day)).inDays;
    if (days >= 0 && days <= 7) {
      return const ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'][local.weekday - 1];
    }
    return '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
  }
}

class BrokerAvailabilityScreen extends ConsumerWidget {
  const BrokerAvailabilityScreen({this.initiallyDue = false, super.key});
  final bool initiallyDue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(authControllerProvider).asData?.value?.id;
    final scope = ref.watch(accountRequestScopeProvider);
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    if (actor == null) return const Scaffold(body: Center(child: Text('سجّل الدخول للمتابعة.')));
    return _BrokerAvailabilityBody(
      key: ValueKey((scope, epoch, actor, initiallyDue)), initiallyDue: initiallyDue,
    );
  }
}

class _BrokerAvailabilityBody extends ConsumerStatefulWidget {
  const _BrokerAvailabilityBody({required this.initiallyDue, super.key});
  final bool initiallyDue;

  @override
  ConsumerState<_BrokerAvailabilityBody> createState() => _BrokerAvailabilityState();
}

enum _AvailabilityOperation { selectingAll, confirming, closing }

class _BrokerAvailabilityState extends ConsumerState<_BrokerAvailabilityBody> {
  final _selected = <int>{};
  _AvailabilityOperation? _operation;
  bool get _busy => _operation != null;
  final _confirmed = <int>{};

  bool Function() _sessionGuard() {
    final scope = ref.read(accountRequestScopeProvider);
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    return () => mounted && scope.isCurrent &&
        epoch == Stage6SecureSessionStore.instance.sessionEpoch;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _selectAll(PrivateCollectionController<BrokerAvailability> controller) async {
    if (_busy) return;
    final current = _sessionGuard();
    final provider = brokerAvailabilityPagesProvider(true);
    setState(() => _operation = _AvailabilityOperation.selectingAll);
    try {
      var state = ref.read(provider);
      while (state.page?.hasMore ?? false) {
        final previousPage = state.page!.currentPage;
        await controller.loadMore();
        if (!current() || !identical(ref.read(provider.notifier), controller)) return;
        state = ref.read(provider);
        final error = state.error ?? state.pageError;
        if (error != null) throw error;
        if ((state.page?.currentPage ?? 0) <= previousPage) {
          _showMessage('تعذّر تحديد الكل. حدّث القائمة ثم أعد المحاولة.');
          return;
        }
      }
      final total = state.page?.total;
      if (total != null && total != state.items.length) {
        _showMessage('تغيّرت قائمة الإعلانات أثناء التحميل. حدّث القائمة ثم أعد تحديد الكل.');
        return;
      }
      setState(() => _selected.addAll(
        state.items.map((item) => item.id).where((id) => !_confirmed.contains(id)),
      ));
    } catch (error) {
      if (current()) _showMessage(friendlyApiError(error));
    } finally {
      if (current()) setState(() => _operation = null);
    }
  }

  Future<void> _confirm() async {
    if (_selected.isEmpty || _busy) return;
    final current = _sessionGuard();
    final repository = ref.read(brokerRepositoryProvider);
    final ids = _selected.toList(growable: false);
    var confirmed = 0;
    setState(() => _operation = _AvailabilityOperation.confirming);
    try {
      // Each request validates and updates at most 100 IDs atomically.
      for (var offset = 0; offset < ids.length; offset += 100) {
        if (!current()) return;
        final batch = ids.skip(offset).take(100).toList(growable: false);
        await repository.updateAvailability(batch, 'available');
        if (!current()) return;
        confirmed += batch.length;
        setState(() {
          _selected.removeAll(batch);
          _confirmed.addAll(batch);
        });
      }
      refreshBrokerData(ref);
    } catch (error) {
      if (!current()) return;
      if (confirmed > 0) {
        ref.invalidate(brokerWorkspaceProvider);
        ref.invalidate(brokerAvailabilityProvider);
        ref.read(propertyDataRevisionProvider.notifier).state++;
      }
      final message = friendlyApiError(error);
      _showMessage(confirmed == 0 ? message : 'تأكد توفر $confirmed إعلانًا. $message');
    } finally {
      if (current()) setState(() => _operation = null);
    }
  }

  Future<void> _close(BrokerAvailability item) async {
    if (_busy) return;
    final current = _sessionGuard();
    setState(() => _operation = _AvailabilityOperation.closing);
    try {
      final updated = await closeBrokerListing(
        context,
        ref,
        propertyId: item.id,
        purpose: item.purpose,
        openResult: false,
        onExternal: (state) async {
          await ref.read(brokerRepositoryProvider).updateAvailability([item.id], state);
          if (!current()) return;
          setState(() => _confirmed.add(item.id));
          refreshBrokerData(ref);
        },
      );
      if (updated && current()) setState(() => _selected.remove(item.id));
    } catch (error) {
      if (current()) _showMessage(friendlyApiError(error));
    } finally {
      if (current()) setState(() => _operation = null);
    }
  }

  Future<void> _refresh(PrivateCollectionController<BrokerAvailability> controller) async {
    if (_busy) return;
    final current = _sessionGuard();
    setState(_selected.clear);
    await controller.refresh();
    if (current() && ref.read(brokerAvailabilityPagesProvider(true)).error == null) {
      setState(_confirmed.clear);
    }
  }

  Widget _listingCard(BrokerAvailability item, {required bool controlsEnabled}) {
    final selected = _selected.contains(item.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: BrokerPanel(
        key: ValueKey('broker-availability-${item.id}'),
        child: _ListingUpdateOptions(
          title: item.title,
          purpose: item.purpose,
          selected: selected,
          availableKey: ValueKey('broker-availability-available-${item.id}'),
          closedKey: ValueKey('broker-availability-close-${item.id}'),
          onAvailable: controlsEnabled ? () => setState(() {
            if (selected) {
              _selected.remove(item.id);
            } else {
              _selected.add(item.id);
            }
          }) : null,
          onClosed: controlsEnabled ? () => _close(item) : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = brokerAvailabilityPagesProvider(true);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final items = state.items
        .where((item) => !_confirmed.contains(item.id))
        .toList(growable: false);
    final controlsEnabled = !_busy && !state.loading && !state.loadingMore && state.error == null;
    final allSelected = items.isNotEmpty && state.page?.hasMore == false &&
        items.every((item) => _selected.contains(item.id));

    return BrokerScaffold(
      appBar: const AppAppBar(title: 'التحديثات'),
      bottomNavigationBar: items.isEmpty ? null : SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: AppButton(
          key: const ValueKey('broker-availability-confirm'),
          label: _selected.isEmpty ? 'تحديث' : 'تحديث (${_selected.length})',
          loading: _operation == _AvailabilityOperation.confirming,
          onPressed: controlsEnabled && _selected.isNotEmpty ? _confirm : null,
          expand: true,
        ),
      ),
      body: _availabilityBody(state, controller, items, controlsEnabled, allSelected),
    );
  }

  Widget _availabilityBody(
    PrivateCollectionState<BrokerAvailability> state,
    PrivateCollectionController<BrokerAvailability> controller,
    List<BrokerAvailability> items,
    bool controlsEnabled,
    bool allSelected,
  ) {
    if (state.loading && items.isEmpty) return const AppLoadingState();
    if (state.error != null && items.isEmpty) {
      return AppErrorState(
        message: friendlyApiError(state.error!),
        onRetry: () => _refresh(controller),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _refresh(controller),
      child: CustomScrollView(
        key: ObjectKey(controller),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (state.loading || state.error != null)
            SliverToBoxAdapter(child: AppRefreshStatus(
              loading: state.loading,
              error: state.error == null ? null : friendlyApiError(state.error!),
              onRetry: _busy ? null : () => _refresh(controller),
            )),
          if (items.isEmpty)
            const SliverPadding(
              padding: EdgeInsets.all(16),
              sliver: SliverToBoxAdapter(
                child: BrokerPanel(child: Text('لا توجد إعلانات تحتاج تحديثًا حاليًا.')),
              ),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: CheckboxListTile(
                  key: const ValueKey('broker-availability-select-all'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(_operation == _AvailabilityOperation.selectingAll
                      ? 'جارٍ تحميل الإعلانات لتحديدها' : 'تحديد الكل'),
                  tristate: true,
                  value: allSelected ? true : _selected.isEmpty ? false : null,
                  onChanged: controlsEnabled ? (_) {
                    if (allSelected) {
                      setState(_selected.clear);
                    } else {
                      unawaited(_selectAll(controller));
                    }
                  } : null,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.builder(
                itemCount: items.length,
                itemBuilder: (_, index) => _listingCard(
                  items[index], controlsEnabled: controlsEnabled,
                ),
              ),
            ),
          ],
          if (state.loadingMore || state.pageError != null)
            SliverToBoxAdapter(child: AppRefreshStatus(
              key: const ValueKey('broker-availability-page-status'),
              loading: state.loadingMore,
              error: state.pageError == null ? null : friendlyApiError(state.pageError!),
              onRetry: _busy ? null : controller.loadMore,
            ))
          else if (state.page?.hasMore ?? false)
            SliverToBoxAdapter(child: TextButton.icon(
              key: const ValueKey('broker-availability-more'),
              onPressed: controlsEnabled ? controller.loadMore : null,
              icon: const Icon(Icons.expand_more),
              label: const Text('المزيد من الإعلانات'),
            )),
        ],
      ),
    );
  }
}

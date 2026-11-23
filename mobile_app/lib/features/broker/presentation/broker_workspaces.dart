import 'dart:async';
import '../data/customer_help_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/local/stage6_secure_session_store.dart';
import '../../account/data/account_request_scope.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../../../core/widgets/ebroker_card_actions.dart';
import 'customer_followup_sheet.dart';
import '../../account/data/auth_controller.dart';
import '../../properties/data/property_repository.dart';
import '../data/broker_repository.dart';
import '../domain/broker_models.dart';

void refreshBrokerData(WidgetRef ref) {
  ref.invalidate(brokerWorkspaceProvider);
  ref.invalidate(brokerAvailabilityProvider);
  ref.invalidate(brokerAvailabilityPagesProvider);
  ref.invalidate(brokerFinanceProvider);
  ref.invalidate(brokerThreadDealProvider);
  ref.invalidate(brokerDirectoryProvider);
  ref.read(propertyDataRevisionProvider.notifier).state++;
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
            icon: const EbrokerImage('notification', size: 22),
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
          final finance = brokerMap(data['financial_summary']);
          final activeListings = profile?.activeListings ?? brokerInt(listings['published']);
          final completedDeals = brokerInt(activity['completed_deals']);
          final unread = brokerInt(activity['unread_conversations']);
          final followups = brokerInt(attention['customer_followups_due']);
          final corrections = brokerInt(listings['returned_for_correction'] ??
              brokerRows(attention['correction_listings']).length);
          final availability = brokerInt(attention['availability_count']);
          final pendingDeals = brokerInt(attention['pending_deal_count']);
          final priorities = <({String id, String label, String route, IconData icon, int? count})>[
            if (finance['listing_creation_blocked'] == true)
              (id: 'finance', label: 'تسوية مستحقات المنصة', route: '/broker/finance',
                icon: Icons.account_balance_wallet_outlined, count: null),
            if (unread > 0)
              (id: 'unread', label: 'الرد على المحادثات', route: '/broker/customers?filter=unread',
                icon: Icons.chat_bubble_outline, count: unread),
            if (followups > 0)
              (id: 'followup-due', label: 'متابعة العملاء', route: '/broker/customers?filter=followup_due',
                icon: Icons.event_note_outlined, count: followups),
            if (corrections > 0)
              (id: 'corrections', label: 'تصحيح الإعلانات', route: '/my-listings?corrections=1',
                icon: Icons.edit_outlined, count: corrections),
            if (availability > 0)
              (id: 'availability', label: 'تأكيد توفر الإعلانات', route: '/broker/availability?due=1',
                icon: Icons.update, count: availability),
            if (pendingDeals > 0)
              (id: 'pending-deals', label: 'متابعة الصفقات المعلقة', route: '/broker/activity',
                icon: Icons.check_circle_outline, count: pendingDeals),
          ];
          final tools = <({String label, IconData icon, VoidCallback? action})>[
            (label: 'عقاراتي', icon: Icons.home_work_outlined, action: () => context.push('/my-listings')),
            (label: 'الصفقات', icon: Icons.handshake_outlined, action: () => context.push('/broker/activity')),
            (label: 'التوفر', icon: Icons.update, action: () => context.push('/broker/availability')),
            (label: 'المستحقات', icon: Icons.account_balance_wallet_outlined, action: () => context.push('/broker/finance')),
            (label: 'الإحصاءات', icon: Icons.bar_chart_outlined, action: () => _statistics(context, profile, listings, activity)),
            (label: 'ملفي العام', icon: Icons.badge_outlined, action: profile == null ? null : () => context.push('/advertisers/${profile.id}')),
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
                AppSurface(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        ClipOval(
                          child: photoUrl == null
                              ? const EbrokerImage('defaultProfileIcon', size: 36)
                              : Image.network(
                                  photoUrl, width: 36, height: 36, fit: BoxFit.cover, cacheWidth: 144,
                                  errorBuilder: (_, __, ___) => const EbrokerImage('defaultProfileIcon', size: 36),
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
                      DefaultTextStyle.merge(
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        child: Wrap(spacing: 12, runSpacing: 4, children: [
                          Text('$activeListings إعلان نشط'),
                          Text('$completedDeals صفقة مؤكدة'),
                          if (profile != null && profile.ratingCount > 0)
                            Text.rich(TextSpan(children: [
                              const WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: EbrokerIcon(Icons.star_outline, size: 16, color: Colors.amber),
                              ),
                              TextSpan(text: ' ${profile.rating.toStringAsFixed(1)} · ${profile.ratingCount} تقييم'),
                            ])),
                        ]),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text('مهام تحتاج إجراء', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                AppSurface(
                  padding: EdgeInsets.zero,
                  child: Material(
                    color: Colors.transparent,
                    child: priorities.isEmpty
                        ? const ListTile(
                            leading: Icon(Icons.task_alt),
                            title: Text('لا توجد مهام معلقة'),
                          )
                        : Column(children: [
                            for (final (index, item) in priorities.indexed) ...[
                              if (index > 0) const Divider(height: 1, indent: 12, endIndent: 12),
                              ListTile(
                                key: ValueKey('broker-priority-${item.id}'),
                                onTap: () => context.push(item.route),
                                minTileHeight: 48,
                                horizontalTitleGap: 8,
                                minLeadingWidth: 20,
                                contentPadding: const EdgeInsetsDirectional.fromSTEB(12, 0, 8, 0),
                                leading: EbrokerIcon(item.icon, size: 19, color: scheme.primary),
                                title: Text(item.label, style: theme.textTheme.bodyMedium),
                                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                  if (item.count != null)
                                    AppStatusBadge(label: '${item.count}', tone: AppStatusTone.info),
                                  const EbrokerIcon(Icons.chevron_left, size: 18),
                                ]),
                              ),
                            ],
                          ]),
                  ),
                ),
                const SizedBox(height: 16),
                Text('أدوات العمل', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                LayoutBuilder(builder: (context, size) {
                  const gap = 8.0;
                  final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                  final columns = scale > 1.5 || size.maxWidth < 300 ? 1 : 2;
                  final width = (size.maxWidth - (columns - 1) * gap) / columns;
                  return Wrap(spacing: gap, runSpacing: gap, children: [
                    for (final tool in tools)
                      SizedBox(
                        width: width,
                        child: AppSurface(
                          key: ValueKey('broker-tool-${tool.label}'),
                          onTap: tool.action,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 32),
                            child: Row(children: [
                              EbrokerIcon(tool.icon, size: 20, color: scheme.primary),
                              const SizedBox(width: 8),
                              Expanded(child: Text(tool.label, style: theme.textTheme.labelLarge)),
                            ]),
                          ),
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

class BrokerCustomersScreen extends ConsumerWidget {
  const BrokerCustomersScreen({this.propertyId, this.selectForDeal = false, this.initialFilter = 'all', this.embedded = false, super.key});
  final int? propertyId;
  final bool selectForDeal;
  final bool embedded;
  final String initialFilter;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(authControllerProvider).asData?.value?.id;
    final scope = ref.watch(accountRequestScopeProvider);
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    return actor == null ? const Scaffold(body: Center(child: Text('سجّل الدخول للمتابعة.')))
      : _BrokerCustomersBody(key: ValueKey((scope, epoch, actor, propertyId, initialFilter, selectForDeal)), propertyId: propertyId, selectForDeal: selectForDeal,
        initialFilter: initialFilter, embedded: embedded);
  }
}
class _BrokerCustomersBody extends ConsumerStatefulWidget {
  const _BrokerCustomersBody({this.propertyId, required this.selectForDeal, required this.initialFilter, required this.embedded, super.key});
  final int? propertyId;
  final bool selectForDeal, embedded;
  final String initialFilter;
  @override
  ConsumerState<_BrokerCustomersBody> createState() => _BrokerCustomersState();
}
class _BrokerCustomersState extends ConsumerState<_BrokerCustomersBody> {
  final _items = <BrokerCustomer>[];
  bool _loading = true, _moreBusy = false, _helpReady = false, _helpSeen = true, _helpUsed = false;
  int? _helpActorId;

  Future<void> _loadHelp() async {
    try {
    final actor = await ref.read(authControllerProvider.future);
    if (!mounted || actor == null) return;
    final seen = await ref.read(customerHelpStoreProvider).seen(actor.id);
    if (mounted && ref.read(authControllerProvider).asData?.value?.id == actor.id) setState(() { _helpActorId = actor.id; _helpReady = true; _helpSeen = seen || _helpUsed; });
    if (_helpUsed) unawaited(_rememberHelp());
    } catch (_) { /* Help storage must not block customer work. */ }
  }
  Future<void> _rememberHelp() async {
    final id = _helpActorId ?? ref.read(authControllerProvider).asData?.value?.id;
    if (id == null || ref.read(authControllerProvider).asData?.value?.id != id) return;
    if (mounted) setState(() { _helpSeen = true; _helpUsed = true; });
    unawaited(ref.read(customerHelpStoreProvider).markSeen(id));
  }
  String? _stage, _error, _query;
  bool _failedMore = false;
  late String _filter;
  int _page = 1, _lastPage = 1, _request = 0;
  @override
  void initState() { super.initState(); _filter = const ['unread', 'followup_due'].contains(widget.initialFilter) ? widget.initialFilter : 'all'; Future.microtask(_loadHelp); Future.microtask(_load); }
  @override
  void dispose() { _request++; super.dispose(); }
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
      if (_query != query) { _items.clear(); _page = 1; _lastPage = 1; }
      _query = query; _error = null; _moreBusy = false;
      if (more) { _moreBusy = true; } else { _loading = true; }
    });
    try {
      final result = await ref.read(brokerRepositoryProvider).customers(stage: _stage, propertyId: widget.propertyId, filter: _filter, page: more ? _page + 1 : 1);
      if (!current()) return;
      if (result.items.any((item) => item.stage != 'new' || item.privateNote.isNotEmpty || item.remindAt != null)) { _helpUsed = true; unawaited(_rememberHelp()); }
      if (!mounted) return;
      setState(() { final merged = <int, BrokerCustomer>{
        if (more) for (final item in _items) item.threadId: item,
        for (final item in result.items) item.threadId: item,
      }; _items..clear()..addAll(merged.values); _page = result.page; _lastPage = result.lastPage; _loading = false; _moreBusy = false; });
    } catch (error) { if (current()) setState(() { if (!isTransientApiFailure(error)) { _items.clear(); _page = 1; _lastPage = 1; _failedMore = false; } _error = friendlyApiError(error); _loading = false; _moreBusy = false; }); }
  }
  Future<void> _chooseStage(BrokerCustomer item) async {
    final stage = await AppBottomSheet.show<String>(context, builder: (sheet) => Padding(padding: const EdgeInsets.fromLTRB(20,0,20,20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('تحديث حالة المتابعة', style: Theme.of(sheet).textTheme.titleLarge), const SizedBox(height: 12),
        Flexible(child: ListView(shrinkWrap:true, children:[for(final entry in brokerLeadLabels.entries.where((e)=>e.key!='completed')) ListTile(
          shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14)), selected:item.stage==entry.key,
          selectedTileColor:Theme.of(sheet).colorScheme.primaryContainer, title:Text(entry.value),
          trailing:item.stage==entry.key?const Icon(Icons.check_circle_outline):null,onTap:()=>Navigator.pop(sheet,entry.key))])),
      ])));
    if (stage != null && mounted) await _change(item, stage);
  }
  Future<void> _change(BrokerCustomer item, String stage) async {
    try { await ref.read(brokerRepositoryProvider).updateCustomer(item.threadId, stage); await _rememberHelp(); refreshBrokerData(ref); await _load(); }
    catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error)))); }
  }
  @override
  Widget build(BuildContext context) => BrokerScaffold(
    appBar: widget.embedded ? null : AppAppBar(
      title: widget.selectForDeal ? 'اختر عميل الصفقة' : 'متابعة العملاء',
    ),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (!widget.selectForDeal) ...[
            _filters(),
            const SizedBox(height: 8),
            if (_helpReady && !_helpSeen)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: BrokerPanel(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('اضغط على الحالة لتحديثها. تجد الملاحظات والتذكير في خيارات العميل.'),
                    TextButton(
                      key: const ValueKey('customer-help-dismiss'),
                      onPressed: _rememberHelp,
                      child: const Text('فهمت'),
                    ),
                  ],
                )),
              ),
          ],
          if (_loading && _items.isEmpty)
            const AppLoadingState()
          else if (_error != null && _items.isEmpty)
            AppErrorState(message: _error!, onRetry: () => _load(more: _failedMore))
          else if (_items.isEmpty)
            BrokerPanel(child: Text(switch (_filter) {
              'unread' => 'لا توجد محادثات تحتاج ردك.',
              'followup_due' => 'لا توجد متابعات مستحقة حاليًا.',
              _ => _stage == null ? 'سيظهر هنا من يتواصل حول إعلاناتك.' : 'لا يوجد عملاء بهذه الحالة.',
            })),
          if (_items.isNotEmpty && (_loading || (_error != null && !_failedMore)))
            AppRefreshStatus(loading: _loading, error: _error, onRetry: _load),
          for (final item in _items) _customerCard(context, item),
          if (_items.isNotEmpty && (_moreBusy || (_error != null && _failedMore)))
            AppRefreshStatus(
              key: const ValueKey('broker-customers-page-status'),
              loading: _moreBusy, error: _failedMore ? _error : null,
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

  Widget _filters() => Wrap(
    spacing: 6,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      for (final entry in const {'all': 'الكل', 'unread': 'تحتاج ردك', 'followup_due': 'حان الموعد'}.entries)
        AppFilterChip(
          label: entry.value,
          selected: _filter == entry.key,
          onSelected: (selected) {
            if (!selected) return;
            setState(() => _filter = entry.key);
            _load();
          },
        ),
      PopupMenuButton<String>(
        tooltip: 'حالة المتابعة',
        initialValue: _stage ?? 'all',
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'all', child: Text('كل الحالات')),
          for (final entry in brokerLeadLabels.entries)
            PopupMenuItem(value: entry.key, child: Text(entry.value)),
        ],
        onSelected: (value) {
          final stage = value == 'all' ? null : value;
          if (stage == _stage) return;
          setState(() => _stage = stage);
          _load();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const EbrokerIcon(Icons.tune_rounded, size: 18),
            const SizedBox(width: 4),
            Flexible(child: Text(brokerLeadLabels[_stage] ?? 'الحالة')),
          ]),
        ),
      ),
    ],
  );

  Widget _customerCard(BuildContext context, BrokerCustomer item) {
    final textTheme = Theme.of(context).textTheme;
    final status = item.deal?.statusLabel ?? item.stageLabel;
    final statusBadge = AppStatusBadge(
      label: status,
      tone: item.stage == 'completed' ? AppStatusTone.success : AppStatusTone.info,
    );
    return Padding(
      key: ValueKey('broker-customer-${item.threadId}'),
      padding: const EdgeInsets.only(bottom: 8),
      child: BrokerPanel(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.customerName, style: textTheme.titleSmall),
                Text(item.propertyTitle, style: textTheme.bodySmall),
              ],
            )),
            if (!widget.selectForDeal) _customerMenu(context, item),
          ]),
          if (widget.selectForDeal) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              statusBadge,
              if (item.unreadCount > 0)
                AppStatusBadge(label: '${item.unreadCount} غير مقروءة', tone: AppStatusTone.info),
            ]),
            const SizedBox(height: 8),
            AppButton(
              label: 'الصفقة مع هذا العميل', expand: true,
              onPressed: () => Navigator.of(context).pop(item),
            ),
          ] else ...[
            if (item.remindAt != null)
              Text(
                '${item.followupDue ? 'حان موعد المتابعة' : 'المتابعة'}: ${followupDateLabel(item.remindAt!)}',
                style: textTheme.bodySmall,
              ),
            if (item.privateNote.isNotEmpty)
              Text('ملاحظة خاصة: ${item.privateNote}', style: textTheme.bodySmall,
                maxLines: 2, overflow: TextOverflow.ellipsis),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (item.stage == 'completed') statusBadge
                else Tooltip(
                  message: 'تحديث حالة المتابعة',
                  child: ActionChip(
                    avatar: const EbrokerIcon(Icons.expand_more, size: 16),
                    label: Text(item.stageLabel),
                    onPressed: () => _chooseStage(item),
                  ),
                ),
                if (item.stage != 'completed' && item.deal != null) statusBadge,
                TextButton.icon(
                  onPressed: () async {
                    await context.push('/messages/${item.threadId}');
                    if (mounted) _load();
                  },
                  icon: const EbrokerIcon(Icons.chat_bubble_outline, size: 18),
                  label: Text(item.unreadCount > 0 ? 'رد (${item.unreadCount})' : 'المحادثة'),
                ),
              ],
            ),
          ],
        ],
      )),
    );
  }

  Widget _customerMenu(BuildContext context, BrokerCustomer item) {
    final actions = [
      EbrokerCardAction('ملاحظة وتذكير', () async {
        final saved = await editCustomerFollowup(context, ref, item.threadId, customer: item);
        if (!saved || !mounted) return;
        await _rememberHelp();
        if (mounted) _load();
      }, icon: Icons.event_note_outlined),
      EbrokerCardAction('العقار', () => context.push('/properties/${item.propertyId}'), icon: Icons.home_outlined),
      if (item.deal != null)
        EbrokerCardAction('نتيجة الصفقة', () => context.push('/broker/deals/${item.deal!.id}'), icon: Icons.check_circle_outline),
    ];
    return PopupMenuButton<EbrokerCardAction>(
      tooltip: 'خيارات البطاقة',
      icon: const EbrokerIcon(Icons.more_vert, size: 22),
      onSelected: (action) => action.onPressed?.call(),
      itemBuilder: (_) => [
        for (final action in actions)
          PopupMenuItem(value: action, child: Row(children: [
            EbrokerIcon(action.icon, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(action.label)),
          ])),
      ],
    );
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
    return _BrokerAvailabilityBody(key: ValueKey((scope, epoch, actor)), initiallyDue: initiallyDue);
  }
}

class _BrokerAvailabilityBody extends ConsumerStatefulWidget {
  const _BrokerAvailabilityBody({required this.initiallyDue, super.key});
  final bool initiallyDue;
  @override
  ConsumerState<_BrokerAvailabilityBody> createState() => _BrokerAvailabilityState();
}
class _BrokerAvailabilityState extends ConsumerState<_BrokerAvailabilityBody> {
  final _selected = <int>{};
  bool _busy = false, _initialized = false;
  Object? _snapshot;
  late bool _onlyDue;
  @override
  void initState() { super.initState(); _onlyDue = widget.initiallyDue; }

  Future<void> _confirm(List<int> ids) async {
    if (ids.isEmpty || _busy) return;
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    final scope = ref.read(accountRequestScopeProvider);
    bool current() => mounted && scope.isCurrent && epoch == Stage6SecureSessionStore.instance.sessionEpoch;
    setState(() => _busy = true);
    try {
      await ref.read(brokerRepositoryProvider).updateAvailability(ids, 'available');
      if (!current()) return;
      _selected.removeAll(ids);
      _initialized = false;
      refreshBrokerData(ref);
    } catch (error) {
      if (mounted && current()) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    } finally { if (current()) setState(() => _busy = false); }
  }

  void _filter(bool due) {
    if (_onlyDue == due) return;
    setState(() { _onlyDue = due; _selected.clear(); _initialized = false; _snapshot = null; });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(brokerAvailabilityPagesProvider(_onlyDue));
    final controller = ref.read(brokerAvailabilityPagesProvider(_onlyDue).notifier);
    final items = state.items;
    if (!identical(_snapshot, controller)) {
      _snapshot = controller; _selected.clear(); _initialized = false;
    }
    if (!_initialized && state.page != null && !state.loading) {
      _selected.addAll(items.where((item) => item.needsConfirmation || item.status == 'confirmation_paused').map((item) => item.id));
      _initialized = true;
    }
    return BrokerScaffold(appBar: const AppAppBar(title: 'تحديث توفر الإعلانات'),
      body: state.loading && items.isEmpty ? const AppLoadingState()
        : state.error != null && items.isEmpty ? AppErrorState(message: friendlyApiError(state.error!), onRetry: controller.refresh)
        : RefreshIndicator(onRefresh: () async { _selected.clear(); _initialized = false; await controller.refresh(); },
          child: ListView(key: ObjectKey(controller), padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(), children: [
            if (state.loading || state.error != null) AppRefreshStatus(loading: state.loading,
              error: state.error == null ? null : friendlyApiError(state.error!), onRetry: controller.refresh),
            const Text('أكد إعلانات البيع كل 14 يومًا والإيجار كل 7 أيام. الإعلانات المتوقفة بسبب التأكيد تعود عند تحديث التوفر ما دامت معتمدة.'),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              EbrokerChoiceChip(label: const Text('تحتاج تأكيد التوفر'), selected: _onlyDue, onSelected: (_) => _filter(true)),
              EbrokerChoiceChip(label: const Text('كل إعلاناتي'), selected: !_onlyDue, onSelected: (_) => _filter(false)),
            ]),
            const SizedBox(height: 12),
            if (items.isEmpty) const BrokerPanel(child: Text('لا توجد إعلانات في هذه القائمة حاليًا.'))
            else ...[
              CheckboxListTile(contentPadding: EdgeInsets.zero,
                title: Text(state.page!.hasMore ? 'اختيار الإعلانات المحمّلة' : 'اختيار الكل'),
                value: items.every((item) => _selected.contains(item.id)),
                onChanged: _busy ? null : (value) => setState(() {
                  _selected.clear(); if (value == true) _selected.addAll(items.map((item) => item.id));
                })),
              for (final item in items) Padding(padding: const EdgeInsets.only(bottom: 8),
                child: BrokerPanel(key: ValueKey('broker-availability-${item.id}'), child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero, value: _selected.contains(item.id),
                  onChanged: _busy ? null : (value) => setState(() { value == true ? _selected.add(item.id) : _selected.remove(item.id); }),
                  title: Text(item.title), subtitle: Text(item.label), controlAffinity: ListTileControlAffinity.leading))),
              const SizedBox(height: 12),
              AppButton(label: _busy ? 'جار التأكيد' : 'ما زالت متوفرة (${_selected.length})', icon: Icons.check_circle_outline,
                onPressed: _busy || _selected.isEmpty || state.loading || state.error != null ? null : () => _confirm(_selected.take(100).toList()), expand: true),
              if (_selected.length > 100) const Padding(padding: EdgeInsets.only(top: 8), child: Text('تحدث أول 100 إعلان في هذه الدفعة، ثم أكمل البقية.')),
              const SizedBox(height: 8), TextButton(onPressed: () => context.push('/my-listings'), child: const Text('تحديد الإعلانات المباعة أو المؤجرة من عقاراتي')),
            ],
            if (state.loadingMore || state.pageError != null) AppRefreshStatus(
              key: const ValueKey('broker-availability-page-status'), loading: state.loadingMore,
              error: state.pageError == null ? null : friendlyApiError(state.pageError!), onRetry: controller.loadMore)
            else if (state.page?.hasMore ?? false) TextButton.icon(key: const ValueKey('broker-availability-more'),
              onPressed: state.loading || state.error != null ? null : controller.loadMore,
              icon: const Icon(Icons.expand_more), label: const Text('المزيد من الإعلانات')),
          ])));
  }
}

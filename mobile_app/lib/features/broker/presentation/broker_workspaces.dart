import '../data/customer_help_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_error_message.dart';
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
    return BrokerScaffold(appBar: AppAppBar(title: user?.isOffice == true ? 'لوحة المكتب' : 'لوحة الدلال', actions: [
      IconButton(tooltip: 'الإشعارات', onPressed: () => context.push('/notifications'), icon: const EbrokerImage('notification', size: 22)),
    ]), body: ref.watch(brokerWorkspaceProvider).when(loading: () => const AppLoadingState(),
      error: (error, _) => AppErrorState(message: friendlyApiError(error), onRetry: () => ref.invalidate(brokerWorkspaceProvider)),
      data: (data) {
        final profile = data['broker_profile'] is Map ? BrokerProfile.fromJson(brokerMap(data['broker_profile'])) : null;
        final listings = brokerMap(data['listings']), activity = brokerMap(data['customer_activity']);
        final attention = brokerMap(data['needs_attention']), finance = brokerMap(data['financial_summary']);
        final corrections = brokerRows(attention['correction_listings']).length;
        final priorities = <({String text, String route, IconData icon})>[
          if (finance['listing_creation_blocked'] == true) (text: 'لديك مستحق للمنصة يحتاج تسوية', route: '/broker/finance', icon: Icons.account_balance_wallet_outlined),
          if (brokerInt(activity['unread_conversations']) > 0) (text: '${brokerInt(activity['unread_conversations'])} محادثات تحتاج ردك', route: '/broker/customers?filter=unread', icon: Icons.chat_bubble_outline),
          if (brokerInt(attention['customer_followups_due']) > 0) (text: '${brokerInt(attention['customer_followups_due'])} عملاء حان موعد متابعتهم', route: '/broker/customers?filter=followup_due', icon: Icons.event_note_outlined),
          if (corrections > 0) (text: '$corrections إعلانات تحتاج تصحيحًا', route: '/my-listings', icon: Icons.edit_outlined),
          if (brokerInt(attention['availability_count']) > 0) (text: '${brokerInt(attention['availability_count'])} إعلانات تحتاج تأكيد التوفر', route: '/broker/availability', icon: Icons.update),
          if (brokerInt(attention['pending_deal_count']) > 0) (text: 'تابع نتائج الصفقات التي تنتظر التأكيد', route: '/broker/activity', icon: Icons.check_circle_outline),
        ];
        final tools = <({String label, IconData icon, VoidCallback? action})>[
          (label: 'عقاراتي', icon: Icons.home_work_outlined, action: () => context.push('/my-listings')),
          (label: 'الصفقات', icon: Icons.handshake_outlined, action: () => context.push('/broker/activity')),
          (label: 'التوفر', icon: Icons.update, action: () => context.push('/broker/availability?due=1')),
          (label: 'المستحقات', icon: Icons.account_balance_wallet_outlined, action: () => context.push('/broker/finance')),
          (label: 'الإحصاءات', icon: Icons.bar_chart_outlined, action: () => _statistics(context, profile, listings, activity)),
          (label: 'ملفي العام', icon: Icons.badge_outlined, action: profile == null ? null : () => context.push('/advertisers/${profile.id}')),
        ];
        Widget priority(({String text, String route, IconData icon}) item) => InkWell(onTap: () => context.push(item.route),
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [
            EbrokerIcon(item.icon, size: 19, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 10),
            Expanded(child: Text(item.text)), const EbrokerIcon(Icons.chevron_left, size: 17),
          ])));
        return RefreshIndicator(onRefresh: () async { ref.invalidate(brokerWorkspaceProvider); await ref.read(brokerWorkspaceProvider.future); },
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), physics: const AlwaysScrollableScrollPhysics(), children: [
            BrokerPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [ClipOval(child: profile?.photoUrl == null ? const EbrokerImage('defaultProfileIcon', size: 44)
                : Image.network(profile!.photoUrl!, width: 44, height: 44, fit: BoxFit.cover, cacheWidth: 160,
                    errorBuilder: (_, __, ___) => const EbrokerImage('defaultProfileIcon', size: 44))), const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(profile?.name ?? user?.name ?? 'مرحبًا بك', style: Theme.of(context).textTheme.titleMedium),
                  Text('${profile?.typeLabel ?? 'دلال'} موثق${profile?.governorate == null ? '' : ' · ${profile!.governorate}'}', style: Theme.of(context).textTheme.bodySmall),
                ])),
              ]), const SizedBox(height: 10),
              Wrap(spacing: 14, runSpacing: 6, children: [
                Text('${profile?.activeListings ?? brokerInt(listings['published'])} عقارات نشطة'),
                Text('${brokerInt(activity['completed_deals'])} صفقات مكتملة مؤكدة'),
                if (profile != null && profile.ratingCount > 0) Text.rich(TextSpan(children: [
                  const WidgetSpan(alignment: PlaceholderAlignment.middle, child: EbrokerIcon(Icons.star_outline, size: 16, color: Colors.amber)),
                  TextSpan(text: ' ${profile.rating.toStringAsFixed(1)} · ${profile.ratingCount} تقييمًا'),
                ])),
              ]),
            ])), const SizedBox(height: 16),
            Text('يحتاج إجراء منك', style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 8),
            BrokerPanel(child: priorities.isEmpty ? const Text('أنت متابع كل شيء. لا توجد إجراءات معلقة الآن.') : Column(children: [
              for (final item in priorities.take(3)) priority(item),
              if (priorities.length > 3) ExpansionTile(tilePadding: EdgeInsets.zero, title: Text('إجراءات أخرى (${priorities.length - 3})'),
                children: [for (final item in priorities.skip(3)) priority(item)]),
            ])), const SizedBox(height: 8),
            const SizedBox(height: 12), Text('أدوات عملك', style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 12),
            LayoutBuilder(builder: (context, size) {
              final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
              final columns = scale > 1.7 || size.maxWidth < 320 ? 1 : 2;
              final width = (size.maxWidth - (columns - 1) * 10) / columns;
              return Wrap(spacing: 10, runSpacing: 10, children: [for (final tool in tools)
                SizedBox(width: width, child: AppSurface(key: ValueKey('broker-tool-${tool.label}'), onTap: tool.action,
                  child: Row(children: [Container(padding:const EdgeInsets.all(10),decoration:BoxDecoration(
                    color:Theme.of(context).colorScheme.secondaryContainer,borderRadius:BorderRadius.circular(14)),
                    child:Icon(tool.icon,size:23,color:Theme.of(context).colorScheme.secondary)), const SizedBox(width:10),
                    Expanded(child:Text(tool.label,style:Theme.of(context).textTheme.labelMedium))]))),
              ]);
            }),
          ]));
      }));
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

class BrokerCustomersScreen extends ConsumerStatefulWidget {
  const BrokerCustomersScreen({this.propertyId, this.selectForDeal = false, this.initialFilter = 'all', this.embedded = false, super.key});
  final int? propertyId;
  final bool selectForDeal;
  final bool embedded;
  final String initialFilter;
  @override
  ConsumerState<BrokerCustomersScreen> createState() => _BrokerCustomersState();
}
class _BrokerCustomersState extends ConsumerState<BrokerCustomersScreen> {
  final _items = <BrokerCustomer>[];
  bool _loading = true, _moreBusy = false, _helpReady = false, _helpSeen = true;
  int? _helpActorId;

  Future<void> _loadHelp() async {
    final actor = await ref.read(authControllerProvider.future);
    if (!mounted || actor == null) return;
    final seen = await ref.read(customerHelpStoreProvider).seen(actor.id);
    if (mounted && ref.read(authControllerProvider).asData?.value?.id == actor.id) setState(() { _helpActorId = actor.id; _helpReady = true; _helpSeen = seen; });
  }
  Future<void> _rememberHelp() async {
    final id = _helpActorId ?? ref.read(authControllerProvider).asData?.value?.id;
    if (id == null || ref.read(authControllerProvider).asData?.value?.id != id) return;
    if (mounted) setState(() => _helpSeen = true);
    await ref.read(customerHelpStoreProvider).markSeen(id);
  }
  String? _stage, _error;
  late String _filter;
  int _page = 1, _lastPage = 1, _request = 0;
  @override
  void initState() { super.initState(); _filter = const ['unread', 'followup_due'].contains(widget.initialFilter) ? widget.initialFilter : 'all'; Future.microtask(() async { await _loadHelp(); if (mounted) await _load(); }); }
  Future<void> _load({bool more = false}) async {
    final request = ++_request;
    if (more) { setState(() => _moreBusy = true); } else { setState(() { _loading = true; _error = null; }); }
    try {
      final result = await ref.read(brokerRepositoryProvider).customers(stage: _stage, propertyId: widget.propertyId, filter: _filter, page: more ? _page + 1 : 1);
      if (!mounted || request != _request) return;
      if (result.items.any((item) => item.stage != 'new' || item.privateNote.isNotEmpty || item.remindAt != null)) await _rememberHelp();
      if (!mounted) return;
      setState(() { if (!more) _items.clear(); _items.addAll(result.items); _page = result.page; _lastPage = result.lastPage; _loading = false; _moreBusy = false; });
    } catch (error) { if (mounted && request == _request) setState(() { _error = friendlyApiError(error); _loading = false; _moreBusy = false; }); }
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
    appBar: widget.embedded ? null : AppAppBar(title: widget.selectForDeal ? 'اختر عميل الصفقة' : 'إدارة العملاء'),
    body: _loading ? const AppLoadingState() : _error != null ? AppErrorState(message: _error!, onRetry: _load) : RefreshIndicator(onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), physics: const AlwaysScrollableScrollPhysics(), children: [
        if (!widget.selectForDeal) ...[
          Text('إدارة العملاء', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          const Text('رتّب عملاءك وتابع كل شخص حسب مرحلته، من أول تواصل حتى إغلاق الصفقة.'),
          const SizedBox(height: 12),
          if (_helpReady && !_helpSeen) BrokerPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('من قائمة العميل (…) يمكنك تغيير الحالة، إضافة ملاحظة خاصة، أو تحديد موعد متابعة.'),
            Align(alignment: AlignmentDirectional.centerEnd, child: TextButton(key: const ValueKey('customer-help-dismiss'), onPressed: _rememberHelp, child: const Text('فهمت'))),
          ])),
          const SizedBox(height: 10),
        ],
        if (!widget.selectForDeal) Padding(padding: const EdgeInsets.only(bottom: 10), child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final entry in const {'all': 'كل العملاء', 'unread': 'تحتاج ردك', 'followup_due': 'حان موعد المتابعة'}.entries) EbrokerChoiceChip(
            label: Text(entry.value), selected: _filter == entry.key, onSelected: (_) { setState(() => _filter = entry.key); _load(); }),
        ])),
        if (!widget.selectForDeal) AppSelectField<String>(value: _stage, isExpanded: true, hint: const Text('كل الحالات'), decoration: const InputDecoration(labelText: 'حالة المتابعة'),
          items: [const DropdownMenuItem(value: null, child: Text('كل الحالات')), for (final entry in brokerLeadLabels.entries) DropdownMenuItem(value: entry.key, child: Text(entry.value))],
          onChanged: (value) { setState(() => _stage = value); _load(); }),
        const SizedBox(height: 12),
        if (_items.isEmpty) const BrokerPanel(child: Text('لا توجد عملاء في هذه القائمة بعد. ستظهر هنا المحادثات المرتبطة بإعلاناتك.')),
        for (final item in _items) Padding(padding: const EdgeInsets.only(bottom: 10), child: BrokerPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Container(padding:const EdgeInsets.all(11),decoration:BoxDecoration(color:Theme.of(context).colorScheme.secondaryContainer,borderRadius:BorderRadius.circular(15)),child:Icon(Icons.person_outline_rounded,size:22,color:Theme.of(context).colorScheme.secondary)), const SizedBox(width: 10), Expanded(child: Text(item.customerName, style: Theme.of(context).textTheme.titleSmall)),
            if (item.unreadCount > 0) AppStatusBadge(label: '${item.unreadCount} غير مقروءة', tone: AppStatusTone.info),

          ]),
          const SizedBox(height: 4), Text(item.propertyTitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 10), AppStatusBadge(label: item.deal?.statusLabel ?? item.stageLabel, tone: item.stage == 'completed' ? AppStatusTone.success : AppStatusTone.info),
          const SizedBox(height: 10),
          if (widget.selectForDeal) AppButton(label: 'الصفقة مع هذا العميل', expand: true, onPressed: () => Navigator.of(context).pop(item))
          else ...[
            if (item.privateNote.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('ملاحظة خاصة: ${item.privateNote}', maxLines: 2, overflow: TextOverflow.ellipsis)),
            if (item.remindAt != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('${item.followupDue ? 'حان موعد المتابعة' : 'المتابعة'}: ${followupDateLabel(item.remindAt!)}')),
            EbrokerCardActions(actions: [
              EbrokerCardAction(item.unreadCount > 0 ? 'الرد على العميل' : 'المحادثة', () async { await context.push('/messages/${item.threadId}'); if (mounted) _load(); }, icon: Icons.chat_bubble_outline),
              if (item.stage != 'completed') EbrokerCardAction('تحديث حالة المتابعة', () => _chooseStage(item), icon: Icons.swap_horiz_rounded),
              EbrokerCardAction('ملاحظة وتذكير', () async { final saved = await editCustomerFollowup(context, ref, item.threadId, customer: item); if (saved && mounted) { await _rememberHelp(); if (mounted) _load(); } }, icon: Icons.event_note_outlined),
              EbrokerCardAction('العقار', () => context.push('/properties/${item.propertyId}'), icon: Icons.home_outlined),
              if (item.deal != null) EbrokerCardAction('نتيجة الصفقة', () => context.push('/broker/deals/${item.deal!.id}'), icon: Icons.check_circle_outline),
            ]),
          ],
        ]))),
        if (_page < _lastPage) AppButton(label: _moreBusy ? 'جار التحميل' : 'تحميل المزيد', onPressed: _moreBusy ? null : () => _load(more: true)),
      ])),
  );
}

class BrokerAvailabilityScreen extends ConsumerStatefulWidget {
  const BrokerAvailabilityScreen({this.initiallyDue = false, super.key});
  final bool initiallyDue;
  @override
  ConsumerState<BrokerAvailabilityScreen> createState() => _BrokerAvailabilityState();
}
class _BrokerAvailabilityState extends ConsumerState<BrokerAvailabilityScreen> {
  final _selected = <int>{};
  bool _busy = false, _initialized = false;
  late bool _onlyDue;
  @override
  void initState() { super.initState(); _onlyDue = widget.initiallyDue; }
  Future<void> _confirm(List<int> ids) async {
    if (ids.isEmpty || _busy) return;
    setState(() => _busy = true);
    try { await ref.read(brokerRepositoryProvider).updateAvailability(ids, 'available'); refreshBrokerData(ref); _selected.removeAll(ids); }
    catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error)))); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) => BrokerScaffold(
    appBar: const AppAppBar(title: 'تحديث توفر الإعلانات'),
    body: ref.watch(brokerAvailabilityProvider).when(loading: () => const AppLoadingState(),
      error: (error, _) => AppErrorState(message: friendlyApiError(error), onRetry: () => ref.invalidate(brokerAvailabilityProvider)),
      data: (allItems) {
        final items = _onlyDue ? allItems.where((i) => i.needsConfirmation || i.status == 'confirmation_paused').toList() : allItems;
        if (!_initialized) { _selected.addAll(items.where((i) => i.needsConfirmation || i.status == 'confirmation_paused').map((i) => i.id)); _initialized = true; }
        return RefreshIndicator(onRefresh: () async { ref.invalidate(brokerAvailabilityProvider); await ref.read(brokerAvailabilityProvider.future); },
          child: ListView(padding: const EdgeInsets.all(16), physics: const AlwaysScrollableScrollPhysics(), children: [
            const Text('أكد إعلانات البيع كل 14 يومًا والإيجار كل 7 أيام. الإعلانات المتوقفة بسبب التأكيد تعود عند تحديث التوفر ما دامت معتمدة.'),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              EbrokerChoiceChip(label: const Text('تحتاج تأكيد التوفر'), selected: _onlyDue,
                onSelected: (_) => setState(() { _onlyDue = true; _selected.clear(); _initialized = false; })),
              EbrokerChoiceChip(label: const Text('كل إعلاناتي'), selected: !_onlyDue,
                onSelected: (_) => setState(() { _onlyDue = false; _selected.clear(); _initialized = false; })),
            ]),
            const SizedBox(height: 12),
            if (items.isEmpty) const BrokerPanel(child: Text('لا توجد إعلانات تحتاج تحديث التوفر حاليًا.'))
            else ...[
              CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('اختيار الكل'), value: items.every((i) => _selected.contains(i.id)),
                onChanged: _busy ? null : (value) => setState(() { _selected.clear(); if (value == true) _selected.addAll(items.map((i) => i.id)); })),
              for (final item in items) Padding(padding: const EdgeInsets.only(bottom: 8), child: BrokerPanel(child: CheckboxListTile(
                contentPadding: EdgeInsets.zero, value: _selected.contains(item.id), onChanged: _busy ? null : (value) => setState(() { value == true ? _selected.add(item.id) : _selected.remove(item.id); }),
                title: Text(item.title), subtitle: Text(item.label), controlAffinity: ListTileControlAffinity.leading))),
              const SizedBox(height: 12),
              AppButton(label: _busy ? 'جار التأكيد' : 'ما زالت متوفرة (${_selected.length})', icon: Icons.check_circle_outline,
                onPressed: _busy || _selected.isEmpty ? null : () => _confirm(_selected.take(100).toList()), expand: true),
              if (_selected.length > 100) const Padding(padding: EdgeInsets.only(top: 8), child: Text('تحدث أول 100 إعلان في هذه الدفعة، ثم أكمل البقية.')),
              const SizedBox(height: 8), TextButton(onPressed: () => context.push('/my-listings'), child: const Text('تحديد الإعلانات المباعة أو المؤجرة من عقاراتي')),
            ],
          ]));
      }),
  );
}

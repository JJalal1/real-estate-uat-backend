import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/ebroker_widgets.dart';
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
      border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: .35)), borderRadius: BorderRadius.circular(12)),
    child: child,
  );
}

class BrokerDashboardScreen extends ConsumerWidget {
  const BrokerDashboardScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(brokerWorkspaceProvider);
    final user = ref.watch(authControllerProvider).asData?.value;
    return BrokerScaffold(
      appBar: AppAppBar(title: user?.isOffice == true ? 'لوحة المكتب' : user?.isOwner == true ? 'لوحة المعلن' : 'لوحة الدلال', actions: [
        IconButton(tooltip: 'الإشعارات', onPressed: () => context.push('/notifications'), icon: const EbrokerImage('notification', size: 22)),
      ]),
      body: state.when(loading: () => const AppLoadingState(),
        error: (error, _) => AppErrorState(message: friendlyApiError(error), onRetry: () => ref.invalidate(brokerWorkspaceProvider)),
        data: (data) {
          final profile = data['broker_profile'] is Map ? BrokerProfile.fromJson(brokerMap(data['broker_profile'])) : null;
          final listings = brokerMap(data['listings']), activity = brokerMap(data['customer_activity']);
          final attention = brokerMap(data['needs_attention']), finance = brokerMap(data['financial_summary']);
          final corrections = brokerRows(attention['correction_listings']).length;
          final priorities = <({String text, String route, IconData icon})>[
            if (brokerInt(activity['unread_conversations']) > 0) (text: '${brokerInt(activity['unread_conversations'])} محادثات تحتاج ردك', route: '/broker/customers', icon: Icons.chat_bubble_outline),
            if (brokerInt(activity['active_viewings']) > 0) (text: '${brokerInt(activity['active_viewings'])} معاينات للمتابعة', route: '/broker/activity', icon: Icons.event_outlined),
            if (corrections > 0) (text: '$corrections إعلانات تحتاج تصحيحًا', route: '/my-listings', icon: Icons.edit_outlined),
            if (brokerInt(attention['availability_count']) > 0) (text: '${brokerInt(attention['availability_count'])} إعلانات تحتاج تأكيد التوفر', route: '/broker/availability', icon: Icons.update),
            if (brokerInt(attention['pending_deal_count']) > 0) (text: 'تابع نتائج الصفقات التي تنتظر التأكيد', route: '/broker/activity', icon: Icons.check_circle_outline),
            if (finance['listing_creation_blocked'] == true) (text: 'لديك مستحق للمنصة يحتاج تسوية', route: '/broker/finance', icon: Icons.account_balance_wallet_outlined),
          ];
          return RefreshIndicator(onRefresh: () async { ref.invalidate(brokerWorkspaceProvider); await ref.read(brokerWorkspaceProvider.future); },
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), physics: const AlwaysScrollableScrollPhysics(), children: [
              BrokerPanel(child: Row(children: [
                const EbrokerImage('defaultProfileIcon', size: 38), const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(profile?.name ?? user?.name ?? 'مرحبًا بك', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  Text('${profile?.typeLabel ?? 'معلن'} موثق${profile?.governorate == null ? '' : ' · ${profile!.governorate}'}'),
                  if (profile != null && profile.ratingCount > 0) Text('⭐ ${profile.rating.toStringAsFixed(1)} · ${profile.ratingCount} تقييمًا'),
                ])),
                if (profile != null) IconButton(tooltip: 'ملفي العام', onPressed: () => context.push('/advertisers/${profile.id}'), icon: const EbrokerIcon(Icons.open_in_new, size: 20)),
              ])),
              const SizedBox(height: 20),
              Text('يحتاج إجراء منك', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              BrokerPanel(child: priorities.isEmpty ? const Text('أنت متابع كل شيء. لا توجد إجراءات معلقة الآن.') : Column(children: [
                for (var i = 0; i < priorities.length; i++) ...[
                  if (i > 0) const Divider(height: 16),
                  InkWell(onTap: () => context.push(priorities[i].route), child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
                    EbrokerIcon(priorities[i].icon, size: 20), const SizedBox(width: 10), Expanded(child: Text(priorities[i].text)),
                    const EbrokerIcon(Icons.chevron_left, size: 18),
                  ]))),
                ],
              ])),
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: [
                AppButton(label: 'إضافة عقار', icon: Icons.add, onPressed: () => context.push('/add-property')),
                AppButton(label: 'تحديث التوفر', icon: Icons.update, onPressed: () => context.push('/broker/availability')),
                AppButton(label: 'المستحقات', icon: Icons.account_balance_wallet_outlined, onPressed: () => context.push('/broker/finance')),
              ]),
              const SizedBox(height: 20),
              LayoutBuilder(builder: (context, size) {
                final oneColumn = size.maxWidth < 330 || MediaQuery.textScalerOf(context).scale(14) > 22;
                final width = oneColumn ? size.maxWidth : (size.maxWidth - 12) / 2;
                return Wrap(spacing: 12, runSpacing: 12, children: [
                  for (final metric in <({int count, String label, String route})>[
                    (count: brokerInt(listings['published']), label: 'إعلانات منشورة', route: '/my-listings'),
                    (count: brokerInt(activity['new_customers_this_week']), label: 'عملاء جدد هذا الأسبوع', route: '/broker/customers'),
                    (count: brokerInt(activity['active_viewings']), label: 'معاينات نشطة', route: '/broker/activity'),
                    (count: brokerInt(activity['completed_deals']), label: 'صفقات مكتملة مؤكدة', route: '/broker/activity'),
                  ]) SizedBox(width: width, child: InkWell(onTap: () => context.push(metric.route), child: BrokerPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${metric.count}', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
                    const SizedBox(height: 4), Text(metric.label),
                  ])))),
                ]);
              }),
              if (data['best_listing'] is Map && brokerInt(brokerMap(data['best_listing'])['view_count']) > 0) ...[
                const SizedBox(height: 16), BrokerPanel(child: Text('أكثر إعلان جذب مشاهدة: ${brokerMap(data['best_listing'])['title']}')),
              ],
            ]));
        }),
    );
  }
}

class BrokerCustomersScreen extends ConsumerStatefulWidget {
  const BrokerCustomersScreen({this.propertyId, this.selectForDeal = false, super.key});
  final int? propertyId;
  final bool selectForDeal;
  @override
  ConsumerState<BrokerCustomersScreen> createState() => _BrokerCustomersState();
}
class _BrokerCustomersState extends ConsumerState<BrokerCustomersScreen> {
  final _items = <BrokerCustomer>[];
  bool _loading = true, _moreBusy = false;
  String? _stage, _error;
  int _page = 1, _lastPage = 1, _request = 0;
  @override
  void initState() { super.initState(); Future.microtask(_load); }
  Future<void> _load({bool more = false}) async {
    final request = ++_request;
    if (more) { setState(() => _moreBusy = true); } else { setState(() { _loading = true; _error = null; }); }
    try {
      final result = await ref.read(brokerRepositoryProvider).customers(stage: _stage, propertyId: widget.propertyId, page: more ? _page + 1 : 1);
      if (!mounted || request != _request) return;
      setState(() { if (!more) _items.clear(); _items.addAll(result.items); _page = result.page; _lastPage = result.lastPage; _loading = false; _moreBusy = false; });
    } catch (error) { if (mounted && request == _request) setState(() { _error = friendlyApiError(error); _loading = false; _moreBusy = false; }); }
  }
  Future<void> _change(BrokerCustomer item, String stage) async {
    try { await ref.read(brokerRepositoryProvider).updateCustomer(item.threadId, stage); refreshBrokerData(ref); await _load(); }
    catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error)))); }
  }
  @override
  Widget build(BuildContext context) => BrokerScaffold(
    appBar: AppAppBar(title: widget.selectForDeal ? 'اختر عميل الصفقة' : 'العملاء'),
    body: _loading ? const AppLoadingState() : _error != null ? AppErrorState(message: _error!, onRetry: _load) : RefreshIndicator(onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), physics: const AlwaysScrollableScrollPhysics(), children: [
        if (!widget.selectForDeal) DropdownButtonFormField<String>(value: _stage, isExpanded: true, hint: const Text('كل العملاء'), decoration: const InputDecoration(labelText: 'حالة المتابعة'),
          items: [const DropdownMenuItem(value: null, child: Text('كل العملاء')), for (final entry in brokerLeadLabels.entries) DropdownMenuItem(value: entry.key, child: Text(entry.value))],
          onChanged: (value) { setState(() => _stage = value); _load(); }),
        const SizedBox(height: 12),
        if (_items.isEmpty) const BrokerPanel(child: Text('لا توجد عملاء في هذه القائمة بعد. ستظهر هنا المحادثات المرتبطة بإعلاناتك.')),
        for (final item in _items) Padding(padding: const EdgeInsets.only(bottom: 10), child: BrokerPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const EbrokerIcon(Icons.person_outline, size: 22), const SizedBox(width: 8), Expanded(child: Text(item.customerName, style: Theme.of(context).textTheme.titleMedium)),
            if (!widget.selectForDeal && item.stage != 'completed') PopupMenuButton<String>(tooltip: 'تحديث حالة العميل',
              onSelected: (value) => _change(item, value), itemBuilder: (_) => [for (final entry in brokerLeadLabels.entries.where((e) => e.key != 'completed')) PopupMenuItem(value: entry.key, child: Text(entry.value))]),
          ]),
          const SizedBox(height: 4), Text(item.propertyTitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8), Text(item.deal?.statusLabel ?? item.stageLabel, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          const SizedBox(height: 10),
          if (widget.selectForDeal) AppButton(label: 'الصفقة مع هذا العميل', expand: true, onPressed: () => Navigator.of(context).pop(item))
          else Wrap(spacing: 8, runSpacing: 8, children: [
            AppButton(label: 'المحادثة', icon: Icons.chat_bubble_outline, onPressed: () async { await context.push('/messages/${item.threadId}'); if (mounted) _load(); }),
            AppButton(label: 'العقار', icon: Icons.home_outlined, onPressed: () => context.push('/properties/${item.propertyId}')),
            if (item.deal != null) AppButton(label: 'نتيجة الصفقة', icon: Icons.check_circle_outline, onPressed: () => context.push('/broker/deals/${item.deal!.id}')),
          ]),
        ]))),
        if (_page < _lastPage) AppButton(label: _moreBusy ? 'جار التحميل' : 'تحميل المزيد', onPressed: _moreBusy ? null : () => _load(more: true)),
      ])),
  );
}

class BrokerAvailabilityScreen extends ConsumerStatefulWidget {
  const BrokerAvailabilityScreen({super.key});
  @override
  ConsumerState<BrokerAvailabilityScreen> createState() => _BrokerAvailabilityState();
}
class _BrokerAvailabilityState extends ConsumerState<BrokerAvailabilityScreen> {
  final _selected = <int>{};
  bool _busy = false, _initialized = false;
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
      data: (items) {
        if (!_initialized) { _selected.addAll(items.where((i) => i.needsConfirmation || i.status == 'confirmation_paused').map((i) => i.id)); _initialized = true; }
        return RefreshIndicator(onRefresh: () async { ref.invalidate(brokerAvailabilityProvider); await ref.read(brokerAvailabilityProvider.future); },
          child: ListView(padding: const EdgeInsets.all(16), physics: const AlwaysScrollableScrollPhysics(), children: [
            const Text('أكد إعلانات البيع كل 14 يومًا والإيجار كل 7 أيام. الإعلانات المتوقفة بسبب التأكيد تعود عند تحديث التوفر ما دامت معتمدة.'),
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

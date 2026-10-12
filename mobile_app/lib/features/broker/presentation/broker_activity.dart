import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../../bookings/presentation/bookings_screen.dart';
import '../../community/data/community_repository.dart';
import '../../financial/presentation/receivable_payment_screen.dart';
import '../../messages/domain/message_models.dart';
import '../../messages/presentation/messages_screen.dart';
import '../data/broker_repository.dart';
import '../domain/broker_models.dart';
import 'broker_workspaces.dart';

String brokerMoney(dynamic amount, String currency) => '${brokerNumber(amount).toStringAsFixed(2)} ${currency == 'YER' ? 'ر.ي' : currency}';

Future<void> reportBrokerDeal(BuildContext context, WidgetRef ref, int threadId) async {
  String raw = '';
  final form = GlobalKey<FormState>();
  final amount = await showDialog<double>(context: context, builder: (dialogContext) => AlertDialog(
    title: const Text('تسجيل نتيجة الصفقة'),
    content: SingleChildScrollView(child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('سجّل البيع أو التأجير الذي تم مع هذا العميل خارج التطبيق. سيُغلق الإعلان ويُطلب من العميل تأكيد النتيجة.'),
      const SizedBox(height: 12),
      TextFormField(onChanged: (value) => raw = value, keyboardType: const TextInputType.numberWithOptions(decimal: true),
        validator: (value) => value?.trim().isNotEmpty == true && (_brokerAmount(value!) == null || _brokerAmount(value)! <= 0) ? 'أدخل مبلغًا صحيحًا أكبر من صفر.' : null,
        decoration: const InputDecoration(labelText: 'المبلغ الفعلي', helperText: 'للإيجار: الإيجار الشهري. اتركه فارغًا لاستخدام مبلغ الإعلان.')),
    ]))),
    actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
      AppButton(label: 'إرسال للتأكيد', onPressed: () {
        if (form.currentState?.validate() != true) return;
        Navigator.pop(dialogContext, raw.trim().isEmpty ? -1.0 : _brokerAmount(raw));
      })],
  ));
  if (amount == null || !context.mounted) return;
  try {
    final deal = await ref.read(brokerRepositoryProvider).reportDeal(threadId, amount: amount < 0 ? null : amount);
    refreshBrokerData(ref);
    if (context.mounted) await context.push('/broker/deals/${deal.id}');
  } catch (error) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
  }
}

double? _brokerAmount(String text) {
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  var value = text.trim().replaceAll(',', '').replaceAll('٬', '').replaceAll('٫', '.');
  for (var i = 0; i < 10; i++) { value = value.replaceAll(arabic[i], '$i'); }
  final parsed = double.tryParse(value);
  return parsed?.isFinite == true ? parsed : null;
}

class BrokerActivityScreen extends StatelessWidget {
  const BrokerActivityScreen({this.initialTab = 0, super.key});
  final int initialTab;
  @override
  Widget build(BuildContext context) => DefaultTabController(length: 3, initialIndex: initialTab.clamp(0, 2).toInt(), child: BrokerScaffold(
    appBar: AppBar(title: const Text('نشاطي'), bottom: const TabBar(isScrollable: true, tabs: [
      Tab(text: 'الصفقات'), Tab(text: 'المعاينات'), Tab(text: 'المحادثات'),
    ])),
    body: const TabBarView(children: [BrokerDealsList(), BookingsScreen(embedded: true), MessagesScreen(embedded: true)]),
  ));
}

class BrokerDealsList extends ConsumerStatefulWidget {
  const BrokerDealsList({super.key});
  @override
  ConsumerState<BrokerDealsList> createState() => _BrokerDealsListState();
}
class _BrokerDealsListState extends ConsumerState<BrokerDealsList> {
  final List<BrokerDeal> _items = [];
  bool _loading = true, _more = false;
  int _page = 0;
  String? _error;
  @override
  void initState() { super.initState(); Future.microtask(_load); }
  Future<void> _load({bool next = false}) async {
    setState(() { _loading = true; _error = null; });
    try {
      final page = await ref.read(brokerRepositoryProvider).activity(page: next ? _page + 1 : 1);
      if (!mounted) return;
      setState(() { if (!next) _items.clear(); _items.addAll(page.items); _page = page.page; _more = page.hasMore; _loading = false; });
    } catch (error) { if (mounted) setState(() { _loading = false; _error = friendlyApiError(error); }); }
  }
  @override
  Widget build(BuildContext context) => RefreshIndicator(onRefresh: () => _load(), child: ListView(
    padding: const EdgeInsets.all(16), physics: const AlwaysScrollableScrollPhysics(), children: [
      const Text('يُحتسب الإنجاز بعد تأكيدك وتأكيد العميل. نتيجة مرفوضة أو قيد المراجعة لا تفتح التقييم.'),
      const SizedBox(height: 12),
      for (final deal in _items) Padding(padding: const EdgeInsets.only(bottom: 10), child: BrokerPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(deal.propertyTitle, style: Theme.of(context).textTheme.titleMedium),
        Text('${deal.customerName} · ${deal.statusLabel}'),
        Text(brokerMoney(deal.amount, deal.currency)),
        AppButton(label: deal.canConfirm ? 'تأكيد النتيجة' : 'عرض النتيجة', onPressed: () async { await context.push('/broker/deals/${deal.id}'); if (mounted) await _load(); }),
      ]))),
      if (_loading) const AppLoadingState(),
      if (_error != null) AppErrorState(message: _error!, onRetry: () => _load()),
      if (!_loading && _error == null && _items.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('ستظهر هنا نتائج صفقاتك بعد تسجيلها من محادثة العميل.')),
      if (_more && !_loading) AppButton(label: 'عرض المزيد', onPressed: () => _load(next: true)),
    ],
  ));
}

class BrokerDealScreen extends ConsumerStatefulWidget {
  const BrokerDealScreen({required this.id, super.key});
  final int id;
  @override
  ConsumerState<BrokerDealScreen> createState() => _BrokerDealScreenState();
}
class _BrokerDealScreenState extends ConsumerState<BrokerDealScreen> {
  bool _busy = false;
  Future<void> _decide(bool yes) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: Text(yes ? 'هل تمت الصفقة؟' : 'لم تتم الصفقة؟'),
      content: Text(yes ? 'أكد فقط إن تم البيع أو التأجير بالفعل. سيُحسب الإنجاز ويُفتح التقييم وفق شروط السعي المحفوظة.' : 'سيسجل رفضك ويحيل النتيجة للدعم للمراجعة، دون احتساب صفقة أو مستحق جديد.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('رجوع')),
        AppButton(label: yes ? 'نعم، تمت' : 'لم تتم', onPressed: () => Navigator.pop(c, true))]));
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try { await ref.read(brokerRepositoryProvider).decide(widget.id, yes); refreshBrokerData(ref); ref.invalidate(brokerDealProvider(widget.id)); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(e)))); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _rate(BrokerDeal deal) async {
    int stars = 0;
    String note = '';
    final chosen = await showDialog<int>(context: context, builder: (c) => StatefulBuilder(builder: (c, change) => AlertDialog(
      title: const Text('قيّم تجربتك مع المعلن'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Wrap(children: [for (var i = 1; i <= 5; i++) IconButton(tooltip: '$i نجوم', onPressed: () => change(() => stars = i), icon: Icon(i <= stars ? Icons.star : Icons.star_border, color: Colors.amber, size: 28))]),
        TextField(onChanged: (value) => note = value, maxLength: 1000, maxLines: 3, decoration: const InputDecoration(labelText: 'تعليق اختياري')),
      ])), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
        AppButton(label: 'حفظ التقييم', onPressed: stars == 0 ? null : () => Navigator.pop(c, stars))],
    )));
    final comment = note;
    if (chosen == null || !mounted) return;
    setState(() => _busy = true);
    try { await ref.read(communityRepositoryProvider).rateAdvertiser(advertiserId: deal.advertiserId, rating: chosen, propertyId: deal.propertyId, comment: comment);
      ref.invalidate(brokerProfileProvider(deal.advertiserId)); ref.invalidate(brokerDirectoryProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ تقييمك.')));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(e)))); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) => BrokerScaffold(appBar: const AppAppBar(title: 'نتيجة الصفقة'), body: ref.watch(brokerDealProvider(widget.id)).when(
    loading: () => const AppLoadingState(), error: (e, _) => AppErrorState(message: friendlyApiError(e), onRetry: () => ref.invalidate(brokerDealProvider(widget.id))),
    data: (deal) => ListView(padding: const EdgeInsets.all(16), children: [
      BrokerPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(deal.propertyTitle, style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 8),
        Text(deal.statusLabel, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
        Text('المعلن: ${deal.advertiserName}'), Text('العميل: ${deal.customerName}'), Text('أساس السعي: ${brokerMoney(deal.amount, deal.currency)}'),
      ])), const SizedBox(height: 16),
      if (deal.canConfirm) ...[const Text('هل تم البيع أو التأجير فعلًا مع هذا المعلن؟'), const SizedBox(height: 12),
        AppButton(label: 'نعم، تمت الصفقة', loading: _busy, expand: true, onPressed: _busy ? null : () => _decide(true)),
        const SizedBox(height: 10), AppButton(label: 'لم تتم الصفقة', expand: true, onPressed: _busy ? null : () => _decide(false))],
      if (deal.canRate) AppButton(label: 'تقييم المعلن', icon: Icons.star_outline, expand: true, onPressed: _busy ? null : () => _rate(deal)),
      if (deal.status == 'pending_customer' && !deal.canConfirm) const Text('تم إرسال طلب تأكيد النتيجة للعميل. لن تُحتسب حتى يؤكدها.'),
      if (deal.supportCaseId != null) AppButton(label: 'متابعة مراجعة الدعم', onPressed: () => context.push(deal.canViewSupportCase ? '/support?case=${deal.supportCaseId}' : '/support')),
      const SizedBox(height: 12), AppButton(label: 'فتح المحادثة', icon: Icons.chat_bubble_outline, onPressed: () => context.push('/messages/${deal.threadId}')),
    ]),
  ));
}

class BrokerConversationTools extends ConsumerWidget {
  const BrokerConversationTools({required this.thread, super.key});
  final MessageThreadSummary thread;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (thread.propertyId == null) return const SizedBox.shrink();
    return ref.watch(brokerThreadDealProvider(thread.id)).when(loading: () => const SizedBox.shrink(), error: (_, __) => const SizedBox.shrink(), data: (deal) =>
      Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 8), child: BrokerPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (deal != null) ...[Text(deal.statusLabel), AppButton(label: deal.canConfirm ? 'تأكيد نتيجة الصفقة' : 'عرض نتيجة الصفقة', onPressed: () => context.push('/broker/deals/${deal.id}'))]
        else if (thread.canManageCustomer) ...[
          Text(brokerLeadLabels[thread.leadStage] ?? 'عميل جديد'),
          Wrap(spacing: 8, children: [AppButton(label: 'تسجيل نتيجة الصفقة', onPressed: () => reportBrokerDeal(context, ref, thread.id)),
            AppButton(label: 'متابعة العميل', onPressed: () => context.push('/broker/customers?property=${thread.propertyId}'))]),
        ] else const Text('يمكنك تأكيد نتيجة الصفقة هنا عندما يسجلها المعلن.'),
      ]))));
  }
}

class BrokerFinanceScreen extends ConsumerWidget {
  const BrokerFinanceScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => BrokerScaffold(appBar: const AppAppBar(title: 'مستحقات المنصة'), body: ref.watch(brokerFinanceProvider).when(
    loading: () => const AppLoadingState(), error: (e, _) => AppErrorState(message: friendlyApiError(e), onRetry: () => ref.invalidate(brokerFinanceProvider)),
    data: (data) => RefreshIndicator(onRefresh: () async { ref.invalidate(brokerFinanceProvider); await ref.read(brokerFinanceProvider.future); }, child: ListView(
      physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16), children: [
        for (final balance in brokerRows(data['balances'])) Padding(padding: const EdgeInsets.only(bottom: 12), child: BrokerPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('المستحق: ${brokerMoney(balance['open'], '${balance['currency']}')}', style: Theme.of(context).textTheme.titleMedium),
          Text('المدفوع: ${brokerMoney(balance['paid'], '${balance['currency']}')}'),
        ]))),
        const Text('تظهر هنا حصة المنصة من السعي وفق الشروط المحفوظة للصفقة، بعد تأكيد الطرفين.'), const SizedBox(height: 14),
        for (final due in brokerRows(data['receivables'])) Padding(padding: const EdgeInsets.only(bottom: 12), child: BrokerPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${due['property_title'] ?? 'العقار'}', style: Theme.of(context).textTheme.titleMedium),
          Text('المرجع: ${due['reference']}'),
          Text('أساس الحساب: ${brokerMoney(due['basis_amount'], '${due['currency']}')}'),
          Text('إجمالي السعي: ${brokerMoney(due['sai_amount'], '${due['currency']}')}'),
          Text('حصة المنصة: ${brokerMoney(due['amount_total'], '${due['currency']}')}'),
          Text('المتبقي: ${brokerMoney(due['remaining_amount'], '${due['currency']}')}'),
          Text(_dueStatus('${due['status']}')),
          if (due['due_at'] != null) Text('موعد السداد: ${'${due['due_at']}'.split('T').first}'),
          if (brokerNumber(due['remaining_amount']) > 0 && ['open', 'overdue'].contains(due['status'])) AppButton(label: 'سداد المستحق', onPressed: () async {
            await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ReceivablePaymentScreen(receivableId: brokerInt(due['id']), remainingAmount: brokerNumber(due['remaining_amount']), currency: '${due['currency']}', propertyTitle: '${due['property_title'] ?? 'العقار'}')));
            ref.invalidate(brokerFinanceProvider);
          }),
        ]))),
        if (brokerRows(data['receivables']).isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('لا توجد مستحقات مسجلة حتى الآن.')),
      ],
    )),
  ));
  String _dueStatus(String status) => switch (status) {'paid' => 'تم السداد', 'under_review' => 'إثبات الدفع قيد المراجعة', 'overdue' => 'متأخر السداد', 'disputed' => 'قيد مراجعة الدعم', _ => 'بانتظار السداد'};
}

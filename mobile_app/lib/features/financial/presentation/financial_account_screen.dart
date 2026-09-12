import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../agreements/presentation/agreement_detail_screen.dart';
import '../data/financial_repository.dart';
import '../domain/financial_models.dart';
import 'deal_financial_screen.dart';

class FinancialAccountScreen extends ConsumerStatefulWidget {
  const FinancialAccountScreen({this.showAccountSummary = true, super.key});
  final bool showAccountSummary;

  @override
  ConsumerState<FinancialAccountScreen> createState() => _FinancialAccountScreenState();
}

class _FinancialAccountScreenState extends ConsumerState<FinancialAccountScreen> {
  FinancialAccountSummary? _summary;
  List<FinancialPayment> _payments = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final repo = ref.read(financialRepositoryProvider);
      final payments = await repo.paymentsMine();
      final summary = widget.showAccountSummary ? await repo.account() : null;
      if (!mounted) return;
      setState(() { _payments = payments; _summary = summary; _loading = false; });
    } catch (error) {
      if (!mounted) return;
      setState(() { _error = friendlyApiError(error); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.showAccountSummary ? 'الحساب المالي' : 'مدفوعاتي'),
          actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh))],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _Error(message: _error!, retry: _load)
                : RefreshIndicator(onRefresh: _load, child: _body()),
      ),
    );
  }

  Widget _body() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        if (_summary != null) ...[
          _statusCard(_summary!),
          const SizedBox(height: 16),
          Text('ملخص الحساب', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.65,
            children: [
              _metric('مستحق للمنصة', _money(_summary!.openPlatformDue), Icons.receipt_long_outlined),
              _metric('متأخر', _money(_summary!.overduePlatformDue), Icons.schedule_outlined),
              _metric('مستحق لك', _money(_summary!.pendingPayouts), Icons.account_balance_wallet_outlined),
              _metric('تم تحويله لك', _money(_summary!.paidPayouts), Icons.check_circle_outline),
            ],
          ),
          const SizedBox(height: 20),
        ],
        Text('مدفوعاتي', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (_payments.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('لا توجد عمليات دفع عقارية حتى الآن.')))
        else
          ..._payments.map(_paymentCard),
      ],
    );
  }

  Widget _statusCard(FinancialAccountSummary summary) {
    if (!summary.listingCreationBlocked && !summary.publishedListingsHidden) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.verified_outlined),
          title: Text('الحساب المالي سليم', style: TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('لا توجد مستحقات مالية تمنع إنشاء إعلان جديد.'),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [Icon(Icons.info_outline), SizedBox(width: 8), Expanded(child: Text('يوجد مستحق للمنصة', style: TextStyle(fontWeight: FontWeight.w900)))]),
          const SizedBox(height: 8),
          Text(summary.publishedListingsHidden
              ? 'انتهت مهلة 24 ساعة، لذلك أُخفيت إعلاناتك المنشورة مؤقتًا حتى تأكيد السداد.'
              : 'إنشاء أو إرسال إعلان جديد متوقف مؤقتًا حتى تأكيد سداد المستحق.'),
        ]),
      ),
    );
  }

  Widget _metric(String title, String value, IconData icon) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 20),
            const SizedBox(height: 6),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      );

  Widget _paymentCard(FinancialPayment payment) => Card(
        child: ListTile(
          leading: Icon(payment.status == 'confirmed' ? Icons.check_circle_outline : Icons.payments_outlined),
          title: Text(payment.propertyTitle ?? payment.reference, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${payment.statusLabel} • ${_money(payment.amount, payment.currency)}${payment.reviewNote == null ? '' : '\n${payment.reviewNote}'}'),
          isThreeLine: payment.reviewNote != null,
          trailing: payment.agreementId == null ? null : const Icon(Icons.chevron_left),
          onTap: payment.agreementId == null ? null : () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DealFinancialScreen(agreementId: payment.agreementId!)));
            await _load();
          },
        ),
      );

  String _money(double value, [String currency = 'YER']) {
    final amount = value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2);
    return '$amount $currency';
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: retry, icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
          ]),
        ),
      );
}

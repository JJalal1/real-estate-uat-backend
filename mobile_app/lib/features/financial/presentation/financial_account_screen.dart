import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../data/financial_repository.dart';
import '../domain/financial_models.dart';
import 'deal_financial_screen.dart';
import 'receivable_payment_screen.dart';

class FinancialAccountScreen extends ConsumerStatefulWidget {
  const FinancialAccountScreen({this.showAccountSummary = true, super.key});
  final bool showAccountSummary;

  @override
  ConsumerState<FinancialAccountScreen> createState() =>
      _FinancialAccountScreenState();
}

class _FinancialAccountScreenState extends ConsumerState<FinancialAccountScreen> {
  FinancialAdvertiserAccount? _account;
  List<FinancialPayment> _payments = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final repo = ref.read(financialRepositoryProvider);
      final payments = await repo.paymentsMine();
      final account =
          widget.showAccountSummary ? await repo.advertiserAccount() : null;
      if (!mounted) return;
      setState(() {
        _payments = payments;
        _account = account;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = friendlyApiError(error);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title:
              Text(widget.showAccountSummary ? 'الحساب المالي' : 'مدفوعاتي'),
          actions: [
            IconButton(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh))
          ],
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
    final account = _account;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        if (account != null) ...[
          _statusCard(account.summary),
          const SizedBox(height: 16),
          _title('ملخص الحساب'),
          const SizedBox(height: 8),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.65,
            children: [
              _metric('مستحقات المنصة عليّ',
                  _money(account.summary.openPlatformDue),
                  Icons.receipt_long_outlined),
              _metric('متأخر', _money(account.summary.overduePlatformDue),
                  Icons.schedule_outlined),
              _metric('مستحق لي', _money(account.summary.pendingPayouts),
                  Icons.account_balance_wallet_outlined),
              _metric('تم تحويله لي', _money(account.summary.paidPayouts),
                  Icons.check_circle_outline),
            ],
          ),
          const SizedBox(height: 20),
          _title('مستحقات المنصة عليّ'),
          const SizedBox(height: 8),
          if (account.receivables.isEmpty)
            _empty('لا توجد مستحقات منصة مفتوحة أو سابقة.')
          else
            ...account.receivables.map(_receivableCard),
          const SizedBox(height: 20),
          _title('مستحق لي / التحويلات'),
          const SizedBox(height: 8),
          if (account.payouts.isEmpty)
            _empty('لا توجد تحويلات للمعلن حتى الآن.')
          else
            ...account.payouts.map(_payoutCard),
          const SizedBox(height: 20),
          _title('صفقاتي'),
          const SizedBox(height: 8),
          if (account.deals.isEmpty)
            _empty('لا توجد صفقات مالية مجمدة لهذا الحساب بعد.')
          else
            ...account.deals.map(_dealCard),
          const SizedBox(height: 20),
        ],
        _title('مدفوعاتي'),
        const SizedBox(height: 8),
        if (_payments.isEmpty)
          _empty('لا توجد عمليات دفع عقارية حتى الآن.')
        else
          ..._payments.map(_paymentCard),
      ],
    );
  }

  Widget _receivableCard(Map<String, dynamic> row) {
    final total = _number(row['amount_total']);
    final paid = _number(row['amount_paid']);
    final remaining = (total - paid).clamp(0, double.infinity).toDouble();
    final currency = '${row['currency'] ?? 'YER'}';
    final status = '${row['status'] ?? ''}';
    final dealId = _int(row['deal_financial_term_id']);
    final deal = _account?.deals.cast<Map<String, dynamic>?>().firstWhere(
          (item) => item != null && _int(item['id']) == dealId,
          orElse: () => null,
        );
    final agreementId = deal == null ? 0 : _int(deal['property_agreement_id']);
    final overdue = _isPast(row['due_at']) && remaining > 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(overdue ? Icons.warning_amber_outlined : Icons.receipt_long),
            const SizedBox(width: 8),
            Expanded(
                child: Text('${row['reference'] ?? 'مستحق منصة'}',
                    style: const TextStyle(fontWeight: FontWeight.w900))),
          ]),
          const SizedBox(height: 8),
          _line('المبلغ الأصلي', _money(total, currency)),
          _line('المسدد', _money(paid, currency)),
          _line('المتبقي', _money(remaining, currency)),
          if (row['due_at'] != null) _line('موعد الاستحقاق', '${row['due_at']}'),
          _line('الحالة', overdue ? 'متأخر' : status),
          if (remaining > 0 && agreementId > 0) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  final changed = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => ReceivablePaymentScreen(
                        receivableId: _int(row['id']),
                        agreementId: agreementId,
                        remainingAmount: remaining,
                        currency: currency,
                        propertyTitle: '${row['property_title'] ?? ''}',
                      ),
                    ),
                  );
                  if (changed == true) await _load();
                },
                icon: const Icon(Icons.payments_outlined),
                label: const Text('سداد مستحق المنصة'),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _payoutCard(Map<String, dynamic> row) => Card(
        child: ListTile(
          leading: Icon(row['status'] == 'paid'
              ? Icons.check_circle_outline
              : Icons.account_balance_wallet_outlined),
          title: Text(_money(_number(row['amount']), '${row['currency'] ?? 'YER'}'),
              style: const TextStyle(fontWeight: FontWeight.w900)),
          subtitle: Text(
              '${row['status'] == 'paid' ? 'تم التحويل' : 'بانتظار التحويل'} • ${row['reference'] ?? ''}${row['paid_at'] == null ? '' : '\n${row['paid_at']}'}'),
          isThreeLine: row['paid_at'] != null,
        ),
      );

  Widget _dealCard(Map<String, dynamic> row) {
    final agreementId = _int(row['property_agreement_id']);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.handshake_outlined),
        title: Text('${row['property_title'] ?? 'صفقة عقارية'}'),
        subtitle: Text(
            '${row['transaction_type'] == 'rent' ? 'إيجار' : 'بيع'} • ${_money(_number(row['base_amount']), '${row['currency'] ?? 'YER'}')}\nالسعي: ${_money(_number(row['sai_total_amount']), '${row['currency'] ?? 'YER'}')}'),
        isThreeLine: true,
        trailing: agreementId > 0 ? const Icon(Icons.chevron_left) : null,
        onTap: agreementId <= 0
            ? null
            : () async {
                await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        DealFinancialScreen(agreementId: agreementId)));
                await _load();
              },
      ),
    );
  }

  Widget _statusCard(FinancialAccountSummary summary) {
    if (!summary.listingCreationBlocked && !summary.publishedListingsHidden) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.verified_outlined),
          title: Text('الحساب المالي سليم',
              style: TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('لا توجد مستحقات مالية تمنع إنشاء إعلان جديد.'),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.info_outline),
            SizedBox(width: 8),
            Expanded(
                child: Text('يوجد مستحق للمنصة',
                    style: TextStyle(fontWeight: FontWeight.w900)))
          ]),
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
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20),
                const SizedBox(height: 6),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
        ),
      );

  Widget _paymentCard(FinancialPayment payment) => Card(
        child: ListTile(
          leading: Icon(payment.status == 'confirmed'
              ? Icons.check_circle_outline
              : Icons.payments_outlined),
          title: Text(payment.propertyTitle ?? payment.reference,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
              '${payment.statusLabel} • ${_money(payment.amount, payment.currency)}${payment.reviewNote == null ? '' : '\n${payment.reviewNote}'}'),
          isThreeLine: payment.reviewNote != null,
          trailing:
              payment.agreementId == null ? null : const Icon(Icons.chevron_left),
          onTap: payment.agreementId == null
              ? null
              : () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => DealFinancialScreen(
                          agreementId: payment.agreementId!)));
                  await _load();
                },
        ),
      );

  Widget _title(String value) => Text(value,
      style: Theme.of(context)
          .textTheme
          .titleMedium
          ?.copyWith(fontWeight: FontWeight.w800));
  Widget _empty(String value) =>
      Card(child: Padding(padding: const EdgeInsets.all(18), child: Text(value)));
  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(children: [
          SizedBox(width: 120, child: Text(label)),
          Expanded(
              child: Text(value,
                  style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
      );

  int _int(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;
  double _number(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse('${value ?? 0}') ?? 0;
  bool _isPast(dynamic value) {
    final time = value == null ? null : DateTime.tryParse('$value');
    return time != null && time.isBefore(DateTime.now());
  }

  String _money(double value, [String currency = 'YER']) {
    final amount =
        value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2);
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
            FilledButton.icon(
                onPressed: retry,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة')),
          ]),
        ),
      );
}

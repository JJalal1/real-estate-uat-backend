import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/platform/stage5_media_picker.dart';
import '../data/financial_repository.dart';
import '../domain/financial_models.dart';

class DealFinancialScreen extends ConsumerStatefulWidget {
  const DealFinancialScreen({required this.agreementId, super.key});
  final int agreementId;

  @override
  ConsumerState<DealFinancialScreen> createState() => _DealFinancialScreenState();
}

class _DealFinancialScreenState extends ConsumerState<DealFinancialScreen> {
  FinancialDeal? _deal;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    try {
      final deal = await ref.read(financialRepositoryProvider).deal(widget.agreementId);
      if (!mounted) return;
      setState(() { _deal = deal; _loading = false; _error = null; });
    } catch (error) {
      if (!mounted) return;
      setState(() { _loading = false; _error = friendlyApiError(error); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تسوية الصفقة'),
          actions: [IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh))],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
                : _body(_deal!),
      ),
    );
  }

  Widget _body(FinancialDeal deal) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(deal.propertyTitle, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              _row(deal.isRent ? 'المبلغ المتفق عليه' : 'قيمة الصفقة', _money(deal.baseAmount, deal.currency)),
              if (deal.isRent && deal.monthlyRent != null) _row('الإيجار الشهري', _money(deal.monthlyRent!, deal.currency)),
              if (deal.isRent && deal.rentalTermMonths != null) _row('مدة التأجير', '${deal.rentalTermMonths} شهر'),
              if (deal.isRent && deal.advanceMonths != null) _row('المقدم', '${deal.advanceMonths} شهر'),
              _row('السعي', _money(deal.saiTotalAmount, deal.currency)),
              _row('يتحمل السعي', _payerLabel(deal.saiPayer)),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        if (deal.canPayFull)
          _actionCard(
            title: 'الدفع عبر المنصة',
            subtitle: 'حوّل المبلغ المطلوب ثم ارفع إثبات العملية للتحقق.',
            amount: deal.requiredFullPayment,
            currency: deal.currency,
            icon: Icons.account_balance_wallet_outlined,
            onTap: () => _chooseMethod(deal, 'platform_full', deal.requiredFullPayment),
          ),
        if (deal.canPaySaiOnly) ...[
          const SizedBox(height: 8),
          _actionCard(
            title: 'سداد السعي عبر المنصة',
            subtitle: 'استخدم هذه الطريقة عندما تكون قيمة العقار بين الطرفين مباشرة والسعي عبر المنصة.',
            amount: deal.requiredSaiPayment,
            currency: deal.currency,
            icon: Icons.receipt_long_outlined,
            onTap: () => _chooseMethod(deal, 'platform_sai_only', deal.requiredSaiPayment),
          ),
        ],
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [Icon(Icons.handshake_outlined), SizedBox(width: 8), Expanded(child: Text('تم الدفع مباشرة بين الطرفين', style: TextStyle(fontWeight: FontWeight.w900)))]),
              const SizedBox(height: 8),
              const Text('كل طرف يؤكد بشكل مستقل أن التسوية تمت مباشرة. بعد تأكيد الطرفين ينشأ مستحق السعي للمنصة حسب الشروط المجمدة، وتبدأ مهلة 24 ساعة.'),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _confirmDirect,
                  icon: const Icon(Icons.verified_outlined),
                  label: const Text('أؤكد أن الدفع تم مباشرة'),
                ),
              ),
            ]),
          ),
        ),
        if (deal.payments.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('عمليات الدفع', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          ...deal.payments.map((payment) => Card(
                child: ListTile(
                  title: Text('${payment.statusLabel} • ${_money(payment.amount, payment.currency)}'),
                  subtitle: Text('${payment.reference}${payment.reviewNote == null ? '' : '\n${payment.reviewNote}'}'),
                  isThreeLine: payment.reviewNote != null,
                  trailing: ['waiting_payment', 'correction_required'].contains(payment.status)
                      ? FilledButton.tonal(onPressed: _busy ? null : () => _proofFlow(payment, null), child: const Text('رفع الإثبات'))
                      : null,
                ),
              )),
        ],
      ],
    );
  }

  Widget _actionCard({
    required String title,
    required String subtitle,
    required double amount,
    required String currency,
    required IconData icon,
    required VoidCallback onTap,
  }) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(icon), const SizedBox(width: 8), Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)))]),
            const SizedBox(height: 6),
            Text(subtitle),
            const SizedBox(height: 8),
            Text(_money(amount, currency), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: _busy ? null : onTap, child: const Text('اختيار طريقة الدفع'))),
          ]),
        ),
      );

  Future<void> _chooseMethod(FinancialDeal deal, String mode, double amount) async {
    final method = await showModalBottomSheet<FinancialPaymentMethod>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('اختر طريقة الدفع', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text('المبلغ المطلوب: ${_money(amount, deal.currency)}'),
              const SizedBox(height: 12),
              ...deal.paymentMethods.map((method) => ListTile(
                    enabled: method.available,
                    leading: Icon(_methodIcon(method.key)),
                    title: Text(method.name),
                    subtitle: Text(method.available ? '${method.destinationLabel}: ${method.destinationValue}' : (method.unavailableReason ?? 'غير متاح')),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: method.available ? () => Navigator.pop(context, method) : null,
                  )),
            ]),
          ),
        ),
      ),
    );
    if (method == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final payment = await ref.read(financialRepositoryProvider).createPayment(
            agreementId: deal.agreementId,
            mode: mode,
            paymentMethodId: method.id,
          );
      if (!mounted) return;
      setState(() => _busy = false);
      await _proofFlow(payment, method);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _message(friendlyApiError(error));
    }
  }

  Future<void> _proofFlow(FinancialPayment payment, FinancialPaymentMethod? selectedMethod) async {
    final deal = _deal;
    if (deal == null) return;
    final method = selectedMethod ?? deal.paymentMethods.where((m) => m.name == payment.paymentMethod).firstOrNull;
    if (method == null) {
      _message('تعذر تحديد طريقة الدفع لهذه العملية. حدّث الصفحة وحاول مرة أخرى.');
      return;
    }

    final sender = TextEditingController();
    final phone = TextEditingController();
    final reference = TextEditingController();
    String? pickedPath;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, setDialogState) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text('إثبات الدفع عبر ${method.name}'),
            content: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                _info('المستفيد', method.beneficiaryName),
                _info(method.destinationLabel, method.destinationValue),
                _info('المبلغ', _money(payment.amount, payment.currency)),
                if (method.instructions != null) ...[const SizedBox(height: 6), Text(method.instructions!)],
                const Divider(height: 24),
                TextField(controller: sender, decoration: const InputDecoration(labelText: 'اسم المرسل (اختياري)')),
                if (method.requiresSenderPhone)
                  TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم المرسل')),
                TextField(controller: reference, decoration: InputDecoration(labelText: method.requiresProviderReference ? 'رقم العملية' : 'رقم العملية (اختياري)')),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final paths = await const Stage5MediaPicker().pickImages();
                    if (paths.isNotEmpty) setDialogState(() => pickedPath = paths.first);
                  },
                  icon: Icon(pickedPath == null ? Icons.add_photo_alternate_outlined : Icons.check_circle_outline),
                  label: Text(pickedPath == null ? 'اختيار صورة الإثبات' : 'تم اختيار صورة الإثبات'),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('لاحقًا')),
              FilledButton(
                onPressed: pickedPath == null || (method.requiresSenderPhone && phone.text.trim().isEmpty) || (method.requiresProviderReference && reference.text.trim().isEmpty)
                    ? null
                    : () => Navigator.pop(dialogContext, true),
                child: const Text('إرسال للتحقق'),
              ),
            ],
          ),
        );
      }),
    );
    if (submitted != true || pickedPath == null || !mounted) {
      sender.dispose(); phone.dispose(); reference.dispose();
      await _load();
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(financialRepositoryProvider).submitProof(
            paymentId: payment.id,
            imagePath: pickedPath!,
            senderName: sender.text,
            senderPhone: phone.text,
            providerReference: reference.text,
          );
      if (mounted) _message('تم إرسال إثبات الدفع للتحقق.');
      await _load();
    } catch (error) {
      if (mounted) _message(friendlyApiError(error));
    } finally {
      sender.dispose(); phone.dispose(); reference.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDirect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد الدفع المباشر'),
          content: const Text('أكد فقط إذا تمت التسوية مباشرة بين الطرفين. يحتاج الطرف الآخر إلى تأكيد مستقل أيضًا.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('رجوع')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('نعم، أؤكد')),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await ref.read(financialRepositoryProvider).confirmDirect(widget.agreementId);
      if (!mounted) return;
      _message(result['completed'] == true
          ? 'تم تأكيد الطرفين. تم تسجيل مستحق السعي للمنصة وبدأت مهلة 24 ساعة.'
          : 'تم تسجيل تأكيدك. بانتظار تأكيد الطرف الآخر.');
      await _load();
    } catch (error) {
      if (mounted) _message(friendlyApiError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
          Expanded(child: Text(value)),
        ]),
      );

  Widget _info(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Text('$label: $value', style: const TextStyle(fontWeight: FontWeight.w600)),
      );

  IconData _methodIcon(String key) => switch (key) {
        'kuraimi' => Icons.account_balance_outlined,
        'transfer' => Icons.send_to_mobile_outlined,
        _ => Icons.account_balance_wallet_outlined,
      };

  String _money(double value, String currency) => '${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2)} $currency';
  String _payerLabel(String value) => switch (value) {
        'buyer' => 'المشتري', 'seller' => 'البائع', 'tenant' => 'المستأجر', 'landlord' => 'المؤجر', _ => value,
      };
  void _message(String value) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

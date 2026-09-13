import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      final deal =
          await ref.read(financialRepositoryProvider).deal(widget.agreementId);
      if (!mounted) return;
      setState(() {
        _deal = deal;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyApiError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إتمام الدفع'),
          actions: [
            IconButton(
                onPressed: _busy ? null : _load,
                icon: const Icon(Icons.refresh))
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!, textAlign: TextAlign.center),
                    ),
                  )
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(deal.propertyTitle,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                _row(deal.isRent ? 'قيمة المقدم' : 'قيمة الصفقة النهائية',
                    _money(deal.baseAmount, deal.currency)),
                if (deal.isRent && deal.monthlyRent != null)
                  _row('الإيجار الشهري',
                      _money(deal.monthlyRent!, deal.currency)),
                if (deal.isRent && deal.rentalTermMonths != null)
                  _row('مدة التأجير', '${deal.rentalTermMonths} شهر'),
                if (deal.isRent && deal.advanceMonths != null)
                  _row('المقدم', '${deal.advanceMonths} شهر'),
                _row('السعي', _money(deal.saiTotalAmount, deal.currency)),
                _row('يتحمل السعي', _payerLabel(deal.saiPayer)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (deal.canPayFull)
          _actionCard(
            title: 'الدفع الكامل عبر المنصة',
            subtitle:
                'المبلغ محسوب من الاتفاق النهائي والشروط المالية المجمدة ولا يمكن تعديله.',
            amount: deal.requiredFullPayment,
            currency: deal.currency,
            icon: Icons.account_balance_wallet_outlined,
            onTap: () => _chooseMethod(
                deal, 'platform_full', deal.requiredFullPayment),
          ),
        if (deal.canPaySaiOnly) ...[
          const SizedBox(height: 8),
          _actionCard(
            title: 'سداد السعي عبر المنصة فقط',
            subtitle:
                'استخدمه عندما يتم أصل الصفقة خارج المنصة ويكون السعي مستحقًا عليك.',
            amount: deal.requiredSaiPayment,
            currency: deal.currency,
            icon: Icons.receipt_long_outlined,
            onTap: () => _chooseMethod(
                deal, 'platform_sai_only', deal.requiredSaiPayment),
          ),
        ],
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.handshake_outlined),
                  SizedBox(width: 8),
                  Expanded(
                      child: Text('الدفع المباشر بين الطرفين',
                          style: TextStyle(fontWeight: FontWeight.w900)))
                ]),
                const SizedBox(height: 8),
                const Text(
                    'كل طرف يؤكد بشكل مستقل أن الدفع تم مباشرة. لا تعتبر الصفقة مؤكدة ماليًا حتى يؤكد الطرفان. عند اكتمال التأكيد ينشأ مستحق المنصة وتبدأ مهلة 24 ساعة.'),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _confirmDirect,
                    icon: const Icon(Icons.verified_outlined),
                    label: const Text('أؤكد أن الدفع تم مباشرة'),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (deal.payments.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('عمليات الدفع',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          ...deal.payments.map((payment) => _paymentCard(deal, payment)),
        ],
      ],
    );
  }

  Widget _paymentCard(FinancialDeal deal, FinancialPayment payment) {
    final pendingReview =
        ['proof_submitted', 'under_review'].contains(payment.status);
    final confirmed = payment.status == 'confirmed';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(confirmed
                  ? Icons.check_circle_outline
                  : pendingReview
                      ? Icons.hourglass_top
                      : Icons.payments_outlined),
              const SizedBox(width: 8),
              Expanded(
                child: Text(payment.statusLabel,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
            ]),
            const SizedBox(height: 8),
            _row('رقم العملية', payment.reference),
            _row('المبلغ', _money(payment.amount, payment.currency)),
            _row('العقار', payment.propertyTitle ?? deal.propertyTitle),
            if (payment.paymentMethod != null)
              _row('طريقة الدفع', payment.paymentMethod!),
            if (payment.confirmedAt != null)
              _row('تاريخ التأكيد', _date(payment.confirmedAt!)),
            if (payment.reviewNote != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(payment.reviewNote!),
              ),
            if (pendingReview) ...[
              const SizedBox(height: 8),
              const Text(
                'تم استلام الإثبات وهو الآن قيد التحقق. لا تدفع مرة أخرى لهذه العملية حتى تصلك النتيجة.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
            if (confirmed) ...[
              const SizedBox(height: 8),
              Text('السعي: ${_money(deal.saiTotalAmount, deal.currency)}'),
              const Text(
                  'هذا الإيصال يؤكد استلام المنصة لهذه الدفعة وفق نوعها المسجل، ولا يغيّر وحده الصفة القانونية للصفقة.'),
            ],
            if (['waiting_payment', 'correction_required']
                .contains(payment.status)) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: _busy
                      ? null
                      : () => _showTransferDetails(
                          payment, payment.method ?? _methodFor(payment)),
                  child: const Text('إكمال الدفع'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _actionCard({
    required String title,
    required String subtitle,
    required double amount,
    required String currency,
    required IconData icon,
    required VoidCallback onTap,
  }) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w900)))
              ]),
              const SizedBox(height: 6),
              Text(subtitle),
              const SizedBox(height: 8),
              Text(_money(amount, currency),
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                      onPressed: _busy ? null : onTap,
                      child: const Text('اختيار طريقة الدفع'))),
            ],
          ),
        ),
      );

  Future<void> _chooseMethod(
      FinancialDeal deal, String mode, double amount) async {
    final method = await showModalBottomSheet<FinancialPaymentMethod>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('اختر طريقة الدفع',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text('المبلغ المطلوب: ${_money(amount, deal.currency)}'),
                const SizedBox(height: 12),
                ...deal.paymentMethods.map((method) {
                  final capabilityAllowed = mode == 'platform_full'
                      ? method.allowsFullPayment
                      : method.allowsSaiOnly;
                  final enabled = method.available && capabilityAllowed;
                  final reason = !capabilityAllowed
                      ? (mode == 'platform_full'
                          ? 'غير مفعلة للدفع الكامل.'
                          : 'غير مفعلة لسداد السعي.')
                      : method.unavailableReason;
                  return ListTile(
                    enabled: enabled,
                    leading: _methodLogo(method),
                    title: Text(method.name),
                    subtitle: enabled ? null : Text(reason ?? 'غير متاح'),
                    trailing: const Icon(Icons.chevron_left),
                    onTap:
                        enabled ? () => Navigator.pop(context, method) : null,
                  );
                }),
                const SizedBox(height: 6),
                const Text(
                  'لن تظهر بيانات التحويل إلا بعد اختيار وسيلة الدفع من هذه الصفحة.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
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
      await _showTransferDetails(payment, payment.method ?? method);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _message(friendlyApiError(error));
    }
  }

  Future<void> _showTransferDetails(
      FinancialPayment payment, FinancialPaymentMethod? method) async {
    if (method == null) {
      _message('تعذر تحديد طريقة الدفع. حدّث الصفحة وحاول مرة أخرى.');
      return;
    }
    final completed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(children: [
            _methodLogo(method, size: 42),
            const SizedBox(width: 10),
            Expanded(child: Text(method.name)),
          ]),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'أنت على وشك تحويل ${_amountOnly(payment.amount)} ريال لهذه الصفقة. لا تحول إلى أي رقم آخر يرسله لك شخص عبر المحادثات. بيانات الدفع المعتمدة تظهر في هذه الصفحة فقط.',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 16),
                _info('المستفيد', method.beneficiaryName),
                const SizedBox(height: 8),
                _copyRow(method.destinationLabel, method.destinationValue,
                    'نسخ الرقم'),
                const SizedBox(height: 8),
                _copyRow('المبلغ', _amountOnly(payment.amount), 'نسخ المبلغ'),
                const SizedBox(height: 4),
                Text('العملة: ${payment.currency}'),
                if (method.instructions != null) ...[
                  const SizedBox(height: 10),
                  Text(method.instructions!),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء')),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('لقد أتممت التحويل'),
            ),
          ],
        ),
      ),
    );
    if (completed == true && mounted) {
      await _proofFlow(payment, method);
    }
  }

  Future<void> _proofFlow(
      FinancialPayment payment, FinancialPaymentMethod method) async {
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  InputDecorator(
                    decoration: const InputDecoration(labelText: 'المبلغ'),
                    child: Text(_money(payment.amount, payment.currency),
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                      controller: sender,
                      decoration:
                          const InputDecoration(labelText: 'اسم المرسل')),
                  if (method.requiresSenderPhone)
                    TextField(
                        controller: phone,
                        keyboardType: TextInputType.phone,
                        decoration:
                            const InputDecoration(labelText: 'رقم المرسل')),
                  TextField(
                    controller: reference,
                    decoration: InputDecoration(
                        labelText: method.requiresProviderReference
                            ? 'رقم العملية أو الحوالة *'
                            : 'رقم العملية أو الحوالة (إن وجد)'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final paths =
                          await const Stage5MediaPicker().pickImages();
                      if (paths.isNotEmpty) {
                        setDialogState(() => pickedPath = paths.first);
                      }
                    },
                    icon: Icon(pickedPath == null
                        ? Icons.add_photo_alternate_outlined
                        : Icons.check_circle_outline),
                    label: Text(pickedPath == null
                        ? 'اختيار صورة إثبات التحويل *'
                        : 'تم اختيار صورة الإثبات'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('لاحقًا')),
              FilledButton(
                onPressed: pickedPath == null ||
                        (method.requiresSenderPhone &&
                            phone.text.trim().isEmpty) ||
                        (method.requiresProviderReference &&
                            reference.text.trim().isEmpty)
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
      sender.dispose();
      phone.dispose();
      reference.dispose();
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
      if (mounted) {
        _message(
            'جارٍ التحقق من الدفع. تم استلام الإثبات، لا تدفع مرة أخرى لهذه العملية حتى تصلك النتيجة.');
      }
      await _load();
    } catch (error) {
      if (mounted) _message(friendlyApiError(error));
    } finally {
      sender.dispose();
      phone.dispose();
      reference.dispose();
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
          content: const Text(
              'أكد فقط إذا تمت التسوية مباشرة بين الطرفين. يحتاج الطرف الآخر إلى تأكيد مستقل أيضًا. إذا كان هناك خلاف فلا تؤكد العملية.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('رجوع')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('نعم، أؤكد')),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(financialRepositoryProvider)
          .confirmDirect(widget.agreementId);
      if (!mounted) return;
      _message(result['completed'] == true
          ? 'تم تأكيد الطرفين. تم تسجيل مستحق المنصة وبدأت مهلة 24 ساعة.'
          : 'تم تسجيل تأكيدك. بانتظار تأكيد الطرف الآخر.');
      await _load();
    } catch (error) {
      if (mounted) _message(friendlyApiError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  FinancialPaymentMethod? _methodFor(FinancialPayment payment) {
    final methods = _deal?.paymentMethods ?? const <FinancialPaymentMethod>[];
    for (final method in methods) {
      if (method.name == payment.paymentMethod) return method;
    }
    return null;
  }

  Widget _methodLogo(FinancialPaymentMethod method, {double size = 40}) {
    final path = method.localAssetPath;
    if (path == null) {
      return SizedBox(
          width: size,
          height: size,
          child: const Icon(Icons.send_to_mobile_outlined));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Image.asset(path,
          width: size, height: size, fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => SizedBox(
              width: size,
              height: size,
              child: const Icon(Icons.account_balance_wallet_outlined))),
    );
  }

  Widget _copyRow(String label, String value, String action) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _info(label, value)),
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (mounted) _message('تم النسخ');
            },
            icon: const Icon(Icons.copy, size: 18),
            label: Text(action),
          ),
        ],
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 120,
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w700))),
          Expanded(child: Text(value)),
        ]),
      );

  Widget _info(String label, String value) => Text('$label: $value',
      style: const TextStyle(fontWeight: FontWeight.w600));

  String _amountOnly(double value) =>
      value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2);
  String _money(double value, String currency) =>
      '${_amountOnly(value)} $currency';
  String _date(DateTime value) => value.toLocal().toString().split('.').first;
  String _payerLabel(String value) => switch (value) {
        'buyer' => 'المشتري',
        'seller' => 'البائع',
        'tenant' => 'المستأجر',
        'landlord' => 'المؤجر',
        _ => value,
      };
  void _message(String value) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(value)));
}

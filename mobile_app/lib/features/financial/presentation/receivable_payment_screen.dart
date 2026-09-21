import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/platform/stage5_media_picker.dart';
import '../data/financial_repository.dart';
import '../domain/financial_models.dart';

class ReceivablePaymentScreen extends ConsumerStatefulWidget {
  const ReceivablePaymentScreen({
    required this.receivableId,
    required this.agreementId,
    required this.remainingAmount,
    required this.currency,
    this.propertyTitle,
    super.key,
  });

  final int receivableId;
  final int agreementId;
  final double remainingAmount;
  final String currency;
  final String? propertyTitle;

  @override
  ConsumerState<ReceivablePaymentScreen> createState() =>
      _ReceivablePaymentScreenState();
}

class _ReceivablePaymentScreenState
    extends ConsumerState<ReceivablePaymentScreen> {
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
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('سداد مستحق المنصة')),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!, textAlign: TextAlign.center),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(widget.propertyTitle ??
                                    _deal?.propertyTitle ??
                                    'العقار'),
                                const SizedBox(height: 8),
                                Text(
                                  _money(widget.remainingAmount,
                                      widget.currency),
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                    'هذا هو المبلغ المتبقي المستحق للمنصة عن الصفقة المباشرة. المبلغ غير قابل للتعديل.'),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text('اختر طريقة الدفع',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 8),
                        ...?_deal?.paymentMethods.map((method) {
                          final enabled = method.available && method.allowsSaiOnly;
                          return Card(
                            child: ListTile(
                              enabled: enabled,
                              leading: _logo(method),
                              title: Text(method.name),
                              subtitle: enabled
                                  ? null
                                  : Text(method.unavailableReason ??
                                      'غير متاحة لسداد مستحق المنصة.'),
                              trailing: const Icon(Icons.chevron_left),
                              onTap: enabled && !_busy
                                  ? () => _start(method)
                                  : null,
                            ),
                          );
                        }),
                      ],
                    ),
        ),
      );

  Future<void> _start(FinancialPaymentMethod method) async {
    setState(() => _busy = true);
    try {
      final payment = await ref
          .read(financialRepositoryProvider)
          .createReceivablePayment(
            receivableId: widget.receivableId,
            paymentMethodId: method.id,
          );
      if (!mounted) return;
      setState(() => _busy = false);
      await _transfer(payment, payment.method ?? method);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _message(friendlyApiError(error));
    }
  }

  Future<void> _transfer(
      FinancialPayment payment, FinancialPaymentMethod method) async {
    final complete = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(children: [
            _logo(method, size: 42),
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
                    'أنت على وشك تحويل ${_amount(payment.amount)} ريال لهذه الصفقة. لا تحول إلى أي رقم آخر يرسله لك شخص عبر المحادثات. بيانات الدفع المعتمدة تظهر في هذه الصفحة فقط.',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 14),
                Text('المستفيد: ${method.beneficiaryName}'),
                const SizedBox(height: 8),
                _copy(method.destinationLabel, method.destinationValue,
                    'نسخ الرقم'),
                const SizedBox(height: 8),
                _copy('المبلغ', _amount(payment.amount), 'نسخ المبلغ'),
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
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('لقد أتممت التحويل')),
          ],
        ),
      ),
    );
    if (complete == true && mounted) await _proof(payment, method);
  }

  Future<void> _proof(
      FinancialPayment payment, FinancialPaymentMethod method) async {
    final sender = TextEditingController();
    final phone = TextEditingController();
    final reference = TextEditingController();
    String? proof;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('إرسال إثبات السداد'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InputDecorator(
                    decoration: const InputDecoration(labelText: 'المبلغ'),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(_money(payment.amount, payment.currency),
                          style: const TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
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
                      decoration: const InputDecoration(
                          labelText: 'رقم العملية أو الحوالة (إن وجد)')),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final files =
                          await const Stage5MediaPicker().pickImages();
                      if (files.isNotEmpty) setLocal(() => proof = files.first);
                    },
                    icon: Icon(proof == null
                        ? Icons.add_photo_alternate_outlined
                        : Icons.check_circle_outline),
                    label: Text(proof == null
                        ? 'اختيار صورة الإثبات *'
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
                  onPressed: proof == null
                      ? null
                      : () => Navigator.pop(dialogContext, true),
                  child: const Text('إرسال للتحقق')),
            ],
          ),
        ),
      ),
    );
    if (ok == true && proof != null && mounted) {
      setState(() => _busy = true);
      try {
        await ref.read(financialRepositoryProvider).submitProof(
              paymentId: payment.id,
              imagePath: proof!,
              senderName: sender.text,
              senderPhone: phone.text,
              providerReference: reference.text,
            );
        if (mounted) {
          _message(
              'جارٍ التحقق من الدفع. تم استلام الإثبات، لا تدفع مرة أخرى لهذه العملية حتى تصلك النتيجة.');
          Navigator.of(context).pop(true);
        }
      } catch (error) {
        if (mounted) _message(friendlyApiError(error));
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    sender.dispose();
    phone.dispose();
    reference.dispose();
  }

  Widget _copy(String label, String value, String action) => Row(children: [
        Expanded(child: Text('$label: $value')),
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: value));
            if (mounted) _message('تم النسخ');
          },
          icon: const Icon(Icons.copy, size: 18),
          label: Text(action),
        ),
      ]);

  Widget _logo(FinancialPaymentMethod method, {double size = 42}) {
    final path = method.localAssetPath;
    if (path == null) {
      return SizedBox(
          width: size,
          height: size,
          child: const Icon(Icons.send_to_mobile_outlined));
    }
    return Image.asset(path,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => SizedBox(
            width: size,
            height: size,
            child: const Icon(Icons.account_balance_wallet_outlined)));
  }

  String _amount(double value) =>
      value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2);
  String _money(double value, String currency) => '${_amount(value)} $currency';
  void _message(String value) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(value)));
}

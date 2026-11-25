import 'package:flutter/material.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/platform/stage5_media_picker.dart';
import '../data/financial_repository.dart';
import '../domain/financial_models.dart';
import '../../account/presentation/actor_scoped_page.dart';
import '../../account/data/account_request_scope.dart';

class ReceivablePaymentScreen extends StatelessWidget {
  const ReceivablePaymentScreen({
    required this.receivableId,
    this.agreementId = 0,
    required this.remainingAmount,
    required this.currency,
    this.propertyTitle,
    this.requestScope,
    super.key,
  });

  final int receivableId;
  final int agreementId;
  final double remainingAmount;
  final String currency;
  final String? propertyTitle;
  final AccountRequestScope? requestScope;
  @override
  Widget build(BuildContext context) => ActorBoundPage(
      title: 'سداد مستحق المنصة',
      requestScope: requestScope,
      builder: (_) => _ReceivablePaymentPage(
          receivableId: receivableId,
          agreementId: agreementId,
          remainingAmount: remainingAmount,
          currency: currency,
          propertyTitle: propertyTitle));
}

class _ReceivablePaymentPage extends ConsumerStatefulWidget {
  const _ReceivablePaymentPage(
      {required this.receivableId,
      required this.agreementId,
      required this.remainingAmount,
      required this.currency,
      required this.propertyTitle});
  final int receivableId;
  final int agreementId;
  final double remainingAmount;
  final String currency;
  final String? propertyTitle;
  @override
  ConsumerState<_ReceivablePaymentPage> createState() =>
      _ReceivablePaymentScreenState();
}

class _ReceivablePaymentScreenState
    extends ConsumerState<_ReceivablePaymentPage> {
  late final AccountRequestScope _scope;
  bool get _valid => mounted && _scope.isCurrent;
  FinancialDeal? _deal;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  double get _remainingAmount =>
      double.tryParse('${_deal?.receivable?['remaining_amount'] ?? ''}') ??
      widget.remainingAmount;
  String get _currency =>
      _deal?.receivable?['currency']?.toString() ?? widget.currency;
  bool get _underReview => _deal?.receivable?['status'] == 'under_review';

  static const _methodOrder = {
    'jeeb': 0,
    'kuraimi': 1,
    'jawali': 2,
    'transfer': 3
  };
  List<FinancialPaymentMethod> get _paymentMethods {
    final methods = [...?_deal?.paymentMethods];
    return methods
      ..sort((a, b) {
        final rank = (_methodOrder[a.key] ?? _methodOrder.length)
            .compareTo(_methodOrder[b.key] ?? _methodOrder.length);
        return rank == 0 ? a.sortOrder.compareTo(b.sortOrder) : rank;
      });
  }

  @override
  void initState() {
    super.initState();
    _scope = ref.read(accountRequestScopeProvider);
    Future.microtask(_load);
  }

  Future<void> _load() async {
    if (!_valid) return;
    try {
      final repo = ref.read(financialRepositoryProvider);
      final deal = widget.agreementId > 0
          ? await repo.deal(widget.agreementId)
          : await repo.receivableDeal(widget.receivableId);
      if (!_valid) return;
      setState(() {
        _deal = deal;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!_valid) return;
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
                                  _money(_remainingAmount, _currency),
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                    'هذا هو المبلغ المتبقي المستحق للمنصة عن الصفقة المباشرة. المبلغ غير قابل للتعديل.'),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_underReview)
                          const Text('إثبات السداد قيد التحقق')
                        else if (_remainingAmount <= 0)
                          const Text('تم سداد مستحق المنصة')
                        else ...[
                          Text('اختر طريقة الدفع',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          ..._paymentMethods.map((method) {
                            final enabled =
                                method.available && method.allowsSaiOnly;
                            return Card(
                              child: ListTile(
                                key:
                                    ValueKey('receivable-method-${method.key}'),
                                enabled: enabled,
                                leading: _logo(method),
                                title: Text(method.name),
                                subtitle: enabled
                                    ? null
                                    : Text(method.unavailableReason ??
                                        'غير متاحة لسداد مستحق المنصة.'),
                                trailing: const Icon(Icons.arrow_back,
                                    textDirection: TextDirection.ltr),
                                onTap: enabled && !_busy
                                    ? () => _start(method)
                                    : null,
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
        ),
      );

  Future<void> _start(FinancialPaymentMethod method) async {
    if (!_valid || _busy) return;
    setState(() => _busy = true);
    try {
      final payment =
          await ref.read(financialRepositoryProvider).createReceivablePayment(
                receivableId: widget.receivableId,
                paymentMethodId: method.id,
              );
      if (!_valid) return;
      final selected = payment.method ?? method;
      if (selected.id != method.id) {
        _message('تعذر تبديل طريقة الدفع. أعد فتح المستحق وحاول مرة أخرى.');
        return;
      }
      await _transfer(payment, selected);
    } catch (error) {
      if (_valid) _message(friendlyApiError(error));
    } finally {
      if (_valid) setState(() => _busy = false);
    }
  }

  Future<void> _transfer(
      FinancialPayment payment, FinancialPaymentMethod method) async {
    if (!_valid) return;
    final complete = await showActorDialog<bool>(
      context: context,
      ref: ref,
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
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'أنت على وشك تحويل ${_money(payment.amount, payment.currency == 'YER' ? 'ريال' : payment.currency)} لهذه الصفقة. لا تحول إلى أي رقم آخر يرسله لك شخص عبر المحادثات. بيانات الدفع المعتمدة تظهر في هذه الصفحة فقط.',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 14),
                _copy('المستفيد', method.beneficiaryName, 'نسخ اسم المستفيد'),
                _copy(method.destinationLabel, method.destinationValue,
                    'نسخ الرقم'),
                _copy('المبلغ', _amount(payment.amount), 'نسخ المبلغ'),
                const SizedBox(height: 10),
                Text(method.instructions ??
                    'حوّل المبلغ المطلوب فقط، ثم ارفع صورة واضحة لإثبات العملية للتحقق.'),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء')),
            EbrokerFilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('لقد أتممت التحويل')),
          ],
        ),
      ),
    );
    if (complete == true && _valid) await _proof(payment);
  }

  Future<void> _proof(FinancialPayment payment) async {
    if (!_valid) return;
    const picker = Stage5MediaPicker();
    String? proof;
    String? errorMessage;
    bool picking = false;
    bool sending = false;
    bool? sent;

    Future<void> removeTemporaryFiles(Iterable<String> paths) async {
      try {
        await picker.clearTemporaryFiles(paths);
      } catch (_) {
        // Do not mask the payment result with cache cleanup.
      }
    }

    try {
      sent = await showActorDialog<bool>(
        context: context,
        ref: ref,
        barrierDismissible: false,
        builder: (_) => StatefulBuilder(builder: (dialogContext, setLocal) {
          final theme = Theme.of(dialogContext);
          return Directionality(
            textDirection: TextDirection.rtl,
            child: PopScope(
              canPop: !picking && !sending,
              child: AlertDialog(
                title: const Text('إرسال إثبات السداد'),
                content: SingleChildScrollView(
                    child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InputDecorator(
                      decoration: const InputDecoration(labelText: 'المبلغ'),
                      child: Text(_money(payment.amount, payment.currency),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 10),
                    EbrokerOutlinedButton.icon(
                      onPressed: picking || sending
                          ? null
                          : () async {
                              if (!_valid || picking || sending) return;
                              setLocal(() {
                                picking = true;
                                errorMessage = null;
                              });
                              try {
                                final files = await picker.pickImages();
                                if (!dialogContext.mounted || !_valid) {
                                  await removeTemporaryFiles(files);
                                  return;
                                }
                                if (files.isEmpty) return;
                                final selected = files.first;
                                final unused = {
                                  ...files.skip(1),
                                  if (proof != null) proof!,
                                }..remove(selected);
                                setLocal(() => proof = selected);
                                await removeTemporaryFiles(unused);
                              } catch (error) {
                                if (dialogContext.mounted && _valid) {
                                  setLocal(() =>
                                      errorMessage = friendlyApiError(error));
                                }
                              } finally {
                                if (dialogContext.mounted && _valid) {
                                  setLocal(() => picking = false);
                                }
                              }
                            },
                      icon: EbrokerIcon(proof == null
                          ? Icons.add_photo_alternate_outlined
                          : Icons.check_circle_outline),
                      label: const Text('رفع صورة الاثبات(الايصال)'),
                    ),
                    if (proof != null) const Text('تم اختيار صورة الإثبات'),
                    if (errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(errorMessage!,
                            style: TextStyle(color: theme.colorScheme.error)),
                      ),
                  ],
                )),
                actions: [
                  TextButton(
                    onPressed: picking || sending
                        ? null
                        : () => Navigator.pop(dialogContext, false),
                    child: const Text('لاحقًا'),
                  ),
                  EbrokerFilledButton(
                    onPressed: proof == null || picking || sending
                        ? null
                        : () async {
                            if (!_valid ||
                                sending ||
                                picking ||
                                proof == null) {
                              return;
                            }
                            setLocal(() {
                              sending = true;
                              errorMessage = null;
                            });
                            try {
                              await ref
                                  .read(financialRepositoryProvider)
                                  .submitProof(
                                    paymentId: payment.id,
                                    imagePath: proof!,
                                  );
                              if (dialogContext.mounted && _valid) {
                                Navigator.pop(dialogContext, true);
                              }
                            } catch (error) {
                              if (dialogContext.mounted && _valid) {
                                setLocal(() {
                                  sending = false;
                                  errorMessage = friendlyApiError(error);
                                });
                              }
                            }
                          },
                    child: Text(sending ? 'جارٍ الإرسال…' : 'إرسال للتحقق'),
                  ),
                ],
              ),
            ),
          );
        }),
      );
    } finally {
      if (proof != null) await removeTemporaryFiles([proof!]);
    }

    if (sent == true && mounted && _scope.isCurrent) {
      _message(
          'تم استلام إثبات السداد وهو الآن قيد التحقق. لا تدفع مرة أخرى لهذه العملية.');
      Navigator.of(context).pop(true);
    }
  }

  Widget _copy(String label, String value, String action) => Row(children: [
        Expanded(child: Text('$label: $value')),
        IconButton(
          tooltip: action,
          onPressed: () async {
            if (!_valid) return;
            await Clipboard.setData(ClipboardData(text: value));
            if (_valid) _message('تم النسخ');
          },
          icon: Icon(Icons.content_copy_outlined,
              size: 18, color: Theme.of(context).colorScheme.primary),
        ),
      ]);

  Widget _logo(FinancialPaymentMethod method, {double size = 42}) {
    final path = method.localAssetPath;
    if (method.key == 'transfer') {
      return SizedBox(
        width: size,
        height: size,
        child: Icon(Icons.compare_arrows_rounded, size: size * .70),
      );
    }
    if (path == null) {
      return SizedBox(
          width: size,
          height: size,
          child: const EbrokerIcon(Icons.send_to_mobile_outlined));
    }
    return Image.asset(path,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => SizedBox(
            width: size,
            height: size,
            child: const EbrokerIcon(Icons.account_balance_wallet_outlined)));
  }

  String _amount(double value) =>
      value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2);
  String _money(double value, String currency) => '${_amount(value)} $currency';
  void _message(String value) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(value)));
}

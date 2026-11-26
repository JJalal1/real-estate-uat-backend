import 'dart:async';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/widgets/app_components.dart';
import '../../account/data/account_request_scope.dart';
import '../../account/data/auth_controller.dart';
import '../../account/presentation/actor_scoped_page.dart';
import '../../community/data/community_repository.dart';
import '../../financial/presentation/receivable_payment_screen.dart';
import '../../financial/data/financial_repository.dart';
import '../../messages/domain/message_models.dart';
import '../../properties/data/property_repository.dart';
import '../../properties/domain/property_details.dart';
import '../data/broker_repository.dart';
import '../domain/broker_models.dart';
import 'broker_workspaces.dart';
import 'customer_followup_sheet.dart';

String brokerMoney(dynamic amount, String currency) => '${brokerNumber(amount).toStringAsFixed(2)} ${currency == 'YER' ? 'ر.ي' : currency}';

Future<bool> reportBrokerDeal(
  BuildContext context,
  WidgetRef ref,
  int threadId, {
  int? propertyId,
  bool openResult = true,
}) async {
  final scope = ref.read(accountRequestScopeProvider);
  final repository = ref.read(propertyRepositoryProvider);
  final amount = await showActorDialog<_DealAmount>(
    context: context,
    ref: ref,
    builder: (_) => _BrokerDealAmountDialog(
      loadProperty: propertyId == null ? null : () => repository.details(propertyId),
    ),
  );
  if (amount == null || !context.mounted || !scope.isCurrent) return false;
  try {
    final deal = await _reportWithSaiConsent(context, ref, scope, threadId, amount.manual);
    if (deal == null || !context.mounted || !scope.isCurrent) return false;
    refreshBrokerData(ref);
    if (openResult) {
      await context.push('/broker/deals/${deal.id}');
    } else {
      final message = deal.status == 'pending_customer'
          ? 'أُرسل مبلغ الصفقة للعميل للتأكيد.'
          : 'تم تسجيل الصفقة.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
    return true;
  } catch (error) {
    if (context.mounted && scope.isCurrent) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    }
    return false;
  }
}

enum _DealPriceChoice { advertised, manual }

class _DealAmount {
  const _DealAmount([this.manual]);
  final double? manual;
}

class _BrokerDealAmountDialog extends StatefulWidget {
  const _BrokerDealAmountDialog({required this.loadProperty});
  final Future<PropertyDetails> Function()? loadProperty;

  @override
  State<_BrokerDealAmountDialog> createState() => _BrokerDealAmountDialogState();
}

class _BrokerDealAmountDialogState extends State<_BrokerDealAmountDialog> {
  _DealPriceChoice? _choice;
  Future<PropertyDetails>? _property;
  String _raw = '';

  void _choose(_DealPriceChoice? choice) => setState(() {
    _choice = choice;
    if (choice == _DealPriceChoice.manual) _property ??= widget.loadProperty?.call();
  });

  double? _advertisedPrice(PropertyDetails? property) {
    if (property == null) return null;
    final monthlyRent = property.monthlyRent;
    return property.purpose == 'rent' && monthlyRent != null && monthlyRent > 0
        ? monthlyRent
        : property.editablePrice;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<PropertyDetails>(
    future: _property,
    builder: (context, snapshot) {
      final enteringAmount = _choice == _DealPriceChoice.manual;
      final property = snapshot.data;
      final advertised = _advertisedPrice(property);
      final amount = _brokerAmount(_raw);
      final amountValid = amount != null &&
          amount > 0 && amount <= 9999999999999 && (amount * 100).round() > 0;
      final canSubmit = _choice == _DealPriceChoice.advertised ||
          (enteringAmount && advertised != null && advertised > 0 && amountValid);
      final priceLabel = property?.purpose == 'sale' && property?.editablePrice != property?.price
          ? 'سعر الإعلان دون السعي'
          : 'السعر المعروض';

      return AlertDialog(
        title: const Text('مبلغ الصفقة'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<_DealPriceChoice>(
                contentPadding: EdgeInsets.zero,
                title: const Text('بنفس السعر المعروض'),
                value: _DealPriceChoice.advertised,
                groupValue: _choice,
                onChanged: _choose,
              ),
              RadioListTile<_DealPriceChoice>(
                contentPadding: EdgeInsets.zero,
                title: const Text('إدخال المبلغ'),
                value: _DealPriceChoice.manual,
                groupValue: _choice,
                onChanged: widget.loadProperty == null ? null : _choose,
              ),
              if (enteringAmount) ...[
                if (snapshot.hasError)
                  TextButton(
                    onPressed: () => setState(() => _property = widget.loadProperty?.call()),
                    child: const Text('إعادة محاولة تحميل السعر المعروض'),
                  )
                else if (advertised == null)
                  const LinearProgressIndicator()
                else if (advertised <= 0)
                  const Text('أضف سعر الإعلان قبل تسجيل الصفقة.')
                else
                  TextFormField(
                    initialValue: _raw,
                    onChanged: (value) => setState(() => _raw = value),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: property?.purpose == 'rent' ? 'الإيجار الشهري' : 'المبلغ',
                      helperText: '$priceLabel: ${brokerMoney(advertised, property!.currency)}',
                      errorText: _raw.trim().isNotEmpty && !amountValid
                          ? 'أدخل مبلغًا صحيحًا.'
                          : null,
                    ),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          AppButton(
            label: 'تسجيل الصفقة',
            onPressed: canSubmit
                ? () => Navigator.pop(context, _DealAmount(enteringAmount ? amount : null))
                : null,
          ),
        ],
      );
    },
  );
}

Future<BrokerDeal?> _reportWithSaiConsent(BuildContext context, WidgetRef ref, AccountRequestScope scope, int threadId, double? amount) async {
  final repository = ref.read(brokerRepositoryProvider);
  try { return await repository.reportDeal(threadId, amount: amount); }
  on DioException catch (error) {
    final body = error.response?.data;
    if (error.response?.statusCode != 409 || body is! Map || body['code'] != 'sai_consent_required') rethrow;
    final data = body['data'];
    if (data is! Map || data['property_id'] is! int || data['sai_term_id'] is! int || data['text'] is! String || !context.mounted || !scope.isCurrent) rethrow;
    final accepted = await showActorDialog<bool>(context: context, ref: ref, builder: (dialog) => AlertDialog(
      title: const Text('إقرار السعي لهذه المحادثة'),
      content: SingleChildScrollView(child: Text(data['text'] as String)),
      actions: [TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('ليس الآن')),
        AppButton(label: 'أوافق وأتابع', onPressed: () => Navigator.pop(dialog, true))],
    ));
    if (accepted != true || !context.mounted || !scope.isCurrent) return null;
    await ref.read(financialRepositoryProvider).attestSai(data['property_id'] as int, saiTermId: data['sai_term_id'] as int);
    if (!context.mounted || !scope.isCurrent) return null;
    return repository.reportDeal(threadId, amount: amount);
  }
}

double? _brokerAmount(String text) {
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  var value = text.trim().replaceAll(',', '').replaceAll('٬', '').replaceAll('٫', '.');
  for (var i = 0; i < 10; i++) { value = value.replaceAll(arabic[i], '$i'); }
  final parsed = double.tryParse(value);
  return parsed?.isFinite == true ? parsed : null;
}

class BrokerActivityScreen extends ConsumerWidget {
  const BrokerActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountRequestScopeProvider);
    return BrokerScaffold(
      appBar: const AppAppBar(title: 'نشاطي'),
      body: account.isCurrent ? BrokerDealsList(key: ValueKey(account)) : const AppLoadingState(),
    );
  }
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
  int _loadVersion = 0;
  String? _error;
  @override
  void initState() { super.initState(); Future.microtask(_load); }
  Future<void> _load({bool next = false}) async {
    if (!mounted) return;
    final version = ++_loadVersion;
    setState(() { _loading = true; _error = null; });
    AccountRequestScope? scope;
    try {
      await ref.read(authControllerProvider.future);
      if (!mounted || version != _loadVersion) return;
      final request = ref.read(accountRequestScopeProvider);
      scope = request;
      final page = await ref.read(brokerRepositoryProvider).activity(page: next ? _page + 1 : 1);
      if (!mounted || !request.isCurrent || version != _loadVersion) return;
      setState(() {
        if (!next) _items.clear();
        final currentIds = _items.map((item) => item.id).toSet();
        _items.addAll(page.items.where((item) => currentIds.add(item.id)));
        _page = page.page;
        _more = page.hasMore;
        _loading = false;
      });
    } catch (error) {
      if (mounted && scope?.isCurrent != false && version == _loadVersion) {
        setState(() { _loading = false; _error = friendlyApiError(error); });
      }
    }
  }

  Future<void> _openResult(BrokerDeal deal) async {
    final scope = ref.read(accountRequestScopeProvider);
    await showActorDialog<void>(context: context, ref: ref, builder: (_) => BrokerDealScreen._dialog(
      id: deal.id,
      onDealChanged: (updated) {
        if (!mounted || !scope.isCurrent) return;
        final index = _items.indexWhere((item) => item.id == updated.id);
        if (index >= 0) setState(() => _items[index] = updated);
      },
    ));
  }

  @override
  Widget build(BuildContext context) {
    final viewer = ref.watch(authControllerProvider.select((state) => state.asData?.value?.id));
    return RefreshIndicator(onRefresh: () => _load(), child: ListView(
      key: const ValueKey('broker-activity-deals'),
      padding: const EdgeInsets.all(16), physics: const AlwaysScrollableScrollPhysics(), children: [
        for (final deal in _items) Padding(key: ValueKey(deal.id), padding: const EdgeInsets.only(bottom: 10), child: BrokerPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(deal.propertyTitle, style: Theme.of(context).textTheme.titleMedium),
          Text('${deal.otherPartyName(viewer)} · ${deal.statusLabel}'),
          Text(deal.transactionType == 'rent'
            ? 'الإيجار الشهري: ${brokerMoney(deal.amount, deal.currency)}'
            : brokerMoney(deal.amount, deal.currency)),
          AppButton(label: 'عرض النتيجة', onPressed: () => _openResult(deal)),
        ]))),
        if (_loading) const AppLoadingState(),
        if (_error != null) AppErrorState(message: _error!, onRetry: () => _load()),
        if (!_loading && _error == null && _items.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('ستظهر هنا نتائج صفقاتك بعد تسجيلها من محادثة العميل.')),
        if (_more && !_loading) AppButton(label: 'عرض المزيد', onPressed: () => _load(next: true)),
      ],
    ));
  }
}

class BrokerDealScreen extends ConsumerStatefulWidget {
  const BrokerDealScreen({required this.id, super.key}) : _inDialog = false, _onDealChanged = null;
  const BrokerDealScreen._dialog({required this.id, required ValueChanged<BrokerDeal> onDealChanged})
      : _inDialog = true, _onDealChanged = onDealChanged;

  final int id;
  final bool _inDialog;
  final ValueChanged<BrokerDeal>? _onDealChanged;
  @override
  ConsumerState<BrokerDealScreen> createState() => _BrokerDealScreenState();
}
class _BrokerDealScreenState extends ConsumerState<BrokerDealScreen> {
  bool _busy = false;
  (AccountRequestScope, int, int)? _scheduledView;

  void _recordDisplayedDeal(BrokerDeal deal) {
    final revision = deal.advertiserViewRevision;
    if (revision == null || revision <= 0) return;
    final scope = ref.read(accountRequestScopeProvider);
    final view = (scope, deal.id, revision);
    if (_scheduledView == view) return;
    _scheduledView = view;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.id != deal.id || !scope.isCurrent ||
          ModalRoute.of(context)?.isCurrent == false) {
        if (_scheduledView == view) _scheduledView = null;
        return;
      }
      unawaited(_markDealSeen(scope, deal.id, revision));
    });
  }

  Future<void> _markDealSeen(AccountRequestScope scope, int id, int revision) async {
    try {
      await ref.read(brokerRepositoryProvider).markDealSeen(id, revision);
      if (mounted && scope.isCurrent) ref.invalidate(brokerWorkspaceProvider);
    } catch (_) {
      // An unrecorded view can be retried when the deal is opened again.
    }
  }

  Future<void> _decide(BrokerDeal deal, bool yes) async {
    final scope = ref.read(accountRequestScopeProvider);
    final amount = brokerMoney(deal.amount, deal.currency);
    final confirmingAmount = deal.priceConfirmationRequired;
    final ok = await showActorDialog<bool>(
      context: context,
      ref: ref,
      builder: (dialog) => AlertDialog(
        title: Text(confirmingAmount
            ? (yes ? 'تأكيد المبلغ' : 'رفض المبلغ')
            : (yes ? 'هل تمت الصفقة؟' : 'لم تتم الصفقة؟')),
        content: Text(confirmingAmount
            ? (yes ? 'هل تؤكد المبلغ $amount؟' : 'سيُحال اختلاف المبلغ إلى الدعم للمراجعة.')
            : (yes
                ? 'أكد فقط إن تم البيع أو التأجير بالفعل. سيُحسب الإنجاز ويُفتح التقييم وفق شروط السعي المحفوظة.'
                : 'سيسجل رفضك ويحيل النتيجة للدعم للمراجعة، دون احتساب صفقة أو مستحق جديد.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('رجوع')),
          AppButton(
            label: confirmingAmount
                ? (yes ? 'أؤكد المبلغ' : 'أرفض المبلغ')
                : (yes ? 'نعم، تمت' : 'لم تتم'),
            onPressed: () => Navigator.pop(dialog, true),
          ),
        ],
      ),
    );
    if (ok != true || !mounted || !scope.isCurrent) return;
    setState(() => _busy = true);
    try {
      final deal = await ref.read(brokerRepositoryProvider).decide(widget.id, yes);
      if (!mounted || !scope.isCurrent) return;
      widget._onDealChanged?.call(deal);
      refreshBrokerData(ref);
      ref.invalidate(brokerDealProvider(widget.id));
    } catch (e) {
      if (mounted && scope.isCurrent) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
    } finally {
      if (mounted && scope.isCurrent) setState(() => _busy = false);
    }
  }
  Future<void> _rate(BrokerDeal deal) async {
    int stars = 0;
    String note = '';
    final scope = ref.read(accountRequestScopeProvider);
    final chosen = await showActorDialog<int>(context: context, ref: ref, builder: (c) => StatefulBuilder(builder: (c, change) => AlertDialog(
      title: const Text('قيّم تجربتك مع المعلن'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Wrap(children: [for (var i = 1; i <= 5; i++) IconButton(tooltip: '$i نجوم', onPressed: () => change(() => stars = i), icon: Icon(i <= stars ? Icons.star : Icons.star_border, color: Colors.amber, size: 28))]),
        TextField(onChanged: (value) => note = value, maxLength: 1000, maxLines: 3, decoration: const InputDecoration(labelText: 'تعليق اختياري')),
      ])), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
        AppButton(label: 'حفظ التقييم', onPressed: stars == 0 ? null : () => Navigator.pop(c, stars))],
    )));
    final comment = note;
    if (chosen == null || !mounted || !scope.isCurrent) return;
    setState(() => _busy = true);
    try { await ref.read(communityRepositoryProvider).rateAdvertiser(advertiserId: deal.advertiserId, rating: chosen, propertyId: deal.propertyId, comment: comment);
      if (!mounted || !scope.isCurrent) return;
      ref.invalidate(brokerProfileProvider(deal.advertiserId)); ref.invalidate(brokerDirectoryProvider);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ تقييمك.')));
    } catch (e) { if (mounted && scope.isCurrent) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(e)))); }
    finally { if (mounted && scope.isCurrent) setState(() => _busy = false); }
  }

  void _openSupport(BrokerDeal deal) {
    final router = GoRouter.of(context);
    if (widget._inDialog) Navigator.pop(context);
    router.push(deal.canViewSupportCase ? '/support?case=${deal.supportCaseId}' : '/support');
  }

  List<Widget> _actions(BrokerDeal deal) => [
    if (deal.canConfirm) ...[
      Text(deal.priceConfirmationRequired
          ? 'هل توافق على ${deal.transactionType == 'rent' ? 'الإيجار الشهري' : 'مبلغ البيع'} ${brokerMoney(deal.amount, deal.currency)}؟'
          : 'هل تم البيع أو التأجير فعلًا مع هذا المعلن؟'),
      const SizedBox(height: 12),
      AppButton(
        label: deal.priceConfirmationRequired ? 'أوافق على المبلغ' : 'نعم، تمت الصفقة',
        loading: _busy,
        expand: true,
        onPressed: _busy ? null : () => _decide(deal, true),
      ),
      const SizedBox(height: 10),
      AppButton(
        label: deal.priceConfirmationRequired ? 'لا أوافق على المبلغ' : 'لم تتم الصفقة',
        expand: true,
        style: deal.priceConfirmationRequired ? AppButtonStyle.outlined : AppButtonStyle.filled,
        onPressed: _busy ? null : () => _decide(deal, false),
      ),
    ],
    if (deal.canRate) AppButton(label: 'تقييم المعلن', icon: Icons.star_outline, expand: true, onPressed: _busy ? null : () => _rate(deal)),
    if (!widget._inDialog && deal.status == 'pending_customer' && !deal.canConfirm)
      Text(deal.priceConfirmationRequired
          ? 'أُرسل مبلغ الصفقة للعميل للتأكيد.'
          : 'تم إرسال طلب تأكيد النتيجة للعميل. لن تُحتسب حتى يؤكدها.'),
    if (deal.supportCaseId != null)
      AppButton(label: 'متابعة مراجعة الدعم', onPressed: () => _openSupport(deal)),
  ];

  Widget _resultDetails(BrokerDeal deal) {
    final viewer = ref.watch(authControllerProvider.select((state) => state.asData?.value?.id));
    final scheme = Theme.of(context).colorScheme;
    final localizations = MaterialLocalizations.of(context);
    final rate = deal.saiRatePercent;
    final confirmedAt = deal.confirmedAt;
    final payment = switch (deal.saiPaymentStatus) {
      'confirmed' => 'تم تأكيد الدفع',
      'waiting_payment' => 'بانتظار الدفع',
      'proof_submitted' || 'under_review' => 'إثبات الدفع قيد المراجعة',
      'correction_required' => 'إثبات الدفع يحتاج تصحيحًا',
      'rejected' => 'رُفض إثبات الدفع',
      _ => null,
    };

    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(deal.propertyTitle, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(deal.otherPartyName(viewer)),
      const SizedBox(height: 8),
      Align(alignment: AlignmentDirectional.centerStart, child: DecoratedBox(
        decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(8)),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(deal.statusLabel, style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w600))),
      )),
      const SizedBox(height: 12),
      _DealResultRow('سعر الإعلان', _resultMoney(deal.listingPrice, deal.listingCurrency, localizations)),
      _DealResultRow('السعر المتفق عليه', _resultMoney(deal.amount > 0 ? deal.amount : null, deal.currency, localizations)),
      if (deal.saiAmount != null && deal.saiCurrency?.isNotEmpty == true)
        _DealResultRow('مبلغ السعي', _resultMoney(deal.saiAmount, deal.saiCurrency, localizations)),
      if (rate != null) _DealResultRow('نسبة السعي', '${_resultNumber(rate, localizations)}%'),
      if (payment != null) _DealResultRow('حالة دفع السعي', payment),
      if (deal.status == 'confirmed' && confirmedAt != null)
        _DealResultRow('تاريخ التأكيد', localizations.formatCompactDate(confirmedAt.toLocal())),
      ..._actions(deal),
    ]);
  }

  String _resultMoney(double? amount, String? currency, MaterialLocalizations localizations) =>
      amount == null || currency == null || currency.isEmpty
      ? 'غير مسجل'
      : '${_resultNumber(amount, localizations)} ${currency == 'YER' ? 'ر.ي' : currency}';

  String _resultNumber(double number, MaterialLocalizations localizations) {
    final parts = number.toStringAsFixed(2).split('.');
    final integer = int.tryParse(parts.first);
    if (integer == null) return number.toString();
    final whole = localizations.formatDecimal(integer);
    final decimals = parts.last;
    return decimals == '00' ? whole : '$whole.$decimals';
  }

  @override
  Widget build(BuildContext context) {
    final content = ref.watch(brokerDealProvider(widget.id)).when(
      loading: () => widget._inDialog
          ? const SizedBox(height: 72, child: Center(child: CircularProgressIndicator()))
          : const AppLoadingState(),
      error: (error, _) {
        final message = friendlyApiError(error);
        void retry() => ref.invalidate(brokerDealProvider(widget.id));
        if (!widget._inDialog) return AppErrorState(message: message, onRetry: retry);
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(message),
          const SizedBox(height: 8),
          AppButton(label: 'إعادة المحاولة', onPressed: retry),
        ]);
      },
      data: (deal) {
        _recordDisplayedDeal(deal);
        if (widget._inDialog) return _resultDetails(deal);

        return ListView(padding: const EdgeInsets.all(16), children: [
          BrokerPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(deal.propertyTitle, style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 8),
            Text(deal.statusLabel, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
            Text('المعلن: ${deal.advertiserName}'), Text('العميل: ${deal.customerName}'), Text('أساس السعي: ${brokerMoney(deal.amount, deal.currency)}'),
          ])),
          const SizedBox(height: 16),
          ..._actions(deal),
          const SizedBox(height: 12),
          AppButton(label: 'فتح المحادثة', icon: Icons.chat_bubble_outline, onPressed: () => context.push('/messages/${deal.threadId}')),
        ]);
      },
    );
    if (!widget._inDialog) return BrokerScaffold(appBar: const AppAppBar(title: 'نتيجة الصفقة'), body: content);

    return Directionality(textDirection: TextDirection.rtl, child: AlertDialog(
      key: const ValueKey('broker-deal-result-dialog'),
      backgroundColor: Theme.of(context).colorScheme.surface,
      scrollable: true,
      title: const Text('نتيجة الصفقة'),
      content: SizedBox(width: 392, child: content),
      actionsAlignment: MainAxisAlignment.center,
      actions: [AppButton(label: 'إغلاق', onPressed: () => Navigator.pop(context))],
    ));
  }
}

class _DealResultRow extends StatelessWidget {
  const _DealResultRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Text(label)),
      const SizedBox(width: 12),
      Expanded(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600))),
    ]),
  );
}

class BrokerConversationTools extends ConsumerWidget {
  const BrokerConversationTools({required this.thread, this.compact = false, super.key});
  final MessageThreadSummary thread;
  final bool compact;

  Future<void> _openClassification(BuildContext context, WidgetRef ref, String stage) async {
    final selected = await showActorModalBottomSheet<String>(
      context: context,
      ref: ref,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('تصنيف العميل', style: Theme.of(sheet).textTheme.titleMedium),
              const SizedBox(height: 10),
              CustomerStageChoices(
                stage: stage,
                supportsClassification: thread.customerStageClassificationV2,
                onSelected: (value) => Navigator.pop(sheet, value),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && context.mounted) {
      await saveCustomerStage(context, ref, thread.id, selected);
    }
  }

  Widget _compactActions(BuildContext context, WidgetRef ref, String stage) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final iconSpace = MediaQuery.sizeOf(context).width >= 340 &&
        MediaQuery.textScalerOf(context).scale(11) <= 14;
    Widget action(String label, String key, VoidCallback? press, {IconData? icon, bool tonal = false}) {
      final style = OutlinedButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        foregroundColor: tonal ? scheme.onPrimaryContainer : scheme.primary,
        backgroundColor: tonal ? scheme.primaryContainer : null,
        side: BorderSide(color: press == null ? scheme.outlineVariant : scheme.primary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
      );
      return Expanded(child: OutlinedButton(
        key: ValueKey(key),
        style: style,
        onPressed: press,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (iconSpace && icon != null) ...[Icon(icon, size: 14), const SizedBox(width: 4)],
          Flexible(child: Text(label, textAlign: TextAlign.center)),
        ]),
      ));
    }

    return ColoredBox(
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          if (!thread.isPropertyUnavailable) ...[
            action('هذا الإعلان', 'conversation-property',
                () => context.push('/properties/${thread.propertyId}')),
            if (thread.canManageCustomer) const SizedBox(width: 6),
          ],
          if (thread.canManageCustomer) ...[
            action('تصنيف العميل', 'conversation-classification',
                stage == 'completed' ? null : () => _openClassification(context, ref, stage),
                icon: Icons.expand_more),
            const SizedBox(width: 6),
            action('ملاحظة وتذكير', 'conversation-followup',
                () => editCustomerFollowup(context, ref, thread.id),
                icon: Icons.event_note_outlined, tonal: true),
          ],
        ]),
      ),
    );
  }

  Future<void> _openManagement(BuildContext context, WidgetRef ref, BrokerDeal? deal,
      String stage, {required bool dealsLoaded}) async {
    final scope = ref.read(accountRequestScopeProvider);
    final selected = await AppBottomSheet.show<String>(context, builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(thread.canManageCustomer ? 'إدارة العميل' : 'نتيجة الصفقة',
              style: Theme.of(sheet).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (thread.canManageCustomer && stage != 'completed') ...[
              Text('تصنيف العميل', style: Theme.of(sheet).textTheme.titleSmall),
              const SizedBox(height: 6),
              CustomerStageChoices(
                stage: stage,
                supportsClassification: thread.customerStageClassificationV2,
                onSelected: (stage) => Navigator.pop(sheet, stage),
              ),
              const Divider(),
            ],
            if (deal != null) ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.handshake_outlined),
              title: Text(deal.resultActionLabel),
              subtitle: Text(deal.statusLabel),
              onTap: () {
                Navigator.pop(sheet);
                if (context.mounted && scope.isCurrent) context.push('/broker/deals/${deal.id}');
              },
            ),
            if (thread.canManageCustomer) ...[
              if (dealsLoaded && deal == null && stage != 'completed') ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.check_circle_outline),
                title: const Text('تسجيل نتيجة الصفقة'),
                onTap: () {
                  Navigator.pop(sheet);
                  if (context.mounted && scope.isCurrent) {
                    reportBrokerDeal(context, ref, thread.id, propertyId: thread.propertyId);
                  }
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_note_outlined),
                title: const Text('ملاحظة وتذكير'),
                onTap: () {
                  Navigator.pop(sheet);
                  if (context.mounted && scope.isCurrent) editCustomerFollowup(context, ref, thread.id);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: const Text('متابعة العميل'),
                onTap: () {
                  Navigator.pop(sheet);
                  if (context.mounted && scope.isCurrent) context.push('/broker/customers?property=${thread.propertyId}');
                },
              ),
            ],
          ]),
      ),
    ));
    if (selected != null && context.mounted && scope.isCurrent) {
      await saveCustomerStage(context, ref, thread.id, selected);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (thread.propertyId == null || (!thread.canManageCustomer && compact && thread.isPropertyUnavailable)) {
      return const SizedBox.shrink();
    }
    final dealData = ref.watch(brokerThreadDealProvider(thread.id)).asData;
    final deal = dealData?.value;
    final stage = deal?.status == 'confirmed' ? 'completed' : thread.leadStage;
    if (compact) return _compactActions(context, ref, stage);
    if (!thread.canManageCustomer && deal == null) return const SizedBox.shrink();

    final stageLabel = brokerLeadLabels[stage];
    return Align(alignment: AlignmentDirectional.centerStart, child: Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton.icon(
          key: const ValueKey('conversation-manage-customer'),
          icon: const Icon(Icons.tune, size: 18),
          label: Text(thread.canManageCustomer ? 'إدارة العميل' : 'نتيجة الصفقة'),
          onPressed: () => _openManagement(context, ref, deal, stage, dealsLoaded: dealData != null),
        ),
        if (thread.canManageCustomer && stageLabel != null)
          AppStatusBadge(label: stageLabel,
            tone: stage == 'completed' ? AppStatusTone.success : AppStatusTone.info),
      ],
    ));
  }
}

class BrokerFinanceScreen extends ConsumerWidget {
  const BrokerFinanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return BrokerScaffold(
      appBar: const AppAppBar(title: 'مستحقات المنصة'),
      body: ref.watch(brokerFinanceProvider).when(
        loading: () => const AppLoadingState(),
        error: (error, _) => AppErrorState(
          message: friendlyApiError(error),
          onRetry: () => ref.invalidate(brokerFinanceProvider),
        ),
        data: (data) {
          final dues = brokerRows(data['receivables']).where((due) =>
            brokerNumber(due['remaining_amount']) > 0 && due['status'] != 'paid');
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(brokerFinanceProvider);
              try {
                await ref.read(brokerFinanceProvider.future);
              } catch (_) {
                // The page renders the error and offers retry.
              }
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                for (final balance in brokerRows(data['balances']))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: BrokerPanel(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('المستحق: ${brokerMoney(balance['open'], '${balance['currency']}')}',
                          style: theme.textTheme.titleMedium),
                        Text('المدفوع: ${brokerMoney(balance['paid'], '${balance['currency']}')}'),
                      ],
                    )),
                  ),
                if (dues.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.info_outline, size: 16, color: theme.colorScheme.error),
                      const SizedBox(width: 6),
                      Expanded(child: Text(
                        'يصلك تذكير كل ٢٤ ساعة حتى تأكيد سداد المستحق.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                      )),
                    ]),
                  ),
                for (final due in dues)
                  _BrokerReceivableCard(due: due),
                if (dues.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('لا توجد مستحقات متبقية حاليًا.'),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BrokerReceivableCard extends ConsumerWidget {
  const _BrokerReceivableCard({required this.due});
  final Map<String, dynamic> due;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = due['status'];
    final isRent = due['transaction_type'] == 'rent';
    final amountLabel = switch (due['transaction_type']) {
      'sale' => 'إجمالي سعر العقار',
      'rent' => 'الإيجار الشهري',
      _ => 'المبلغ المعتمد للصفقة',
    };
    final basis = isRent ? due['monthly_basis_amount'] ?? due['basis_amount'] : due['basis_amount'];
    final deadline = DateTime.tryParse('${due['due_at'] ?? ''}')?.toLocal();
    final currency = '${due['currency'] ?? 'YER'}';
    final title = '${due['property_title'] ?? 'العقار'}';
    final localizations = MaterialLocalizations.of(context);
    final remaining = brokerNumber(due['remaining_amount']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: BrokerPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        Text('المرجع: ${due['reference']}'),
        Text('$amountLabel: ${brokerMoney(basis, currency)}'),
        Text('إجمالي السعي: ${brokerMoney(due['sai_amount'], currency)}'),
        Text('حصة المنصة: ${brokerMoney(due['amount_total'], currency)}'),
        Text('المتبقي: ${brokerMoney(remaining, currency)}'),
        if (status == 'under_review') const Text('إثبات السداد قيد التحقق'),
        if (status == 'disputed') const Text('قيد مراجعة الدعم'),
        if (deadline != null)
          Text('موعد السداد: ${localizations.formatCompactDate(deadline)} · '
              '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(deadline))}'),
        if (status == 'open' || status == 'overdue')
          AppButton(label: 'سداد مستحقات المنصة', onPressed: () async {
            final scope = ref.read(accountRequestScopeProvider);
            if (!scope.isCurrent) return;
            await Navigator.of(context).push(MaterialPageRoute<bool>(
              builder: (_) => ReceivablePaymentScreen(
                receivableId: brokerInt(due['id']),
                remainingAmount: remaining,
                currency: currency,
                propertyTitle: title,
                requestScope: scope,
              ),
            ));
            if (context.mounted && scope.isCurrent) refreshBrokerData(ref);
          }),
      ])),
    );
  }
}

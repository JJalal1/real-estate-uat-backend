import 'package:flutter/material.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../data/property_repository.dart';
import '../domain/property_sai.dart';

/// Returns true only when the listing has sai terms that may proceed to review.
/// A professional explicitly rejecting the 20% platform condition is persisted
/// as a rejected term version and returns false, so publication stays blocked.
Future<bool> showPropertySaiConfigurationSheet(
  BuildContext context, {
  required PropertyRepository repository,
  required int propertyId,
  required String purpose,
}) async {
  final initial = await repository.sai(propertyId);
  if (!context.mounted) return false;

  return await AppBottomSheet.show<bool>(
        context,
        builder: (sheetContext) => _SaiConfigurationBody(
          repository: repository,
          propertyId: propertyId,
          purpose: purpose,
          initial: initial,
        ),
      ) ??
      false;
}

class _SaiConfigurationBody extends StatefulWidget {
  const _SaiConfigurationBody({
    required this.repository,
    required this.propertyId,
    required this.purpose,
    required this.initial,
  });

  final PropertyRepository repository;
  final int propertyId;
  final String purpose;
  final PropertySaiEnvelope initial;

  @override
  State<_SaiConfigurationBody> createState() => _SaiConfigurationBodyState();
}

class _SaiConfigurationBodyState extends State<_SaiConfigurationBody> {
  late final TextEditingController _rateController;
  late final TextEditingController _amountController;
  String _amountType = 'percentage';
  String? _payer;
  bool _busy = false;
  String? _error;

  PropertySaiManagement get management => widget.initial.management ??
      const PropertySaiManagement(configured: false, advertiserType: 'owner');

  bool get isSale => widget.purpose == 'sale';
  bool get isOwner => management.isOwner;
  double get fixedRate => management.fixedRatePercent ?? (isSale ? 1 : 20);
  double get maxProfessionalRate =>
      management.brokerMaxRatePercent ?? (isSale ? 5 : 100);
  double get enteredRate => parseSaiNumber(_rateController.text) ?? double.nan;
  double get enteredAmount => parseSaiNumber(_amountController.text) ?? double.nan;
  bool get fixed => !isOwner && _amountType == 'fixed';
  bool get custom => fixed ? enteredAmount.isFinite && enteredAmount > 0
      : enteredRate.isFinite && enteredRate > 0 && enteredRate <= maxProfessionalRate;

  @override
  void initState() {
    super.initState();
    final currentRequested = management.requestedBrokerRatePercent;
    _rateController = TextEditingController(
      text: currentRequested == null ? '' : _formatRate(currentRequested),
    );
    _amountController = TextEditingController(text: management.fixedAmount?.toString() ?? '');
    _amountType = management.amountType;
    _payer = isSale ? 'buyer' : 'tenant';
  }

  @override
  void dispose() {
    _rateController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = fixed ? enteredAmount : enteredRate;
    final effective = isOwner || active == 0 ? fixedRate : active;
    final payerLabel = isSale ? 'المشتري' : 'المستأجر';
    final display = fixed && active.isFinite && active > 0
        ? 'السعي ${_formatRate(active)} ${management.fixedCurrency ?? 'YER'}'
        : fixed && !active.isFinite ? 'حدد مبلغ السعي'
        : 'السعي ${effective.isFinite ? _formatRate(effective) : '—'}% يتحمله $payerLabel';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          AppLayout.compactPageGutter,
          AppSpacing.s16,
          AppLayout.compactPageGutter,
          MediaQuery.viewInsetsOf(context).bottom + AppSpacing.s24,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSectionHeader(
                title: 'تحديد السعي قبل إرسال الإعلان',
                subtitle: isOwner
                    ? 'نسبة السعي ثابتة في النظام ويتحملها العميل.'
                    : 'حدد نسبة السعي ضمن الحد المسموح.',
              ),
              const SizedBox(height: AppSpacing.s16),
              if (isOwner)
                AppInlineMessage(
                  title: isSale ? 'السعي 1%' : 'السعي 20%',
                  message: isSale
                      ? 'النسبة ثابتة ولا يمكن للمالك تغييرها.'
                      : 'النسبة ثابتة من قيمة إيجار الشهر الأول فقط ولا يمكن للمالك تغييرها.',
                  tone: AppStatusTone.info,
                )
              else ...[
                Wrap(spacing: 8, runSpacing: 6, children: [
                  ChoiceChip(label: const Text('نسبة مئوية %'), selected: !fixed,
                    onSelected: _busy ? null : (_) => setState(() => _amountType = 'percentage')),
                  ChoiceChip(label: const Text('مبلغ ثابت'), selected: fixed,
                    onSelected: _busy ? null : (_) => setState(() => _amountType = 'fixed')),
                ]),
                const SizedBox(height: AppSpacing.s12),
                TextField(
                  controller: fixed ? _amountController : _rateController,
                  enabled: !_busy,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: fixed ? 'مبلغ السعي بالريال اليمني' : 'نسبة السعي %',
                    hintText: '0',
                    helperText: fixed ? 'مبلغ ثابت لا يتغير بتغير سعر إتمام الصفقة.' : isSale
                        ? 'المسموح من 0% إلى 5%.'
                        : 'المسموح من 0% إلى 100% من إيجار الشهر الأول.',
                  ),
                  onChanged: (_) => setState(() => _error = null),
                ),
                const SizedBox(height: AppSpacing.s12),
                if ((fixed ? enteredAmount : enteredRate) == 0)
                  AppInlineMessage(
                    title: 'سعي الدلال/المكتب 0%',
                    message: isSale
                        ? 'سيُفعّل تلقائياً السعي الثابت 1%، وليس صفقة بدون سعي.'
                        : 'سيُفعّل تلقائياً السعي الثابت 20% من إيجار الشهر الأول، وليس صفقة بدون سعي.',
                    tone: AppStatusTone.info,
                  )
                else if (custom)
                  const AppInlineMessage(
                    message: 'للتطبيق نسبة مقدارها 20% من مبلغ السعي عند إتمام الصفقة.',
                    tone: AppStatusTone.warning,
                  ),
              ],
              const SizedBox(height: AppSpacing.s16),
              Text(display,
                style: Theme.of(context).textTheme.bodyMedium),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.s8),
                AppInlineMessage(message: _error!, tone: AppStatusTone.error),
              ],
              const SizedBox(height: AppSpacing.s20),
              if (!isOwner && custom)
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: 'رفض',
                        style: AppButtonStyle.outlined,
                        loading: _busy,
                        onPressed: _busy ? null : () => _save('reject'),
                        expand: true,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    Expanded(
                      child: AppButton(
                        label: 'قبول',
                        loading: _busy,
                        onPressed: _busy ? null : () => _save('accept'),
                        expand: true,
                      ),
                    ),
                  ],
                )
              else
                AppButton(
                  label: 'تأكيد السعي والمتابعة',
                  loading: _busy,
                  onPressed: _busy ? null : () => _save(null),
                  expand: true,
                ),
              const SizedBox(height: AppSpacing.s8),
              AppButton(
                label: 'العودة بدون إرسال',
                style: AppButtonStyle.text,
                onPressed: _busy ? null : () => Navigator.pop(context, false),
                expand: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save(String? decision) async {
    final payer = _payer;
    if (payer == null) {
      setState(() => _error = 'يجب تحديد الطرف الذي يتحمل السعي.');
      return;
    }

    final rate = enteredRate;
    if (!isOwner && (fixed ? !enteredAmount.isFinite || enteredAmount < 0
        : !rate.isFinite || rate < 0 || rate > maxProfessionalRate)) {
      setState(() {
        _error = fixed ? 'أدخل مبلغ سعي صحيحًا أكبر من أو يساوي صفرًا.' : isSale
            ? 'نسبة السعي في البيع يجب أن تكون بين 0% و5%.'
            : 'نسبة السعي في الإيجار يجب أن تكون بين 0% و100% من إيجار الشهر الأول.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.repository.configureSai(
        widget.propertyId,
        payer: payer,
        brokerRatePercent: isOwner || fixed ? null : rate,
        amountType: fixed ? 'fixed' : 'percentage',
        fixedAmount: fixed ? enteredAmount : null,
        platformTermsDecision: decision,
      );
      if (!mounted) return;
      final rejected = result.management?.platformTermsStatus == 'rejected';
      Navigator.pop(context, !rejected);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = friendlyApiError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _formatRate(double rate) {
    if (rate == rate.roundToDouble()) return rate.toInt().toString();
    return rate.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
}

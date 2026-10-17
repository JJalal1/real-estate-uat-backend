import 'package:flutter/material.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../data/property_repository.dart';
import '../domain/property_sai.dart';
import 'listing_sai_section.dart';

/// Returns true only when the listing has sai terms that may proceed to review.
/// A professional explicitly rejecting the server's platform condition is persisted
/// as a rejected term version and returns false, so publication stays blocked.
Future<bool> showPropertySaiConfigurationSheet(
  BuildContext context, {
  required PropertyRepository repository,
  required int propertyId,
  required String purpose,
  required double basis,
}) async {
  final initial = await repository.saiForEditor(propertyId);
  if (initial.management == null) throw StateError('تعذر تحميل سياسة السعي. أعد المحاولة.');
  if (!context.mounted) return false;

  return await AppBottomSheet.show<bool>(
        context,
        builder: (sheetContext) => _SaiConfigurationBody(
          repository: repository,
          propertyId: propertyId,
          purpose: purpose,
          basis: basis,
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
    required this.basis,
  });

  final PropertyRepository repository;
  final int propertyId;
  final String purpose;
  final PropertySaiEnvelope initial;
  final double basis;

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

  PropertySaiManagement get management => widget.initial.management!;

  bool get isSale => widget.purpose == 'sale';
  bool get isOwner => management.isOwner;
  double? get maxProfessionalRate => management.brokerMaxRatePercent;
  double get enteredRate => parseSaiNumber(_rateController.text) ?? double.nan;
  double get enteredAmount => parseSaiNumber(_amountController.text) ?? double.nan;
  bool get fixed => !isOwner && _amountType == 'fixed';
  PropertySaiQuote? get quote => PropertySaiQuote.calculate(management, isOwner ? (management.fixedRatePercent ?? double.nan) : enteredRate, widget.basis,
      fixedAmount: fixed ? enteredAmount : null);
  bool get custom => !isOwner && quote != null && !quote!.fallback;

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
                    : 'حدد السعي ضمن الحد المسموح.',
              ),
              ListingSaiSection(
                purpose: widget.purpose, policy: management, basis: widget.basis,
                rateController: _rateController, amountController: _amountController, amountType: _amountType,
                accepted: false, enabled: !_busy, onChanged: () => setState(() => _error = null),
                onAcceptanceChanged: (_) {}, onRetry: () {},
                onAmountTypeChanged: (value) => setState(() {
                  _amountType = value; _error = null;
                  if (fixed) { _rateController.clear(); } else { _amountController.clear(); }
                }),
              ),
              const SizedBox(height: AppSpacing.s16),
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
    if (quote == null) {
      setState(() => _error = fixed
          ? 'أدخل مبلغ سعي صحيحًا ضمن الحد الذي تسمح به سياسة الإعلان.'
          : 'أدخل نسبة سعي صحيحة من 0 إلى ${maxProfessionalRate == null ? '—' : _formatRate(maxProfessionalRate!)}%.');
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

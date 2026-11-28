import 'package:flutter/material.dart';

import '../../../core/widgets/app_components.dart';
import '../../../core/formatters/latin_number_input.dart';
import '../domain/property_sai.dart';
import '../domain/arabic_price_words.dart';

class ListingSaiSection extends StatelessWidget {
  const ListingSaiSection({
    required this.purpose,
    required this.policy,
    required this.rateController,
    required this.basis,
    required this.accepted,
    required this.onChanged,
    required this.onAcceptanceChanged,
    required this.onRetry,
    this.amountController,
    this.amountType = 'fixed',
    this.onAmountTypeChanged,
    this.onEditHistoricalTerms,
    this.currency = 'YER',
    this.keepConfiguredShare = false,
    this.error,
    this.enabled = true,
    super.key,
  });

  final String purpose, amountType;
  final PropertySaiManagement? policy;
  final TextEditingController rateController;
  final TextEditingController? amountController;
  final double? basis;
  final bool accepted, enabled;
  final String currency;
  final bool keepConfiguredShare;
  final VoidCallback onChanged, onRetry;
  final VoidCallback? onEditHistoricalTerms;
  final ValueChanged<bool> onAcceptanceChanged;
  final ValueChanged<String>? onAmountTypeChanged;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final current = policy;
    final theme = Theme.of(context);
    final historicalFixed = current?.hasHistoricalFixedTerms == true;
    final fixed = amountType == 'fixed' && !historicalFixed;
    final rate = historicalFixed ? current?.effectiveFixedRate
        : parseSaiNumber(rateController.text);
    final enteredAmount = fixed ? parseSaiNumber(amountController?.text ?? '') : null;
    final words = enteredAmount == null || !enteredAmount.isFinite || (enteredAmount * 100 - (enteredAmount * 100).round()).abs() > .000001
        ? null : enteredAmount == 0 ? 'صفر ${currencyLabel(currency)}' : arabicRiyalAmountInWords(enteredAmount.toStringAsFixed(2), currency: currency);
    final rateError = !fixed && rate != null && rate > 100 ? 'أقصى نسبة للسعي 100%' : null;
    final quote = current == null || basis == null ||
        (fixed ? enteredAmount == null : rate == null)
        ? null : PropertySaiQuote.calculate(current, rate ?? 0, basis!, fixedAmount: enteredAmount, keepConfiguredShare: keepConfiguredShare);
    String percent(double value) => value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
    final fixedRate = current?.effectiveFixedRate;
    final fixedRateText = fixedRate == null ? '—' : percent(fixedRate);
    final maximumText = current?.brokerMaxRatePercent?.toStringAsFixed(0) ?? '—';
    final basisText = purpose == 'rent' ? 'إيجار الشهر الأول' : 'سعر البيع';
    final zeroText = fixed ? '0' : '0%';
    String amount(double value) =>
        '${formatMoneyAmount(value, englishDigits: true)} ${currencyLabel(currency)}';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Divider(height: 32),
      Text('السعي', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      const SizedBox(height: 14),
      if (current == null)
        error == null ? const AppSkeleton(height: 52, radius: 6)
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(error!, style: TextStyle(color: theme.colorScheme.error)),
              TextButton(onPressed: enabled ? onRetry : null,
                  child: const Text('إعادة تحميل سياسة السعي')),
            ])
      else ...[
        if (historicalFixed) ...[
          Text('النسبة الثابتة المسجّلة $fixedRateText%'),
          if (onEditHistoricalTerms != null)
            TextButton(key: const ValueKey('listing-sai-edit-historical'),
              onPressed: enabled ? onEditHistoricalTerms : null,
              child: const Text('تغيير السعي')),
        ] else ...[
          Wrap(spacing: 8, runSpacing: 6, children: [
            ChoiceChip(key: const ValueKey('listing-sai-percentage'),
              label: const Text('نسبة مئوية %'), selected: !fixed,
              onSelected: !enabled ? null : (_) => onAmountTypeChanged?.call('percentage')),
            ChoiceChip(key: const ValueKey('listing-sai-fixed'),
              label: const Text('مبلغ ثابت'), selected: fixed,
              onSelected: !enabled ? null : (_) => onAmountTypeChanged?.call('fixed')),
          ]),
          const SizedBox(height: 12),
          if (fixed)
            TextField(key: const ValueKey('listing-sai-amount'), controller: amountController,
              enabled: enabled, inputFormatters: [latinNumberInput], keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'مقدار السعي ${listingCurrencyPhrases[currency] ?? currency}', hintText: '0',
                helperText: words, helperMaxLines: 4),
              onChanged: (_) => onChanged())
          else
            TextField(key: const ValueKey('listing-sai-rate'), controller: rateController,
              enabled: enabled, inputFormatters: [latinNumberInput], keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'نسبة السعي %', hintText: '0',
                errorText: rateError,
                helperText: 'من 0 إلى $maximumText% من $basisText'),
              onChanged: (_) => onChanged()),
        ],
        if (!historicalFixed) Padding(padding: const EdgeInsets.only(top: 8),
          child: Text('حصة المنصة تحسب على ناشر الإعلان',
            style: theme.textTheme.bodySmall)),
        if (quote != null) ...[
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline, size: 16, color: theme.colorScheme.primary), const SizedBox(width: 6),
            Expanded(child: Text('حصة المنصة ${percent(quote.platformPercent)}% وهي ${amount(quote.platform)} من سعي المعلن الذي هو ${amount(quote.total)}',
              key: const ValueKey('listing-sai-total'), style: theme.textTheme.bodySmall)),
          ]),
        ],
        if (!historicalFixed && (fixed ? enteredAmount == 0 : rate == 0)) ...[
          const SizedBox(height: 8),
          Text('اختيار $zeroText يفعّل السعي الثابت $fixedRateText% تلقائيًا.',
              style: theme.textTheme.bodySmall),
        ],
      ],
    ]);
  }
}

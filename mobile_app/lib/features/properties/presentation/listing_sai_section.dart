import 'package:flutter/material.dart';

import '../../../core/widgets/app_components.dart';
import '../domain/property_sai.dart';

class ListingSaiSection extends StatelessWidget {
  const ListingSaiSection({required this.purpose, required this.policy,
    required this.rateController, required this.basis, required this.accepted,
    required this.onChanged, required this.onAcceptanceChanged,
    required this.onRetry, this.error, this.enabled = true, super.key});

  final String purpose;
  final PropertySaiManagement? policy;
  final TextEditingController rateController;
  final double? basis;
  final bool accepted, enabled;
  final VoidCallback onChanged, onRetry;
  final ValueChanged<bool> onAcceptanceChanged;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final current = policy;
    final theme = Theme.of(context);
    final rate = double.tryParse(rateController.text.trim());
    final quote = current == null || rate == null || basis == null
      ? null : PropertySaiQuote.calculate(current, rate, basis!);
    String amount(double value) => '${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2)} ريال';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Divider(height: 32),
      Text('السعي', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Text(purpose == 'rent' ? 'يتحمله المستأجر، ويُحسب على إيجار شهر واحد.' : 'يتحمله المشتري، ويُحسب على سعر البيع.',
        style: theme.textTheme.bodySmall),
      const SizedBox(height: 14),
      if (current == null)
        error == null ? const AppSkeleton(height: 52, radius: 6)
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(error!, style: TextStyle(color: theme.colorScheme.error)),
            TextButton(onPressed: enabled ? onRetry : null, child: const Text('إعادة تحميل سياسة السعي')),
          ])
      else ...[
        if (current.isOwner)
          Text('النسبة الثابتة ${current.fixedRatePercent?.toStringAsFixed(0) ?? '—'}%')
        else
          TextField(key: const ValueKey('listing-sai-rate'), controller: rateController,
            enabled: enabled, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'نسبة السعي %',
              helperText: 'من 0 إلى ${current.brokerMaxRatePercent?.toStringAsFixed(0) ?? '—'}%'),
            onChanged: (_) => onChanged()),
        if (quote != null) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 4, children: [
            Text('قيمة السعي', style: theme.textTheme.bodyMedium),
            Text(amount(quote.total), key: const ValueKey('listing-sai-total'),
              style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary)),
          ]),
          const SizedBox(height: 4),
          Text(current.isOwner ? 'مستحق المنصة: ${amount(quote.platform)}'
              : 'صافي السعي: ${amount(quote.net)} · مستحق المنصة: ${amount(quote.platform)}',
            key: const ValueKey('listing-sai-net'), style: theme.textTheme.bodySmall),
        ],
        if (!current.isOwner && rate == 0) ...[
          const SizedBox(height: 8),
          Text('اختيار 0% يفعّل السعي الثابت ${current.fixedRatePercent?.toStringAsFixed(0) ?? '—'}% للمنصة؛ صافي سعيك صفر.',
            style: theme.textTheme.bodySmall),
        ],
        if (!current.isOwner && rate != null && rate > 0)
          CheckboxListTile(key: const ValueKey('listing-sai-acceptance'),
            contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading,
            value: accepted, onChanged: enabled ? (value) => onAcceptanceChanged(value == true) : null,
            title: Text(current.platformTermsMessage ?? 'أوافق على مستحق المنصة الموضح.', style: theme.textTheme.bodySmall)),
        const SizedBox(height: 6),
        Text('المبالغ تقديرية حسب السعر؛ التسوية تُحسب عند تأكيد نتيجة الصفقة.', style: theme.textTheme.bodySmall),
      ],
    ]);
  }
}

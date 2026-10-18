String currencyLabel(String currency) => switch (currency.toUpperCase()) {
  'YER' => 'ريال', 'SAR' => 'ريال سعودي', 'USD' => 'دولار أمريكي', _ => currency,
};

String arabicDigits(String text) {
  const digits = '٠١٢٣٤٥٦٧٨٩';
  return text.replaceAllMapped(RegExp(r'[0-9]'), (match) => digits[int.parse(match[0]!)]);
}

/// Groups the exact decimal string, without rounding or scaling a monetary value.
String formatMoneyAmount(Object amount) {
  const eastern = '٠١٢٣٤٥٦٧٨٩';
  var raw = amount.toString().replaceAll('٬', '').replaceAll(',', '').replaceAll('٫', '.');
  for (var i = 0; i < eastern.length; i++) { raw = raw.replaceAll(eastern[i], '$i'); }
  if (!RegExp(r'^-?\d+(?:\.\d+)?$').hasMatch(raw)) return arabicDigits(raw);
  final negative = raw.startsWith('-');
  if (negative) raw = raw.substring(1);
  final parts = raw.split('.');
  final whole = parts.first.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (match) => '${match[1]}٬');
  final decimal = parts.length == 2 ? parts[1].replaceFirst(RegExp(r'0+$'), '') : '';
  return arabicDigits('${negative ? '−' : ''}$whole${decimal.isEmpty ? '' : '٫$decimal'}');
}

String moneyLabel(Object amount, String currency) => '${formatMoneyAmount(amount)} ${currencyLabel(currency)}';

String localizedMoneyText(String text) {
  var result = text.replaceAllMapped(RegExp(r'(YER|USD|SAR)\s*([0-9][0-9,.]*)'),
    (m) => moneyLabel(m[2]!, m[1]!));
  result = result.replaceAllMapped(RegExp(r'([0-9][0-9,.]*)\s*(YER|USD|SAR)'),
    (m) => moneyLabel(m[1]!, m[2]!));
  return result.replaceAllMapped(RegExp(r'\b(YER|USD|SAR)\b'), (m) => currencyLabel(m[1]!));
}

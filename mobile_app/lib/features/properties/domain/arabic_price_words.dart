String? arabicRiyalAmountInWords(String rawValue) {
  final normalized = rawValue.replaceAll(',', '').trim();
  final value = int.tryParse(normalized);
  if (value == null || value <= 0) return null;
  return '${arabicIntegerInWords(value)} ريال يمني';
}

String arabicIntegerInWords(int value) {
  if (value == 0) return 'صفر';
  if (value < 0) return 'سالب ${arabicIntegerInWords(-value)}';

  const scales = <_Scale>[
    _Scale('', '', '', ''),
    _Scale('ألف', 'ألفان', 'آلاف', 'ألف'),
    _Scale('مليون', 'مليونان', 'ملايين', 'مليون'),
    _Scale('مليار', 'ملياران', 'مليارات', 'مليار'),
    _Scale('تريليون', 'تريليونان', 'تريليونات', 'تريليون'),
  ];

  final parts = <String>[];
  var remaining = value;
  var scaleIndex = 0;
  while (remaining > 0 && scaleIndex < scales.length) {
    final group = remaining % 1000;
    if (group > 0) {
      final scale = scales[scaleIndex];
      if (scaleIndex == 0) {
        parts.add(_threeDigits(group));
      } else if (group == 1) {
        parts.add(scale.singular);
      } else if (group == 2) {
        parts.add(scale.dual);
      } else {
        final groupWords = _threeDigits(group);
        final scaleWord = group >= 3 && group <= 10
            ? scale.plural
            : scale.accusativeSingular;
        parts.add('$groupWords $scaleWord');
      }
    }
    remaining ~/= 1000;
    scaleIndex++;
  }

  return parts.reversed.join(' و');
}

String _threeDigits(int value) {
  if (value <= 0 || value >= 1000) {
    throw ArgumentError.value(value, 'value', 'Expected 1..999');
  }

  const hundreds = <int, String>{
    1: 'مائة',
    2: 'مائتان',
    3: 'ثلاثمائة',
    4: 'أربعمائة',
    5: 'خمسمائة',
    6: 'ستمائة',
    7: 'سبعمائة',
    8: 'ثمانمائة',
    9: 'تسعمائة',
  };

  final parts = <String>[];
  final hundred = value ~/ 100;
  final rest = value % 100;
  if (hundred > 0) parts.add(hundreds[hundred]!);
  if (rest > 0) parts.add(_underHundred(rest));
  return parts.join(' و');
}

String _underHundred(int value) {
  const ones = <int, String>{
    1: 'واحد',
    2: 'اثنان',
    3: 'ثلاثة',
    4: 'أربعة',
    5: 'خمسة',
    6: 'ستة',
    7: 'سبعة',
    8: 'ثمانية',
    9: 'تسعة',
    10: 'عشرة',
    11: 'أحد عشر',
    12: 'اثنا عشر',
    13: 'ثلاثة عشر',
    14: 'أربعة عشر',
    15: 'خمسة عشر',
    16: 'ستة عشر',
    17: 'سبعة عشر',
    18: 'ثمانية عشر',
    19: 'تسعة عشر',
  };
  const tens = <int, String>{
    20: 'عشرون',
    30: 'ثلاثون',
    40: 'أربعون',
    50: 'خمسون',
    60: 'ستون',
    70: 'سبعون',
    80: 'ثمانون',
    90: 'تسعون',
  };

  if (value <= 19) return ones[value]!;
  final ten = (value ~/ 10) * 10;
  final one = value % 10;
  if (one == 0) return tens[ten]!;
  return '${ones[one]} و${tens[ten]}';
}

class _Scale {
  const _Scale(
    this.singular,
    this.dual,
    this.plural,
    this.accusativeSingular,
  );

  final String singular;
  final String dual;
  final String plural;
  final String accusativeSingular;
}

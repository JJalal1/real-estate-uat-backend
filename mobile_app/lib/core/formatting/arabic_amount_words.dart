String arabicYemeniRialAmountWords(String raw) {
  final normalized = raw
      .replaceAll(',', '')
      .replaceAll('٬', '')
      .replaceAll(' ', '')
      .replaceAll('٠', '0')
      .replaceAll('١', '1')
      .replaceAll('٢', '2')
      .replaceAll('٣', '3')
      .replaceAll('٤', '4')
      .replaceAll('٥', '5')
      .replaceAll('٦', '6')
      .replaceAll('٧', '7')
      .replaceAll('٨', '8')
      .replaceAll('٩', '9');
  final number = double.tryParse(normalized);
  if (number == null || number <= 0) return '';
  final value = number.round();
  if (value == 0) return '';
  return '${_integerToArabicWords(value)} ريال يمني';
}

String _integerToArabicWords(int value) {
  if (value == 0) return 'صفر';
  final groups = <String>[];
  var remaining = value;
  var scale = 0;
  while (remaining > 0) {
    final group = remaining % 1000;
    if (group > 0) {
      groups.insert(0, _groupWithScale(group, scale));
    }
    remaining ~/= 1000;
    scale++;
  }
  return groups.join(' و');
}

String _groupWithScale(int value, int scale) {
  if (scale == 0) return _underThousand(value);
  const singular = ['', 'ألف', 'مليون', 'مليار', 'تريليون'];
  const dual = ['', 'ألفان', 'مليونان', 'ملياران', 'تريليونان'];
  const plural = ['', 'آلاف', 'ملايين', 'مليارات', 'تريليونات'];
  final safeScale = scale.clamp(1, singular.length - 1);
  if (value == 1) return singular[safeScale];
  if (value == 2) return dual[safeScale];
  if (value >= 3 && value <= 10) {
    return '${_underThousand(value)} ${plural[safeScale]}';
  }
  return '${_underThousand(value)} ${singular[safeScale]}';
}

String _underThousand(int value) {
  final parts = <String>[];
  final hundreds = value ~/ 100;
  final rest = value % 100;
  if (hundreds > 0) {
    const hundredsWords = <int, String>{
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
    parts.add(hundredsWords[hundreds]!);
  }
  if (rest > 0) parts.add(_underHundred(rest));
  return parts.join(' و');
}

String _underHundred(int value) {
  const small = <int, String>{
    1: 'واحد', 2: 'اثنان', 3: 'ثلاثة', 4: 'أربعة', 5: 'خمسة',
    6: 'ستة', 7: 'سبعة', 8: 'ثمانية', 9: 'تسعة', 10: 'عشرة',
    11: 'أحد عشر', 12: 'اثنا عشر', 13: 'ثلاثة عشر', 14: 'أربعة عشر',
    15: 'خمسة عشر', 16: 'ستة عشر', 17: 'سبعة عشر', 18: 'ثمانية عشر',
    19: 'تسعة عشر',
  };
  if (value < 20) return small[value]!;
  const tens = <int, String>{
    2: 'عشرون', 3: 'ثلاثون', 4: 'أربعون', 5: 'خمسون',
    6: 'ستون', 7: 'سبعون', 8: 'ثمانون', 9: 'تسعون',
  };
  final ten = value ~/ 10;
  final one = value % 10;
  if (one == 0) return tens[ten]!;
  return '${small[one]} و${tens[ten]}';
}

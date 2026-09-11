import 'package:flutter_test/flutter_test.dart';

import 'package:real_estate_mobile/core/formatting/arabic_amount_words.dart';

void main() {
  test('writes Yemeni rial price in Arabic words', () {
    expect(arabicYemeniRialAmountWords('1250000'), contains('مليون'));
    expect(arabicYemeniRialAmountWords('1250000'), endsWith('ريال يمني'));
    expect(arabicYemeniRialAmountWords('٠'), isEmpty);
  });
}

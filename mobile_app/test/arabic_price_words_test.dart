import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/properties/domain/arabic_price_words.dart';

void main() {
  group('Arabic price words', () {
    test('converts common Yemeni rial listing prices', () {
      expect(arabicRiyalAmountInWords('50000000'), 'خمسون مليون ريال يمني');
      expect(arabicRiyalAmountInWords('125000'),
          'مائة وخمسة وعشرون ألف ريال يمني');
      expect(arabicRiyalAmountInWords('2'), 'اثنان ريال يمني');
    });

    test('ignores empty, invalid, and zero values', () {
      expect(arabicRiyalAmountInWords(''), isNull);
      expect(arabicRiyalAmountInWords('abc'), isNull);
      expect(arabicRiyalAmountInWords('0'), isNull);
    });
  });
}

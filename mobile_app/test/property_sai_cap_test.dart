import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/properties/domain/property_sai.dart';

void main() {
  const policy = PropertySaiManagement(
    configured: false, advertiserType: 'broker', brokerMaxRatePercent: 100,
    fixedRatePercent: 1, fallbackPlatformSharePercent: 100,
    professionalPlatformSharePercent: 10,
  );

  String? error(String value, {String purpose = 'sale', bool fixed = true,
      double? basis = 10000000, double? max = 100, String currency = 'YER'}) =>
      validatePropertySaiInput(purpose: purpose, fixed: fixed, value: value,
          basis: basis, policyMaximumPercent: max, currency: currency);

  test('percentage uses the lower of the business cap and server policy', () {
    expect(error('٥', fixed: false), isNull);
    expect(error('5.01', fixed: false), contains('5%'));
    expect(error('100', fixed: false, purpose: 'rent'), isNull);
    expect(error('100.01', fixed: false, purpose: 'rent'), contains('100%'));
    expect(error('3.51', fixed: false, max: 3.5), contains('3.5%'));
    expect(error('5.01', fixed: false, max: null), contains('5%'));
    expect(error('100', fixed: false, purpose: 'rent', max: null), isNull);
  });

  test('fixed sale amount is floored to a cent and revalidated on price edits', () {
    expect(error('۵۰۰٬۰۰۰٫۰۰'), isNull);
    expect(error('500,000.01', currency: 'SAR'), contains('500,000 ريال سعودي'));
    expect(error('500,000', basis: 9500000), contains('475,000'));
    expect(error('4.99', basis: 99.99), isNull);
    expect(error('5', basis: 99.99), contains('4.99'));
    // Some exact decimal boundaries are lower than a whole cent as binary doubles.
    expect(maximumPropertySaiAmount('sale', 16.4, 5), .82);
    expect(maximumPropertySaiAmount('sale', 110.2, 5), 5.51);
    expect(maximumPropertySaiAmount('sale', 1000, 2.25), 22.5);
    expect(maximumPropertySaiAmount('sale', 1e-7, 5), 0);
    expect(maximumPropertySaiAmount('sale', 9999999999999, 5), 499999999999.95);
  });

  test('first monthly rent is the cap in the selected currency', () {
    expect(error('8,150.25', purpose: 'rent', basis: 8150.25), isNull);
    expect(error('8150.26', purpose: 'rent', basis: 8150.25, currency: 'USD'), contains('8,150.25 دولار أمريكي'));
    expect(error('49', purpose: 'rent', basis: 48), contains('48 ريال'));
    expect(error('100', purpose: 'rent', basis: 150, max: 50), contains('75 ريال'));
    expect(error('1000000000000', purpose: 'rent', basis: 2000000000000), isNotNull);
  });

  test('invalid decimals and missing or invalid basis cannot be saved', () {
    for (final item in ['', '-1', '1e2', '1.005', '1,2', 'Infinity', 'NaN']) {
      expect(error(item), isNotNull, reason: item);
      expect(error(item, fixed: false), isNotNull, reason: item);
    }
    for (final basis in <double?>[null, 0, -1, double.nan, double.infinity]) {
      expect(error('0', basis: basis), isNotNull);
    }
    expect(error('1', purpose: 'unknown'), isNotNull);
    expect(error('1', max: double.nan), isNotNull);
  });

  test('zero uses the configured fallback and both quote modes enforce the same cap', () {
    for (final fixed in [false, true]) {
      expect(error('0', fixed: fixed), isNull);
      final quote = PropertySaiQuote.calculate(policy, 0, 1000,
          purpose: 'sale', fixedAmount: fixed ? 0 : null)!;
      expect(quote.fallback, true);
      expect(quote.total, 10);
      expect(quote.platform, 10);
    }
    const invalidFallback = PropertySaiManagement(configured: false, advertiserType: 'broker',
        fixedRatePercent: 6, brokerMaxRatePercent: 5, fallbackPlatformSharePercent: 100);
    expect(PropertySaiQuote.calculate(invalidFallback, 0, 1000, purpose: 'sale'), isNull);
    expect(PropertySaiQuote.calculate(invalidFallback, 0, 1000, purpose: 'sale', fixedAmount: 0), isNull);
    expect(PropertySaiQuote.calculate(policy, 5.01, 1000, purpose: 'sale'), isNull);
    expect(PropertySaiQuote.calculate(policy, 0, 99.99, fixedAmount: 5, purpose: 'sale'), isNull);
    expect(PropertySaiQuote.calculate(policy, 0, 800, fixedAmount: 801, purpose: 'rent'), isNull);
    expect(PropertySaiQuote.calculate(policy, 0, 800, fixedAmount: 800, purpose: 'rent')?.platform, 80);
  });
}

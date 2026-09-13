import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/router/app_deep_links.dart';

void main() {
  test('Phase 5 agreement deep link opens exact private agreement route', () {
    final link = agreementAppDeepLink(12);
    expect(link.toString(), 'realestate://app/agreements/12');
    expect(internalLocationForAppLink(link), '/agreements/12');
  });

  test('Phase 5 rental contract deep link opens exact private contract route', () {
    final link = rentalContractAppDeepLink(31);
    expect(link.toString(), 'realestate://app/rental-contracts/31');
    expect(internalLocationForAppLink(link), '/rental-contracts/31');
  });

  test('Phase 5 deep links reject invalid ids and foreign ownership', () {
    expect(() => agreementAppDeepLink(0), throwsArgumentError);
    expect(() => rentalContractAppDeepLink(-1), throwsArgumentError);
    expect(
      internalLocationForAppLink(Uri.parse('realestate://app/agreements/nope')),
      isNull,
    );
    expect(
      internalLocationForAppLink(Uri.parse('realestate://other/rental-contracts/31')),
      isNull,
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/account/domain/yemen_admin_divisions.dart';

void main() {
  test('Yemen account-verification dropdown data is complete and unique', () {
    expect(YemenAdminDivisions.governorates.length, 22);
    expect(YemenAdminDivisions.totalDistrictCount, 335);
    expect(YemenAdminDivisions.governorates.toSet().length, 22);

    for (final governorate in YemenAdminDivisions.governorates) {
      final districts = YemenAdminDivisions.districtsFor(governorate);
      expect(districts, isNotEmpty, reason: governorate);
      expect(districts.toSet().length, districts.length, reason: governorate);
    }
  });

  test('legacy governorate spelling is normalized for stored UAT profiles', () {
    expect(YemenAdminDivisions.canonicalGovernorate('ذمار'), 'ذمار');
    expect(YemenAdminDivisions.canonicalGovernorate('ابين'), 'أبين');
    expect(YemenAdminDivisions.canonicalGovernorate('مارب'), 'مأرب');
    expect(YemenAdminDivisions.canonicalGovernorate('امانة العاصمه'),
        'أمانة العاصمة');
  });
}

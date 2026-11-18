import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/discovery/data/assisted_search_suggestions.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_repository.dart';

// Public identities, independent of the presence of listings in each region.
const _governorates = {
  'AMANAT_AL_ASIMAH': 'أمانة العاصمة',
  'SANAA': 'صنعاء',
  'ADEN': 'عدن',
  'TAIZ': 'تعز',
  'HODEIDAH': 'الحديدة',
  'IBB': 'إب',
  'DHAMAR': 'ذمار',
  'HADRAMOUT': 'حضرموت',
  'HAJJAH': 'حجة',
  'SAADAH': 'صعدة',
  'AMRAN': 'عمران',
  'AL_JAWF': 'الجوف',
  'MARIB': 'مأرب',
  'AL_MAHWIT': 'المحويت',
  'RAYMAH': 'ريمة',
  'SHABWAH': 'شبوة',
  'LAHJ': 'لحج',
  'ABYAN': 'أبين',
  'AL_DALEA': 'الضالع',
  'AL_BAYDA': 'البيضاء',
  'AL_MAHRAH': 'المهرة',
  'SOCOTRA': 'أرخبيل سقطرى',
};

final _regions = [
  for (final entry in _governorates.entries)
    HomeLocation(
      governorate: entry.value,
      governorateCode: entry.key,
      manual: true,
    ),
];

void main() {
  test('confirmed Dhamar uses its identity instead of the default Sanaa label', () {
    const location = HomeLocation(
      latitude: 14.55,
      longitude: 44.4,
      governorate: 'ذمار',
      governorateCode: 'DHAMAR',
      device: true,
    );
    final before = Map<String, dynamic>.from(location.searchContext);
    final suggestions = AssistedSearchSuggestions.forLocation(
      location,
      regions: _regions,
    );
    expect(location.label, 'صنعاء');
    expect(suggestions.governorate, 'ذمار');
    expect(suggestions.hint, 'شقة للإيجار في ذمار، ثلاث غرف…');
    expect(suggestions.examples, [
      'شقة للإيجار في ذمار', 'منزل للبيع', 'أرض في ذمار',
    ]);
    expect(location.searchContext, before);
    expect(location.device, isTrue);
    expect(location.manual, isFalse);
  });

  test('all 22 public registry identities produce examples, including Socotra', () {
    expect(_regions, hasLength(22));
    for (final region in _regions) {
      final suggestions = AssistedSearchSuggestions.forLocation(
        HomeLocation(governorateCode: region.governorateCode, device: true),
        regions: _regions,
      );
      expect(suggestions.governorate, region.governorate);
      expect(suggestions.hint, 'شقة للإيجار في ${region.governorate}، ثلاث غرف…');
      expect(suggestions.examples.last, 'أرض في ${region.governorate}');
    }
  });

  test('manual governorate remains authoritative regardless of device coordinates', () {
    const manual = HomeLocation(
      latitude: 14.55,
      longitude: 44.4,
      governorate: 'إب',
      governorateCode: 'IBB',
      label: 'اختياري: إب',
      manual: true,
    );
    final suggestions = AssistedSearchSuggestions.forLocation(manual, regions: _regions);
    expect(suggestions.governorate, 'إب');
    expect(suggestions.examples.first, 'شقة للإيجار في إب');
    expect(manual.searchContext, {'governorate': 'إب', 'governorate_code': 'IBB'});
    expect(manual.manual, isTrue);
    expect(manual.device, isFalse);
    final legacy = AssistedSearchSuggestions.forLocation(
      const HomeLocation(governorate: 'ذمار', manual: true),
      regions: _regions,
    );
    expect(legacy.governorate, 'ذمار');
  });

  test('capital and Sanaa governorate use registry codes instead of stale names', () {
    for (final code in ['AMANAT_AL_ASIMAH', 'SANAA', 'DHAMAR']) {
      final suggestions = AssistedSearchSuggestions.forLocation(
        HomeLocation(governorate: 'صنعاء', governorateCode: code, manual: true),
        regions: _regions,
      );
      expect(suggestions.governorate, _governorates[code]);
    }
  });

  test('unknown and unconfirmed fixes never infer a city from labels or coordinates', () {
    for (final location in const [
      HomeLocation(),
      HomeLocation(latitude: 14.55, longitude: 44.4, device: true, label: 'ذمار'),
      HomeLocation(device: true, governorateCode: 'UNKNOWN', label: 'صنعاء'),
      HomeLocation(device: true, governorate: 'صنعاء', governorateCode: 'UNKNOWN'),
      HomeLocation(device: true, governorate: 'غير معروفة', governorateCode: 'UNKNOWN'),
      HomeLocation(device: true, governorate: 'ذمار', governorateCode: 'DHAMAR',
        needsConfirmation: true),
    ]) {
      final suggestions = AssistedSearchSuggestions.forLocation(location, regions: _regions);
      expect(suggestions.governorate, isNull);
      expect(suggestions.hint, 'شقة للإيجار، ثلاث غرف…');
      expect(suggestions.examples, ['شقة للإيجار', 'منزل للبيع', 'أرض']);
    }
  });

  test('already confirmed names work while the registry loads, code-only waits', () {
    final named = AssistedSearchSuggestions.forLocation(
      const HomeLocation(governorate: 'ذمار', governorateCode: 'DHAMAR', device: true),
    );
    expect(named.governorate, 'ذمار');
    final codeOnly = AssistedSearchSuggestions.forLocation(
      const HomeLocation(governorateCode: 'DHAMAR', device: true),
    );
    expect(codeOnly.governorate, isNull);
    final remembered = AssistedSearchSuggestions.forLocation(
      const HomeLocation(governorate: 'ذمار', governorateCode: 'DHAMAR'),
      regions: _regions,
    );
    expect(remembered.governorate, 'ذمار');
  });

  test('example lists are immutable for both generic and confirmed locations', () {
    for (final location in const [
      HomeLocation(),
      HomeLocation(governorate: 'ذمار', governorateCode: 'DHAMAR', manual: true),
    ]) {
      final examples = AssistedSearchSuggestions.forLocation(location, regions: _regions).examples;
      expect(() => examples.add('طلب آخر'), throwsUnsupportedError);
      expect(() => examples[0] = 'طلب آخر', throwsUnsupportedError);
    }
  });
}

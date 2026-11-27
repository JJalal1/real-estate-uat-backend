import 'smart_search_filters.dart';

/// Public ADM1 identifiers used by /marketplace/locations and the spatial
/// listings filter. Keep the capital distinct from the surrounding province.
const _governorateCodes = {
  'أمانة العاصمة': 'AMANAT_AL_ASIMAH', 'صنعاء': 'SANAA', 'عدن': 'ADEN',
  'تعز': 'TAIZ', 'الحديدة': 'HODEIDAH', 'إب': 'IBB', 'ذمار': 'DHAMAR',
  'حضرموت': 'HADRAMOUT', 'حجة': 'HAJJAH', 'صعدة': 'SAADAH', 'عمران': 'AMRAN',
  'الجوف': 'AL_JAWF', 'مأرب': 'MARIB', 'المحويت': 'AL_MAHWIT', 'ريمة': 'RAYMAH',
  'شبوة': 'SHABWAH', 'لحج': 'LAHJ', 'أبين': 'ABYAN', 'الضالع': 'AL_DALEA',
  'البيضاء': 'AL_BAYDA', 'المهرة': 'AL_MAHRAH', 'أرخبيل سقطرى': 'SOCOTRA',
};

String _normalize(String text) => text.trim().replaceAll(RegExp('[ـً-ٰٟ]'), '')
    .replaceAll(RegExp('[أإآٱ]'), 'ا').replaceAll('ى', 'ي').replaceAll('ة', 'ه')
    .replaceAll(RegExp(r'\s+'), ' ');

final _namesByCode = {for (final entry in _governorateCodes.entries) entry.value: entry.key};
final _names = {
  for (final name in _governorateCodes.keys) _normalize(name): name,
  'صنعا': 'صنعاء', 'ذماء': 'ذمار', 'سقطري': 'أرخبيل سقطرى',
};
final _alternatives = _names.keys.map(RegExp.escape).join('|');
final _onlyProvince = RegExp('^(?:(?:محافظه|مدينه) *)?($_alternatives)[.!،,؟]*\$');
final _placeClause = RegExp('(?:^|\\s)(?:(?:في|داخل|الي|بمحافظه) +(?:(?:محافظه|مدينه) +)?|محافظه +)'
    '($_alternatives)(?=\$|[ .،,؟!])');
final _negatedPlace = RegExp(r'(?:^| )(?:و?(?:باستثناء|استبعد|الا|ليس|ليست|مو|مش|الغ|الغي|الغاء|احذف|ازل|شيل|خارج)|لا (?:اريد|ابحث))(?: +[^ ،,.!?]+){0,4}$');
final _alternativeProvince = RegExp('^[ ،,]*(?:او|ام) +(?:(?:في|محافظه|مدينه) +)*($_alternatives)(?=\$|[ .،,؟!])');
final _typeNames = {for (final e in SmartSearchFilters.types.entries) _normalize(e.value): e.key, 'بيت': 'house'};
final _listingRequest = RegExp('^(?:(?:ابحث (?:لي )?عن|اريد|اشتي|ابغي) )?'
    '(${[..._typeNames.keys, 'عقار', 'عقارات'].map(RegExp.escape).join('|')})'
    '(?: (للبيع|للايجار|للشراء|للتاجير))?[.!،,؟]*\$');

class GovernorateSearch {
  const GovernorateSearch._(this.name, this.remainder);
  final String name;
  final String remainder;
  String get code => _governorateCodes[name]!;
  Map<String, dynamic> get filters => {'governorate': name, 'governorate_code': code};

  static String? nameForCode(String? code) => _namesByCode[code?.trim().toUpperCase()];

  static String? canonical(String? value) {
    if (value == null) return null;
    final match = _onlyProvince.firstMatch(_normalize(value));
    return match == null ? null : _names[match[1]];
  }

  void applyTo(Map<String, dynamic> values) {
    // Former releases inherited a GPS circle of 30 km. An explicitly named
    // province replaces that implicit circle. User-applied map bounds are
    // evaluated against the province when the search is submitted.
    if (num.tryParse(values['radius_km'].toString()) == 30 &&
        values.containsKey('latitude') && values.containsKey('longitude')) {
      values.remove('latitude');
      values.remove('longitude');
      values.remove('radius_km');
    }
    values.addAll(filters);
  }

  static GovernorateSearch? inRequest(String message) {
    final text = _normalize(message);
    final exact = canonical(text);
    if (exact != null) return GovernorateSearch._(exact, '');
    final matches = _placeClause.allMatches(text).where((match) =>
        !_negatedPlace.hasMatch(text.substring(0, match.start).trim())).toList();
    if (matches.length != 1) return null;
    final match = matches.single;
    if (_alternativeProvince.hasMatch(text.substring(match.end))) return null;
    final rest = text.replaceRange(match.start, match.end, ' ').trim()
        .replaceAll(RegExp(r'^[،,. ]+|[،,. ]+$'), '').trim();
    return GovernorateSearch._(_names[match[1]]!, rest);
  }

  /// A short listing request becomes ordinary filters, without requiring AI.
  /// Other keywords (such as a neighborhood or a street) stay searchable.
  static Map<String, dynamic> listingFilters(String text, GovernorateSearch? place) {
    final rest = place?.remainder ?? text.trim();
    final request = _listingRequest.firstMatch(_normalize(rest));
    final type = _typeNames[request?[1]];
    final purpose = request?[2];
    return {
      ...?place?.filters,
      if (type != null) 'type': type,
      if (purpose != null) 'purpose': purpose == 'للبيع' || purpose == 'للشراء' ? 'sale' : 'rent',
      if (request == null && rest.isNotEmpty) 'search': rest,
    };
  }
}

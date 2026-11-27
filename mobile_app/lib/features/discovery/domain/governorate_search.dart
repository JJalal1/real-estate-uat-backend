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

final _names = {
  for (final name in _governorateCodes.keys) _normalize(name): name,
  'صنعا': 'صنعاء', 'ذماء': 'ذمار', 'سقطري': 'أرخبيل سقطرى',
};
final _alternatives = _names.keys.map(RegExp.escape).join('|');
final _onlyProvince = RegExp('^(?:(?:محافظه|مدينه) *)?($_alternatives)[.!،,؟]*\$');
final _placeClause = RegExp('(?:^|\\s)(?:(?:في|داخل|الي|بمحافظه) +(?:(?:محافظه|مدينه) +)?|محافظه +)'
    '($_alternatives)(?=\$|[ .،,؟!])');
final _ambiguous = RegExp(r'(?:^| )(?:او|ام|باستثناء|استبعد|الا|ليس|ليست|مو|مش|لا اريد)(?: |$)');
final _typeNames = {for (final e in SmartSearchFilters.types.entries) _normalize(e.value): e.key, 'بيت': 'house'};
final _listingRequest = RegExp('^(?:(?:ابحث (?:لي )?عن|اريد|اشتي|ابغي) )?'
    '(${[..._typeNames.keys, 'عقار', 'عقارات'].map(RegExp.escape).join('|')})'
    '(?: (للبيع|للايجار|للشراء|للتاجير))?[.!،,؟]*\$');

class GovernorateSearch {
  const GovernorateSearch._(this.name, this.remainder);
  final String name;
  final String remainder;
  Map<String, dynamic> get filters => {'governorate': name, 'governorate_code': _governorateCodes[name]!};

  static String? canonical(String? value) {
    if (value == null) return null;
    final match = _onlyProvince.firstMatch(_normalize(value));
    return match == null ? null : _names[match[1]];
  }

  static GovernorateSearch? interpreted(String keyword, String message) {
    final requested = canonical(keyword);
    if (requested == null) return null;
    final words = _normalize(message).split(RegExp(r'[ ،,.!؟]+'));
    final tokens = words.join(' ');
    for (final e in _names.entries.where((e) => e.value == requested)) {
      if (' $tokens '.contains(' ${e.key} ')) return GovernorateSearch._(requested, '');
    }
    return null;
  }

  static GovernorateSearch? inRequest(String message) {
    final text = _normalize(message);
    final exact = canonical(text);
    if (exact != null) return GovernorateSearch._(exact, '');
    if (_ambiguous.hasMatch(text)) return null;
    final matches = _placeClause.allMatches(text).toList();
    if (matches.length != 1) return null;
    final match = matches.single;
    final rest = text.replaceRange(match.start, match.end, ' ').trim()
        .replaceAll(RegExp(r'^[،,. ]+|[،,. ]+$'), '').trim();
    return GovernorateSearch._(_names[match[1]]!, rest);
  }

  /// A short listing request becomes ordinary filters, without requiring AI.
  /// Other keywords (such as a neighborhood or a street) stay searchable.
  static Map<String, dynamic> listingFilters(String text) {
    final place = inRequest(text);
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

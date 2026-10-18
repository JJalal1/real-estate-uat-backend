/// A deliberately limited first interpreter. It proposes editable API filters;
/// it never invents listings, calls a provider, or claims to understand a brief.
class AssistedPropertySearch {
  const AssistedPropertySearch({this.type, this.purpose, this.place, this.minBedrooms, this.maxPrice});
  final String? type, purpose, place;
  final int? minBedrooms;
  final double? maxPrice;
  bool get isEmpty => type == null && purpose == null && place == null && minBedrooms == null && maxPrice == null;

  Map<String, dynamic> get apiFilters => {
    if (type != null) 'type': type,
    if (purpose != null) 'purpose': purpose,
    if (place != null && place!.trim().isNotEmpty) 'search': place!.trim(),
    if (minBedrooms != null) 'min_bedrooms': minBedrooms,
    if (maxPrice != null) ...{
      (purpose == 'rent' ? 'max_monthly_rent' : 'max_price'): maxPrice,
      'currency': 'YER',
    },
  };

  AssistedPropertySearch without(String field) => AssistedPropertySearch(
    type: field == 'type' ? null : type, purpose: field == 'purpose' ? null : purpose,
    place: field == 'place' ? null : place, minBedrooms: field == 'rooms' ? null : minBedrooms,
    maxPrice: field == 'price' ? null : maxPrice);

  static AssistedPropertySearch parse(String source) {
    var text = source.trim();
    const digits = '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹';
    for (var i = 0; i < digits.length; i++) { text = text.replaceAll(digits[i], '${i % 10}'); }
    text = text.replaceAll('٬', ',');
    final originalPlaceText = text;
    text = text.replaceAll(RegExp('[أإآ]'), 'ا').replaceAll('ة', 'ه')
      .replaceAll(RegExp(r'[\u064B-\u065F\u0640]'), '');
    text = text.replaceAllMapped(RegExp(r'(\d)[,،](\d{3})(?=\D|$)'), (m) => '${m[1]}${m[2]}');
    String? type;
    const names = {'شقه': 'apartment', 'شقق': 'apartment', 'دور كامل': 'floor',
      'عماره': 'building', 'مبنى كامل': 'building', 'فيلا': 'villa', 'منزل': 'house',
      'بيت': 'house', 'ارض': 'land', 'محل': 'shop', 'مكتب': 'office', 'مزرعه': 'farm'};
    final types = names.entries.where((e) => text.contains(e.key)).map((e) => e.value).toSet();
    if (types.length == 1) type = types.single;
    final rent = text.contains('ايجار') || text.contains('استاجر');
    final sale = text.contains('بيع') || text.contains('شراء') || text.contains('اشتري');
    final purpose = rent == sale ? null : rent ? 'rent' : 'sale';
    final rooms = RegExp(r'(\d{1,2})\s*غرف(?:ه|\s+نوم)?').firstMatch(text);
    final count = int.tryParse(rooms?[1] ?? '');
    final budget = RegExp(r'(?:اقل(?:\s+من)?|حتى|بحد\s+اقصى|لا\s+يتجاوز)\s*(\d+(?:\.\d+)?)\s*(الف|مليون)?').firstMatch(text);
    final number = double.tryParse(budget?[1] ?? '');
    final multiplier = budget?[2] == 'مليون' ? 1000000 : budget?[2] == 'الف' ? 1000 : 1;
    final location = RegExp(r'(?:^|\s)(?:في|بمنطقة|بمحافظة)\s+(.+?)(?=\s*(?:[،,]|\d+\s*غرف|أقل|اقل|حتى|بحد|لا\s+يتجاوز|$))').firstMatch(originalPlaceText)?[1]?.trim();
    return AssistedPropertySearch(type: type, purpose: purpose,
      place: location == null || location.isEmpty || location.length > 120 ? null : location,
      minBedrooms: count != null && count > 0 && count <= 50 ? count : null,
      maxPrice: number != null && number > 0 && number.isFinite ? number * multiplier : null);
  }
}

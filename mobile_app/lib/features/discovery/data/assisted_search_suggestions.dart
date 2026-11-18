import 'marketplace_repository.dart';

/// Display-only examples. Reading them never starts location access or changes
/// the user's draft, applied criteria, or manually selected governorate.
class AssistedSearchSuggestions {
  const AssistedSearchSuggestions._({
    required this.governorate,
    required this.hint,
    required this.examples,
  });

  final String? governorate;
  final String hint;
  final List<String> examples;

  static const _generic = AssistedSearchSuggestions._(
    governorate: null,
    hint: 'شقة للإيجار، ثلاث غرف…',
    examples: ['شقة للإيجار', 'منزل للبيع', 'أرض'],
  );

  factory AssistedSearchSuggestions.forLocation(
    HomeLocation location, {
    Iterable<HomeLocation> regions = const [],
  }) {
    final governorate = _confirmedGovernorate(location, regions);
    if (governorate == null) return _generic;
    return AssistedSearchSuggestions._(
      governorate: governorate,
      hint: 'شقة للإيجار في $governorate، ثلاث غرف…',
      examples: List.unmodifiable([
        'شقة للإيجار في $governorate',
        'منزل للبيع',
        'أرض في $governorate',
      ]),
    );
  }

  static String? _confirmedGovernorate(
    HomeLocation location,
    Iterable<HomeLocation> regions,
  ) {
    if (location.needsConfirmation) return null;
    final context = location.searchContext;
    final code = _text(context['governorate_code']);
    final name = _text(context['governorate']);
    if (code == null && name == null) return null;

    // Registry identity wins over a stale/decorated display label. This also
    // keeps Sana'a governorate distinct from Amanat Al Asimah and supports all
    // public governorates without duplicating a fixed city list here.
    for (final region in regions) {
      if (code != null && _text(region.governorateCode) == code &&
          !region.needsConfirmation && _text(region.governorate) != null) {
        return _text(region.governorate);
      }
    }
    if (code != null && regions.isNotEmpty) return null;
    for (final region in regions) {
      if (name != null && _text(region.governorate) == name &&
          !region.needsConfirmation) {
        return name;
      }
    }
    // While the public registry loads, an already confirmed server/manual name
    // can be used. The default label and GPS coordinates are never a fallback.
    return regions.isEmpty ? name : null;
  }

  static String? _text(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }
}

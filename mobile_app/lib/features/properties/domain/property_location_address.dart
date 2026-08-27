class PropertyLocationAddress {
  const PropertyLocationAddress({
    this.governorate,
    this.district,
    this.street,
    this.formattedAddress,
  });

  final String? governorate;
  final String? district;
  final String? street;
  final String? formattedAddress;

  bool get isEmpty =>
      _clean(governorate) == null &&
      _clean(district) == null &&
      _clean(street) == null;

  bool get isComplete =>
      _clean(governorate) != null &&
      _clean(district) != null &&
      _clean(street) != null;

  int get resolvedFieldCount => [governorate, district, street]
      .where((value) => _clean(value) != null)
      .length;

  String get combined {
    final parts = <String>[];
    final governorateValue = _clean(governorate);
    final districtValue = _clean(district);
    final streetValue = _clean(street);
    if (governorateValue != null) parts.add(governorateValue);
    if (districtValue != null) parts.add(districtValue);
    if (streetValue != null) parts.add(streetValue);
    return parts.join(' - ');
  }

  PropertyLocationAddress mergeFallback(PropertyLocationAddress fallback) {
    return PropertyLocationAddress(
      governorate: _clean(governorate) ?? _clean(fallback.governorate),
      district: _clean(district) ?? _clean(fallback.district),
      street: _clean(street) ?? _clean(fallback.street),
      formattedAddress:
          _clean(formattedAddress) ?? _clean(fallback.formattedAddress),
    );
  }

  static PropertyLocationAddress fromStoredAddress(String? value) {
    final text = _clean(value);
    if (text == null) return const PropertyLocationAddress();
    final parts = text
        .split(RegExp(r'\s+-\s+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return const PropertyLocationAddress();
    return PropertyLocationAddress(
      governorate: parts[0],
      district: parts.length > 1 ? parts[1] : null,
      street: parts.length > 2 ? parts.sublist(2).join(' - ') : null,
      formattedAddress: text,
    );
  }
}

String? _clean(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? null : text;
}

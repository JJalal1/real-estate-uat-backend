class PropertyMarker {
  const PropertyMarker({
    required this.id,
    required this.title,
    required this.price,
    required this.currency,
    required this.latitude,
    required this.longitude,
    required this.distanceKm,
    this.basePrice,
    this.priceDisplayMode,
    this.priceDisplayNote,
    this.monthlyRent,
    this.rentalTermMonths,
    this.advanceMonths,
    this.purpose,
    this.type,
    this.areaM2,
    this.bedrooms,
    this.bathrooms,
    this.address,
    this.mainImage,
  });

  final int id;
  final String title;
  /// User-facing amount. Financial V1 prefers display_price when present.
  final double price;
  final double? basePrice;
  final String? priceDisplayMode;
  final String? priceDisplayNote;
  final double? monthlyRent;
  final int? rentalTermMonths;
  final int? advanceMonths;
  final String currency;
  final double latitude;
  final double longitude;
  final double distanceKm;
  final String? purpose;
  final String? type;
  final int? areaM2;
  final int? bedrooms;
  final int? bathrooms;
  final String? address;
  final String? mainImage;

  factory PropertyMarker.fromJson(Map<String, dynamic> json) {
    final rawPrice = _asDouble(json['price']) ?? 0;
    return PropertyMarker(
      id: _asInt(json['id']) ?? 0,
      title: json['title']?.toString() ?? '',
      price: _asDouble(json['display_price']) ?? rawPrice,
      basePrice: _asDouble(json['base_price']) ?? rawPrice,
      priceDisplayMode: _nullableString(json['price_display_mode']),
      priceDisplayNote: _nullableString(json['price_display_note']),
      monthlyRent: _asDouble(json['monthly_rent']),
      rentalTermMonths: _asInt(json['rental_term_months']),
      advanceMonths: _asInt(json['advance_months']),
      currency: json['currency']?.toString() ?? 'YER',
      latitude: _asDouble(json['latitude']) ?? 0,
      longitude: _asDouble(json['longitude']) ?? 0,
      distanceKm: _asDouble(json['distance_km']) ?? 0,
      purpose: _nullableString(json['purpose']),
      type: _nullableString(json['type']),
      areaM2: _asInt(json['area_m2']),
      bedrooms: _asInt(json['bedrooms']),
      bathrooms: _asInt(json['bathrooms']),
      address: _nullableString(json['address']),
      mainImage: _nullableString(json['main_image']),
    );
  }
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

double? _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

String? _nullableString(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  return text;
}

class PropertyMarker {
  const PropertyMarker({
    required this.id,
    required this.title,
    required this.price,
    required this.currency,
    required this.latitude,
    required this.longitude,
    required this.distanceKm,
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
  final double price;
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
    return PropertyMarker(
      id: _asInt(json['id']) ?? 0,
      title: json['title']?.toString() ?? '',
      price: _asDouble(json['price']) ?? 0,
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

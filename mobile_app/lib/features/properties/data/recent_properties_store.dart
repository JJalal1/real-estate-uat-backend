import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/property_details.dart';

final recentPropertiesStoreProvider = Provider<RecentPropertiesStore>((ref) {
  return RecentPropertiesStore();
});

final recentPropertiesProvider = FutureProvider<List<PropertySummary>>((ref) {
  return ref.watch(recentPropertiesStoreProvider).load();
});

class RecentPropertiesStore {
  static const int _limit = 30;
  Future<File>? _fileFuture;

  Future<File> _file() {
    return _fileFuture ??= getApplicationSupportDirectory().then(
      (dir) => File('${dir.path}/aqer_recent_properties.json'),
    );
  }

  Future<List<PropertySummary>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const [];
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((row) => PropertySummary.fromJson(Map<String, dynamic>.from(row)))
          .where((item) => item.id > 0)
          .take(_limit)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> record(PropertySummary property) async {
    if (property.id <= 0 || property.status != 'published') return;
    final current = await load();
    final next = <PropertySummary>[
      property,
      ...current.where((item) => item.id != property.id),
    ].take(_limit).toList(growable: false);
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(next.map(_toJson).toList(growable: false)),
      flush: true,
    );
  }

  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }

  Map<String, dynamic> _toJson(PropertySummary p) => {
        'id': p.id,
        'title': p.title,
        'purpose': p.purpose,
        'type': p.type,
        if (p.tenureType != null) 'tenure_type': p.tenureType,
        'price': p.price,
        if (p.basePrice != null) 'base_price': p.basePrice,
        if (p.monthlyRent != null) 'monthly_rent': p.monthlyRent,
        if (p.advanceMonths != null) 'advance_months': p.advanceMonths,
        'currency': p.currency,
        'latitude': p.latitude,
        'longitude': p.longitude,
        if (p.areaM2 != null) 'area_m2': p.areaM2,
        if (p.areaValue != null) 'area_value': p.areaValue,
        if (p.areaUnit != null) 'area_unit': p.areaUnit,
        if (p.bedrooms != null) 'bedrooms': p.bedrooms,
        if (p.bathrooms != null) 'bathrooms': p.bathrooms,
        if (p.hasParking != null) 'has_parking': p.hasParking,
        if (p.floorsCount != null) 'floors_count': p.floorsCount,
        if (p.unitsPerFloor.isNotEmpty) 'units_per_floor': p.unitsPerFloor,
        if (p.shopOpenings != null) 'shop_openings': p.shopOpenings,
        if (p.buildingFacade != null) 'building_facade': p.buildingFacade,
        if (p.address != null) 'address': p.address,
        'status': p.status,
        if (p.mainImage != null) 'main_image': p.mainImage,
        'image_urls': p.imageUrls,
        'is_spotlight': p.isSpotlight,
        if (p.floorNumber != null) 'floor_number': p.floorNumber,
      };
}

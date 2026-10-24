import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/property_details.dart';
import '../../account/data/auth_controller.dart';

final recentHistoryDirectoryProvider = Provider<Future<Directory> Function()>((ref) => getApplicationSupportDirectory);

final recentPropertiesStoreProvider = Provider<RecentPropertiesStore>((ref) {
  final scope = ref.watch(authControllerProvider.select((state) =>
    (state.asData?.value?.id, !state.isLoading && !state.hasError)));
  return RecentPropertiesStore(actorId: scope.$1, enabled: scope.$2,
    supportDirectory: ref.watch(recentHistoryDirectoryProvider));
});

final recentPropertiesProvider = FutureProvider<List<PropertySummary>>((ref) {
  return ref.watch(recentPropertiesStoreProvider).load();
});

class RecentPropertiesStore {
  RecentPropertiesStore({int? actorId, this.enabled = true, Future<Directory> Function()? supportDirectory})
    : _scope = actorId != null && actorId > 0 ? 'user_$actorId' : 'guest',
      _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;
  final bool enabled;
  final String _scope;
  final Future<Directory> Function() _supportDirectory;
  static const int _limit = 30;
  Future<File>? _fileFuture;
  Future<void> _pending = Future<void>.value();

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return result;
  }

  Future<File> _file() {
    // Legacy device-wide history has no reliable owner; never assign it to a new account.
    return _fileFuture ??= _supportDirectory().then(
      (dir) => File('${dir.path}/aqer_recent_properties_$_scope.json'),
    );
  }

  Future<List<PropertySummary>> load() => enabled ? _serialize(_read) : Future.value(const []);

  Future<List<PropertySummary>> _read() async {
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

  Future<void> record(PropertySummary property) {
    if (!enabled || property.id <= 0 || property.status != 'published') return Future.value();
    return _serialize(() async {
    final current = await _read();
    final next = <PropertySummary>[
      property,
      ...current.where((item) => item.id != property.id),
    ].take(_limit).toList(growable: false);
    final file = await _file();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode(next.map(_toJson).toList(growable: false)),
      flush: true,
    );
    try { await temporary.rename(file.path); }
    catch (_) {
      try { if (await temporary.exists()) await temporary.delete(); } catch (_) { /* Preserve the write failure. */ }
      rethrow;
    }
    });
  }

  Future<void> clear() => !enabled ? Future.value() : _serialize(() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  });

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

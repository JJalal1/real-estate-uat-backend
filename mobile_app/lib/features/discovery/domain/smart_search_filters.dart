import '../../properties/domain/property_schema.dart';
class SmartSearchFilters {
  const SmartSearchFilters([this.values = const {}]);
  final Map<String, dynamic> values;

  static const mapFields = {'area_polygon', 'latitude', 'longitude', 'radius_km', 'south', 'west', 'north', 'east'};
  static const fields = {'governorate', 'advertiser_id', 'spotlight', 'type', 'purpose', 'search', 'currency', 'min_price', 'max_price', 'min_area_m2', 'max_area_m2',
    'min_bedrooms', 'min_bathrooms', 'floor_number', 'has_parking', 'has_elevator', 'building_facade', 'unit_occupies_entire_floor'};
  static const types = {'apartment': 'شقة', 'house': 'منزل', 'villa': 'فيلا', 'building': 'عمارة', 'land': 'أرض', 'farm': 'مزرعة', 'shop': 'محل', 'office': 'مكتب'};
  static const facades = {'north': 'شمالية', 'south': 'جنوبية', 'east': 'شرقية', 'west': 'غربية', 'northeast': 'شمالية شرقية',
    'northwest': 'شمالية غربية', 'southeast': 'جنوبية شرقية', 'southwest': 'جنوبية غربية', 'multiple': 'متعددة'};
  static const labels = {'type': 'نوع العقار', 'purpose': 'الغرض', 'search': 'الموقع', 'budget': 'الميزانية', 'currency': 'العملة',
    'min_bedrooms': 'غرف النوم', 'min_bathrooms': 'دورات المياه', 'min_area_m2': 'أقل مساحة', 'max_area_m2': 'أقصى مساحة',
    'floor_number': 'الدور', 'has_parking': 'موقف', 'has_elevator': 'مصعد', 'building_facade': 'الواجهة', 'unit_occupies_entire_floor': 'دور كامل'};

  factory SmartSearchFilters.fromMap(Map<String, dynamic> source) {
    final next = <String, dynamic>{};
    for (final entry in source.entries) {
      if ((!fields.contains(entry.key) && !mapFields.contains(entry.key)) || entry.value == null || entry.value == '') continue;
      if (entry.value is! String && entry.value is! num && entry.value is! bool) continue;
      next[entry.key] = entry.value;
      if (const ['has_parking', 'has_elevator', 'unit_occupies_entire_floor', 'spotlight'].contains(entry.key)) {
        if (entry.value == 0 || entry.value == 1) { next[entry.key] = entry.value == 1; }
        else if (entry.value is! bool) { next.remove(entry.key); }
      }
    }
    if (next['type'] == 'floor') { next['type'] = 'apartment'; next['unit_occupies_entire_floor'] = true; }
    return SmartSearchFilters(Map.unmodifiable(DynamicPropertySchema.filters(next)));
  }

  factory SmartSearchFilters.fromApiFilters(Map<String, dynamic> source) {
    final values = Map<String, dynamic>.from(source);
    if (values['purpose'] == 'rent') {
      if (values.containsKey('min_monthly_rent')) values['min_price'] = values.remove('min_monthly_rent');
      if (values.containsKey('max_monthly_rent')) values['max_price'] = values.remove('max_monthly_rent');
    }
    return SmartSearchFilters.fromMap(values);
  }

  bool get hasMapArea => mapFields.any(values.containsKey);

  SmartSearchFilters without(String key) {
    final next = Map<String, dynamic>.from(values);
    if (key == 'budget') { next.remove('min_price'); next.remove('max_price'); }
    else if (key == 'map_area') { for (final field in mapFields) { next.remove(field); } }
    else { next.remove(key); }
    return SmartSearchFilters.fromMap(next);
  }

  Map<String, dynamic> get apiFilters {
    final query = <String, dynamic>{};
    for (final entry in values.entries) {
      final key = values['purpose'] == 'rent' && const ['min_price', 'max_price'].contains(entry.key)
        ? entry.key == 'min_price' ? 'min_monthly_rent' : 'max_monthly_rent' : entry.key;
      query[key] = entry.value is bool ? entry.value == true ? 1 : 0 : entry.value;
    }
    if ((values.containsKey('min_price') || values.containsKey('max_price')) && !values.containsKey('currency')) query['currency'] = 'YER';
    return query;
  }

  List<String> get suggestions {
    final keys = switch (values['type']) {
      'apartment' => ['min_bedrooms', 'floor_number', 'has_elevator', 'has_parking'],
      'house' || 'villa' => ['min_bedrooms', 'min_area_m2', 'has_parking'],
      'land' => ['min_area_m2', 'building_facade', 'max_area_m2', 'search'],
      'farm' => ['min_area_m2', 'max_area_m2', 'search'],
      'office' || 'shop' => ['min_area_m2', 'floor_number', 'building_facade'],
      _ => ['type', 'purpose', 'search', 'budget'],
    };
    final allowed = DynamicPropertySchema.filters({...values, for (final key in keys) key: values[key] ?? true});
    return keys.where((key) => allowed.containsKey(key) && (key == 'budget' ? !values.containsKey('min_price') && !values.containsKey('max_price') : !values.containsKey(key))).toList();
  }

  String _number(dynamic value) => value is num ? value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1) : value.toString();
  String get currencyLabel => switch (values['currency']) { 'USD' => 'دولار', 'SAR' => 'ريال سعودي', _ => 'ريال' };

  List<(String, String)> get chips {
    final result = <(String, String)>[];
    for (final entry in values.entries) {
      final key = entry.key, value = entry.value;
      if (const ['min_price', 'max_price'].contains(key) || mapFields.contains(key)) continue;
      final text = switch (key) {
        'governorate' => 'المحافظة: $value',
        'advertiser_id' => 'إعلانات معلن محدد',
        'spotlight' => value == true || value == 1 ? 'العقارات المميزة' : 'بدون اشتراط التمييز',
        'type' => types[value] ?? value.toString(),
        'purpose' => value == 'rent' ? 'للإيجار' : 'للبيع',
        'search' => value.toString(),
        'currency' => currencyLabel,
        'min_bedrooms' => '${_number(value)} غرف فأكثر',
        'min_bathrooms' => '${_number(value)} دورات مياه فأكثر',
        'min_area_m2' => 'من ${_number(value)} م²',
        'max_area_m2' => 'حتى ${_number(value)} م²',
        'floor_number' => 'الدور $value',
        'has_parking' => value == true || value == 1 ? 'يوجد موقف' : 'بدون موقف',
        'has_elevator' => value == true || value == 1 ? 'يوجد مصعد' : 'بدون مصعد',
        'building_facade' => 'واجهة ${facades[value] ?? value}',
        'unit_occupies_entire_floor' => value == true || value == 1 ? 'دور كامل' : 'وحدة ضمن الدور',
        _ => value.toString(),
      };
      result.add((key, text));
    }
    if (hasMapArea) result.add(('map_area', 'نطاق محدد على الخريطة'));
    final low = values['min_price'], high = values['max_price'];
    if (low != null || high != null) {
      final range = low != null && high != null ? '${_number(low)}–${_number(high)}' : low != null ? 'من ${_number(low)}' : 'حتى ${_number(high)}';
      result.add(('budget', '$range $currencyLabel${values['purpose'] == 'rent' ? ' شهريًا' : ''}'));
    }
    return result;
  }
}

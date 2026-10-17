import 'property_schema_definition.g.dart';

abstract final class DynamicPropertySchema {
  static Map<String, dynamic> get fields => propertySchemaDefinition['fields'] as Map<String, dynamic>;
  static bool _matches(Map<dynamic, dynamic> condition, Map<String, dynamic> facts) => condition.entries.every((e) =>
    (e.key == 'type' && facts[e.key] == 'floor' ? 'apartment' : facts[e.key]) == e.value);

  static bool applies(String key, Map<String, dynamic> facts) {
    var field = fields[key] as Map<String, dynamic>?;
    if(field==null) { for(final candidate in fields.values) { if(((candidate as Map)['aliases'] as List? ?? const []).contains(key)) { field=Map<String,dynamic>.from(candidate);break; } } }
    if (field == null) return true;
    final type = facts['type'] == 'floor' ? 'apartment' : facts['type'], purpose = facts['purpose'];
    if (type != null && field['types'] is List && !(field['types'] as List).contains(type)) return false;
    if (purpose != null && field['purposes'] is List && !(field['purposes'] as List).contains(purpose)) return false;
    return !(field['exclude'] as List? ?? const []).any((c) => _matches(c as Map, facts));
  }

  static Set<String> required(Map<String, dynamic> facts) => {
    for (final entry in fields.entries)
      if (applies(entry.key, facts) && ((entry.value as Map)['required'] == true ||
        ((entry.value as Map)['required_cases'] as List? ?? const []).any((c) => _matches(c as Map, facts)))) entry.key,
  };

  static Map<String, dynamic> sanitize(Map<String, dynamic> input) {
    final result = Map<String, dynamic>.from(input);
    if (result['type'] == 'shop' && result['area_value'] is num) {
      final factor = (propertySchemaDefinition['area_units_to_sqm'] as Map)[result['area_unit'] ?? 'sqm'] as num? ?? 1;
      result['area_value'] = (result['area_value'] as num) * factor;
      result['area_m2'] = (result['area_value'] as num).round(); result['area_unit'] = 'sqm';
    }
    for (final entry in fields.entries) {
      if (applies(entry.key, result)) continue;
      for (final key in [entry.key, ...((entry.value as Map)['aliases'] as List? ?? const [])]) { result.remove(key); }
    }
    return result;
  }

  static Map<String, dynamic> filters(Map<String, dynamic> input) {
    final result = Map<String, dynamic>.from(input);
    for (final entry in fields.entries) {
      if (applies(entry.key, input)) continue;
      for (final key in (entry.value as Map)['filters'] as List? ?? const []) { result.remove(key); }
    }
    return result;
  }

  static Map<String, String> get floorOptions => {
    for (final row in propertySchemaDefinition['floors'] as List) (row as Map)['value'] as String: row['label'] as String,
  };
  static String floorLabel(String? value) => floorOptions[value] ?? value ?? '';
}

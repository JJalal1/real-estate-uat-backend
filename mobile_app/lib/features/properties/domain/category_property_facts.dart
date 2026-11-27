const landUseOptions = {
  'residential': 'سكنية',
  'commercial': 'تجارية',
  'agricultural': 'زراعية',
  'mixed': 'متعددة الاستخدام',
};

const farmWaterSourceOptions = {
  'well': 'بئر',
  'network': 'شبكة مياه',
  'rain': 'مياه الأمطار',
  'other': 'مصدر آخر',
};

const farmCropTypeOptions = {
  'fruit': 'فواكه',
  'vegetables': 'خضروات',
  'grains': 'حبوب',
  'mixed': 'محاصيل متنوعة',
  'other': 'محاصيل أخرى',
};

class CategoryPropertyFacts {
  const CategoryPropertyFacts({
    this.parkingSpaces,
    this.hasSeparateMajlis,
    this.hasMajlisBathroom,
    this.landUse,
    this.streetWidth,
    this.hasYard,
    this.officeRooms,
    this.farmWaterSource,
    this.farmCropType,
    this.sectionElevator,
  });

  final int? parkingSpaces, officeRooms;
  final double? streetWidth;
  final bool? hasSeparateMajlis, hasMajlisBathroom, hasYard, sectionElevator;
  final String? landUse, farmWaterSource, farmCropType;

  static const booleanKeys = {
    'has_separate_majlis',
    'has_majlis_bathroom',
    'has_yard',
    'section_elevator',
  };

  static const choiceKeys = {
    ...booleanKeys,
    'land_use',
    'farm_water_source',
    'farm_crop_type',
  };

  static const keys = {
    ...choiceKeys,
    'parking_spaces',
    'street_width_m',
    'office_rooms',
  };

  factory CategoryPropertyFacts.fromJson(Map<String, dynamic> json) {
    final separateMajlis = _optionalBool(json['has_separate_majlis']);
    return CategoryPropertyFacts(
      parkingSpaces: int.tryParse('${json['parking_spaces']}'),
      hasSeparateMajlis: separateMajlis,
      hasMajlisBathroom: separateMajlis == true
          ? _optionalBool(json['has_majlis_bathroom'])
          : null,
      landUse: _knownOption(json['land_use'], landUseOptions),
      streetWidth: double.tryParse('${json['street_width_m']}'),
      hasYard: _optionalBool(json['has_yard']),
      officeRooms: int.tryParse('${json['office_rooms']}'),
      farmWaterSource:
          _knownOption(json['farm_water_source'], farmWaterSourceOptions),
      farmCropType: _knownOption(json['farm_crop_type'], farmCropTypeOptions),
      sectionElevator: _optionalBool(json['section_elevator']),
    );
  }

  Map<String, dynamic> toMap({bool includeCleared = false}) {
    final facts = <String, dynamic>{
      'parking_spaces': parkingSpaces,
      'has_separate_majlis': hasSeparateMajlis,
      'has_majlis_bathroom':
          hasSeparateMajlis == true ? hasMajlisBathroom : null,
      'land_use': landUse,
      'street_width_m': streetWidth,
      'has_yard': hasYard,
      'office_rooms': officeRooms,
      'farm_water_source': farmWaterSource,
      'farm_crop_type': farmCropType,
      'section_elevator': sectionElevator,
    };
    if (!includeCleared) facts.removeWhere((_, value) => value == null);
    return facts;
  }

  static bool? _optionalBool(Object? value) => switch (value) {
        true || 1 || '1' || 'true' || 'yes' => true,
        false || 0 || '0' || 'false' || 'no' => false,
        _ => null,
      };

  static String? _knownOption(Object? value, Map<String, String> options) =>
      value is String && options.containsKey(value) ? value : null;
}

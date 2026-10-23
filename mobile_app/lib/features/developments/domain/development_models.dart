class DeveloperSummary {
  const DeveloperSummary(
      {required this.id,
      required this.name,
      required this.slug,
      required this.status,
      this.description,
      this.logoUrl,
      this.projectsCount = 0});
  final int id;
  final String name;
  final String slug;
  final String status;
  final String? description;
  final String? logoUrl;
  final int projectsCount;

  factory DeveloperSummary.fromJson(Map<String, dynamic> json) =>
      DeveloperSummary(
        id: _int(json['id']) ?? 0,
        name: json['name']?.toString() ?? '',
        slug: json['slug']?.toString() ?? '',
        status: json['status']?.toString() ?? 'active',
        description: _text(json['description']),
        logoUrl: _text(json['logo_url']),
        projectsCount: _int(json['projects_count']) ?? 0,
      );
}

class DevelopmentSummary {
  const DevelopmentSummary(
      {required this.id,
      required this.developerId,
      required this.name,
      required this.slug,
      required this.status,
      required this.completionStatus,
      required this.unitsCount,
      required this.availableUnitsCount,
      this.developer,
      this.description,
      this.address,
      this.coverImageUrl,
      this.expectedCompletionDate,
      this.governorateName,
      this.geoCellName});
  final int id;
  final int developerId;
  final DeveloperSummary? developer;
  final String name;
  final String slug;
  final String status;
  final String completionStatus;
  final String? description;
  final String? address;
  final String? coverImageUrl;
  final DateTime? expectedCompletionDate;
  final String? governorateName;
  final String? geoCellName;
  final int unitsCount;
  final int availableUnitsCount;

  factory DevelopmentSummary.fromJson(Map<String, dynamic> json) {
    final developerJson = json['developer'];
    return DevelopmentSummary(
      id: _int(json['id']) ?? 0,
      developerId: _int(json['developer_id']) ?? 0,
      developer: developerJson is Map<String, dynamic>
          ? DeveloperSummary.fromJson(developerJson)
          : null,
      name: json['name']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
      status: json['status']?.toString() ?? 'draft',
      completionStatus: json['completion_status']?.toString() ?? 'planned',
      description: _text(json['description']),
      address: _text(json['address']),
      coverImageUrl: _text(json['cover_image_url']),
      expectedCompletionDate:
          DateTime.tryParse(json['expected_completion_date']?.toString() ?? ''),
      governorateName: _text(json['governorate_name']),
      geoCellName: _text(json['geo_cell_name']),
      unitsCount: _int(json['units_count']) ?? 0,
      availableUnitsCount: _int(json['available_units_count']) ?? 0,
    );
  }
}

class DevelopmentUnitItem {
  const DevelopmentUnitItem(
      {required this.id,
      required this.code,
      required this.title,
      required this.unitType,
      required this.areaM2,
      required this.currency,
      required this.status,
      this.floorLabel,
      this.bedrooms,
      this.bathrooms,
      this.price,
      this.description});
  final int id;
  final String code;
  final String title;
  final String unitType;
  final String? floorLabel;
  final int? bedrooms;
  final double? bathrooms;
  final double areaM2;
  final double? price;
  final String currency;
  final String status;
  final String? description;

  factory DevelopmentUnitItem.fromJson(Map<String, dynamic> json) =>
      DevelopmentUnitItem(
        id: _int(json['id']) ?? 0,
        code: json['code']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        unitType: json['unit_type']?.toString() ?? 'other',
        floorLabel: _text(json['floor_label']),
        bedrooms: _int(json['bedrooms']),
        bathrooms: _double(json['bathrooms']),
        areaM2: _double(json['area_m2']) ?? 0,
        price: _double(json['price']),
        currency: json['currency']?.toString() ?? 'YER',
        status: json['status']?.toString() ?? 'available',
        description: _text(json['description']),
      );
}

class DevelopmentDetails {
  const DevelopmentDetails({required this.summary, required this.units});
  final DevelopmentSummary summary;
  final List<DevelopmentUnitItem> units;
  factory DevelopmentDetails.fromJson(Map<String, dynamic> json) {
    final rows = json['units'] as List<dynamic>? ?? const <dynamic>[];
    return DevelopmentDetails(
        summary: DevelopmentSummary.fromJson(json),
        units: rows
            .whereType<Map<String, dynamic>>()
            .map(DevelopmentUnitItem.fromJson)
            .toList(growable: false));
  }
}

int? _int(dynamic value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
double? _double(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');
String? _text(dynamic value) {
  final s = value?.toString().trim();
  return s == null || s.isEmpty ? null : s;
}

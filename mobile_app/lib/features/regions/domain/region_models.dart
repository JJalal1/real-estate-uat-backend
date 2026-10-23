import 'package:maplibre_gl/maplibre_gl.dart';

class GovernorateModel {
  const GovernorateModel({
    required this.id,
    required this.code,
    required this.nameAr,
    required this.nameEn,
    required this.isActive,
    required this.cellsCount,
  });

  final int id;
  final String code;
  final String nameAr;
  final String? nameEn;
  final bool isActive;
  final int cellsCount;

  factory GovernorateModel.fromJson(Map<String, dynamic> json) {
    return GovernorateModel(
      id: _int(json['id']),
      code: json['code']?.toString() ?? '',
      nameAr: json['name_ar']?.toString() ?? '',
      nameEn: _nullable(json['name_en']),
      isActive: json['is_active'] == true || json['is_active'] == 1,
      cellsCount: _int(json['cells_count']),
    );
  }
}

/// Read-only compatibility metadata for old Stage 8 clients/tests.
/// It does not restore broker ownership of a region.
class BrokerSummary {
  const BrokerSummary({
    required this.id,
    required this.name,
    this.email,
    this.phone,
  });

  final int id;
  final String name;
  final String? email;
  final String? phone;

  factory BrokerSummary.fromJson(Map<String, dynamic> json) {
    return BrokerSummary(
      id: _int(json['id']),
      name: json['name']?.toString() ?? '',
      email: _nullable(json['email']),
      phone: _nullable(json['phone']),
    );
  }
}

/// Historical assignment metadata kept only so legacy read-only models compile.
/// Admin/Support V1.3 does not expose or create broker-region assignments.
class BrokerAssignmentHistory {
  const BrokerAssignmentHistory({
    required this.id,
    required this.brokerUserId,
    required this.brokerName,
    required this.assignedByName,
    required this.startsAt,
    required this.endsAt,
    required this.reason,
    required this.endReason,
  });

  final int id;
  final int brokerUserId;
  final String? brokerName;
  final String? assignedByName;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String? reason;
  final String? endReason;

  factory BrokerAssignmentHistory.fromJson(Map<String, dynamic> json) {
    return BrokerAssignmentHistory(
      id: _int(json['id']),
      brokerUserId: _int(json['broker_user_id']),
      brokerName: _nullable(json['broker_name']),
      assignedByName: _nullable(json['assigned_by_name']),
      startsAt: _date(json['starts_at']),
      endsAt: _date(json['ends_at']),
      reason: _nullable(json['reason']),
      endReason: _nullable(json['end_reason']),
    );
  }
}

class RegionCell {
  const RegionCell({
    required this.id,
    required this.governorateId,
    required this.governorateName,
    required this.code,
    required this.nameAr,
    required this.nameEn,
    required this.isActive,
    required this.boundary,
    required this.propertiesCount,
    required this.publishedPropertiesCount,
    this.isReserved = false,
    this.activeBroker,
    this.assignmentHistory = const <BrokerAssignmentHistory>[],
  });

  final int id;
  final int governorateId;
  final String governorateName;
  final String code;
  final String nameAr;
  final String? nameEn;
  final bool isActive;
  final List<LatLng> boundary;
  final int propertiesCount;
  final int publishedPropertiesCount;

  /// Legacy read-only compatibility fields. They are ignored by the new UI.
  final bool isReserved;
  final BrokerSummary? activeBroker;
  final List<BrokerAssignmentHistory> assignmentHistory;

  factory RegionCell.fromJson(Map<String, dynamic> json) {
    final governorate = json['governorate'];
    final gov = governorate is Map<String, dynamic>
        ? governorate
        : const <String, dynamic>{};
    final active = json['active_broker'];
    return RegionCell(
      id: _int(json['id']),
      governorateId: _int(gov['id']),
      governorateName: gov['name_ar']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      nameAr: json['name_ar']?.toString() ?? '',
      nameEn: _nullable(json['name_en']),
      isActive: json['is_active'] == true || json['is_active'] == 1,
      boundary: _boundary(json['boundary']),
      propertiesCount: _int(json['properties_count']),
      publishedPropertiesCount: _int(json['published_properties_count']),
      isReserved: json['is_reserved'] == true,
      activeBroker: active is Map<String, dynamic>
          ? BrokerSummary.fromJson(active)
          : null,
      assignmentHistory: _list(
        json['assignment_history'],
        BrokerAssignmentHistory.fromJson,
      ),
    );
  }

  static List<LatLng> _boundary(dynamic value) {
    if (value is! Map<String, dynamic>) {
      return const <LatLng>[];
    }
    final coordinates = value['coordinates'];
    if (coordinates is! List ||
        coordinates.isEmpty ||
        coordinates.first is! List) {
      return const <LatLng>[];
    }
    final ring = coordinates.first as List;
    final points = <LatLng>[];
    for (final item in ring) {
      if (item is List && item.length >= 2) {
        points.add(LatLng(_double(item[1]), _double(item[0])));
      }
    }
    if (points.length > 1 && _same(points.first, points.last)) {
      points.removeLast();
    }
    return points;
  }

  static bool _same(LatLng first, LatLng second) {
    return (first.latitude - second.latitude).abs() < 0.0000001 &&
        (first.longitude - second.longitude).abs() < 0.0000001;
  }
}

class RegionProperty {
  const RegionProperty({
    required this.id,
    required this.title,
    required this.status,
    required this.reviewStatus,
    required this.purpose,
    required this.type,
    required this.price,
    required this.currency,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.ownerName,
  });

  final int id;
  final String title;
  final String status;
  final String reviewStatus;
  final String purpose;
  final String type;
  final double price;
  final String currency;
  final String address;
  final double? latitude;
  final double? longitude;
  final String? ownerName;

  factory RegionProperty.fromJson(Map<String, dynamic> json) {
    final owner = json['owner'] is Map<String, dynamic>
        ? json['owner'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return RegionProperty(
      id: _int(json['id']),
      title: json['title']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      reviewStatus: json['review_status']?.toString() ?? '',
      purpose: json['purpose']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      price: _double(json['price']),
      currency: json['currency']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      latitude: _nullableDouble(json['latitude']),
      longitude: _nullableDouble(json['longitude']),
      ownerName: _nullable(owner['name']),
    );
  }
}

List<T> _list<T>(dynamic value, T Function(Map<String, dynamic>) convert) {
  if (value is! List) {
    return <T>[];
  }
  return value
      .whereType<Map<String, dynamic>>()
      .map(convert)
      .toList(growable: false);
}

int _int(dynamic value) {
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _double(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

double? _nullableDouble(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value.toString());
}

String? _nullable(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return text;
}

DateTime? _date(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return DateTime.tryParse(text);
}

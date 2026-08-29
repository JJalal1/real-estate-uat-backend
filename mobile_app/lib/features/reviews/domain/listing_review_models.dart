class BrokerVerificationRecord {
  const BrokerVerificationRecord({
    required this.id,
    required this.status,
    this.requestNote,
    this.responseNote,
    this.requestedAt,
    this.respondedAt,
    this.cancelledAt,
    this.cancelReason,
    this.brokerUserId,
    this.brokerName,
    this.requestedByName,
    this.geoCellId,
  });

  final int id;
  final String status;
  final String? requestNote;
  final String? responseNote;
  final DateTime? requestedAt;
  final DateTime? respondedAt;
  final DateTime? cancelledAt;
  final String? cancelReason;
  final int? brokerUserId;
  final String? brokerName;
  final String? requestedByName;
  final int? geoCellId;

  bool get isPending => status == 'pending';
  bool get isAvailable => status == 'available';

  factory BrokerVerificationRecord.fromJson(Map<String, dynamic> json) {
    return BrokerVerificationRecord(
      id: _asInt(json['id']),
      status: json['status']?.toString() ?? '',
      requestNote: _nullable(json['request_note']),
      responseNote: _nullable(json['response_note']),
      requestedAt: _date(json['requested_at']),
      respondedAt: _date(json['responded_at']),
      cancelledAt: _date(json['cancelled_at']),
      cancelReason: _nullable(json['cancel_reason']),
      brokerUserId: _nullableInt(json['broker_user_id']),
      brokerName: _nullable(json['broker_name']),
      requestedByName: _nullable(json['requested_by_name']),
      geoCellId: _nullableInt(json['geo_cell_id']),
    );
  }
}

class BrokerVerificationState {
  const BrokerVerificationState({
    required this.required,
    required this.approvalAllowed,
    this.reason,
    this.geoCellId,
    this.geoCellName,
    this.brokerId,
    this.brokerName,
    this.latest,
  });

  final bool required;
  final bool approvalAllowed;
  final String? reason;
  final int? geoCellId;
  final String? geoCellName;
  final int? brokerId;
  final String? brokerName;
  final BrokerVerificationRecord? latest;

  factory BrokerVerificationState.fromJson(dynamic raw) {
    if (raw is! Map<String, dynamic>) {
      return const BrokerVerificationState(
        required: false,
        approvalAllowed: true,
      );
    }
    final broker = raw['broker'];
    final brokerMap =
        broker is Map<String, dynamic> ? broker : const <String, dynamic>{};
    final latest = raw['latest'];
    return BrokerVerificationState(
      required: raw['required'] == true || raw['required'] == 1,
      approvalAllowed:
          raw['approval_allowed'] == true || raw['approval_allowed'] == 1,
      reason: _nullable(raw['reason']),
      geoCellId: _nullableInt(raw['geo_cell_id']),
      geoCellName: _nullable(raw['geo_cell_name']),
      brokerId: _nullableInt(brokerMap['id']),
      brokerName: _nullable(brokerMap['name']),
      latest: latest is Map<String, dynamic>
          ? BrokerVerificationRecord.fromJson(latest)
          : null,
    );
  }
}

class ReviewListingItem {
  const ReviewListingItem({
    required this.id,
    required this.title,
    required this.purpose,
    required this.type,
    required this.price,
    required this.reviewStatus,
    required this.ownerName,
    required this.ownerVerificationType,
    required this.ownerVerificationStatus,
    required this.proofCount,
    required this.brokerVerification,
    this.reason,
  });

  final int id;
  final String title;
  final String purpose;
  final String type;
  final double price;
  final String reviewStatus;
  final String ownerName;
  final String? ownerVerificationType;
  final String ownerVerificationStatus;
  final int proofCount;
  final BrokerVerificationState brokerVerification;
  final String? reason;

  factory ReviewListingItem.fromJson(Map<String, dynamic> json) {
    final owner = json['owner'];
    final documents = json['proof_documents'];
    return ReviewListingItem(
      id: _asInt(json['id']),
      title: json['title']?.toString() ?? '',
      purpose: json['purpose']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      price: _asDouble(json['price']),
      reviewStatus: json['review_status']?.toString() ?? '',
      ownerName:
          owner is Map<String, dynamic> ? owner['name']?.toString() ?? '' : '',
      ownerVerificationType: owner is Map<String, dynamic>
          ? _nullable(owner['verification_type'])
          : null,
      ownerVerificationStatus: owner is Map<String, dynamic>
          ? owner['verification_status']?.toString() ?? 'not_submitted'
          : 'not_submitted',
      proofCount: documents is List ? documents.length : 0,
      brokerVerification:
          BrokerVerificationState.fromJson(json['broker_verification']),
      reason: _nullable(json['last_review_reason']),
    );
  }
}

class PublicationBlockItem {
  const PublicationBlockItem({
    required this.id,
    required this.propertyAssetId,
    required this.purpose,
    required this.isActive,
    required this.reason,
  });
  final int id;
  final int propertyAssetId;
  final String purpose;
  final bool isActive;
  final String reason;

  factory PublicationBlockItem.fromJson(Map<String, dynamic> json) {
    return PublicationBlockItem(
      id: _asInt(json['id']),
      propertyAssetId: _asInt(json['property_asset_id']),
      purpose: json['purpose']?.toString() ?? '',
      isActive: json['is_active'] == true || json['is_active'] == 1,
      reason: json['reason']?.toString() ?? '',
    );
  }
}

class ReviewMediaItem {
  const ReviewMediaItem(
      {required this.id, required this.url, this.name, this.kind});
  final int id;
  final String url;
  final String? name;
  final String? kind;

  factory ReviewMediaItem.fromImageJson(Map<String, dynamic> json) {
    return ReviewMediaItem(
      id: _asInt(json['id']),
      url: json['url']?.toString() ?? '',
    );
  }

  factory ReviewMediaItem.fromDocumentJson(Map<String, dynamic> json) {
    return ReviewMediaItem(
      id: _asInt(json['id']),
      url: json['url']?.toString() ?? '',
      name: _nullable(json['original_name']),
      kind: _nullable(json['kind']),
    );
  }
}

class ReviewListingDetail {
  const ReviewListingDetail({
    required this.id,
    required this.title,
    required this.purpose,
    required this.type,
    required this.price,
    required this.reviewStatus,
    required this.ownerName,
    required this.ownerEmail,
    required this.ownerPhone,
    required this.ownerVerificationType,
    required this.ownerVerificationStatus,
    required this.ownerIdentityReviewed,
    required this.ownershipDocumentType,
    required this.documentOwnerName,
    required this.ownerRelationshipType,
    required this.ownerRelationshipNote,
    required this.ownerNameMatchesDocument,
    required this.ownershipDocumentPresent,
    required this.description,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.areaM2,
    this.areaValue,
    this.areaUnit,
    this.bedrooms,
    this.bathrooms,
    this.hasParking,
    this.buildingFacade,
    required this.images,
    required this.proofDocuments,
    required this.reviewHistory,
    required this.brokerVerification,
    this.reason,
  });

  final int id;
  final String title;
  final String purpose;
  final String type;
  final double price;
  final String reviewStatus;
  final String ownerName;
  final String ownerEmail;
  final String ownerPhone;
  final String? ownerVerificationType;
  final String ownerVerificationStatus;
  final bool ownerIdentityReviewed;
  final String? ownershipDocumentType;
  final String? documentOwnerName;
  final String? ownerRelationshipType;
  final String? ownerRelationshipNote;
  final bool? ownerNameMatchesDocument;
  final bool ownershipDocumentPresent;
  final String description;
  final String address;
  final double latitude;
  final double longitude;
  final int? areaM2;
  final double? areaValue;
  final String? areaUnit;
  final int? bedrooms;
  final int? bathrooms;
  final bool? hasParking;
  final String? buildingFacade;
  final List<ReviewMediaItem> images;
  final List<ReviewMediaItem> proofDocuments;
  final List<ReviewHistoryItem> reviewHistory;
  final BrokerVerificationState brokerVerification;
  final String? reason;

  factory ReviewListingDetail.fromJson(Map<String, dynamic> json) {
    final owner = json['owner'];
    final ownerMap =
        owner is Map<String, dynamic> ? owner : const <String, dynamic>{};
    final ownership = json['ownership_relationship'];
    final ownershipMap = ownership is Map<String, dynamic>
        ? ownership
        : const <String, dynamic>{};
    final imageRows = json['images'];
    final proofRows = json['proof_documents'];
    final historyRows = json['review_history'];
    return ReviewListingDetail(
      id: _asInt(json['id']),
      title: json['title']?.toString() ?? '',
      purpose: json['purpose']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      price: _asDouble(json['price']),
      reviewStatus: json['review_status']?.toString() ?? '',
      ownerName: ownerMap['name']?.toString() ?? '',
      ownerEmail: ownerMap['email']?.toString() ?? '',
      ownerPhone: ownerMap['phone']?.toString() ?? '',
      ownerVerificationType: _nullable(ownerMap['verification_type']),
      ownerVerificationStatus:
          ownerMap['verification_status']?.toString() ?? 'not_submitted',
      ownerIdentityReviewed: ownerMap['identity_reviewed'] == true ||
          ownerMap['identity_reviewed'] == 1,
      ownershipDocumentType: _nullable(ownershipMap['document_type']),
      documentOwnerName: _nullable(ownershipMap['document_owner_name']),
      ownerRelationshipType: _nullable(ownershipMap['relationship_type']),
      ownerRelationshipNote: _nullable(ownershipMap['relationship_note']),
      ownerNameMatchesDocument: _nullableBool(ownershipMap['name_matches_account']),
      ownershipDocumentPresent: ownershipMap['document_present'] == true ||
          ownershipMap['document_present'] == 1,
      description: json['description']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      latitude: _asDouble(json['latitude']),
      longitude: _asDouble(json['longitude']),
      areaM2: _nullableInt(json['area_m2']),
      areaValue: _nullableDouble(json['area_value']),
      areaUnit: _nullable(json['area_unit']),
      bedrooms: _nullableInt(json['bedrooms']),
      bathrooms: _nullableInt(json['bathrooms']),
      hasParking: _nullableBool(json['has_parking']),
      buildingFacade: _nullable(json['building_facade']),
      images: imageRows is List
          ? imageRows
              .whereType<Map<String, dynamic>>()
              .map(ReviewMediaItem.fromImageJson)
              .toList(growable: false)
          : const <ReviewMediaItem>[],
      proofDocuments: proofRows is List
          ? proofRows
              .whereType<Map<String, dynamic>>()
              .map(ReviewMediaItem.fromDocumentJson)
              .toList(growable: false)
          : const <ReviewMediaItem>[],
      reviewHistory: historyRows is List
          ? historyRows
              .whereType<Map<String, dynamic>>()
              .map(ReviewHistoryItem.fromJson)
              .toList(growable: false)
          : const <ReviewHistoryItem>[],
      brokerVerification:
          BrokerVerificationState.fromJson(json['broker_verification']),
      reason: _nullable(json['last_review_reason']),
    );
  }
}

class ReviewHistoryItem {
  const ReviewHistoryItem(
      {required this.action,
      this.fromStatus,
      this.toStatus,
      this.reason,
      this.actorName,
      this.createdAt});
  final String action;
  final String? fromStatus;
  final String? toStatus;
  final String? reason;
  final String? actorName;
  final DateTime? createdAt;
  factory ReviewHistoryItem.fromJson(Map<String, dynamic> json) =>
      ReviewHistoryItem(
        action: json['action']?.toString() ?? '',
        fromStatus: _nullable(json['from']),
        toStatus: _nullable(json['to']),
        reason: _nullable(json['reason']),
        actorName: _nullable(json['actor_name']),
        createdAt: _date(json['created_at']),
      );
}

class BrokerVerificationQueueItem {
  const BrokerVerificationQueueItem({
    required this.verification,
    required this.listingId,
    required this.listingTitle,
    required this.purpose,
    required this.type,
    required this.address,
    this.areaValue,
    this.areaUnit,
    this.areaM2,
    this.geoCellName,
  });

  final BrokerVerificationRecord verification;
  final int listingId;
  final String listingTitle;
  final String purpose;
  final String type;
  final String address;
  final double? areaValue;
  final String? areaUnit;
  final int? areaM2;
  final String? geoCellName;

  factory BrokerVerificationQueueItem.fromJson(Map<String, dynamic> json) {
    final listing = json['listing'];
    final listingMap =
        listing is Map<String, dynamic> ? listing : const <String, dynamic>{};
    return BrokerVerificationQueueItem(
      verification: BrokerVerificationRecord.fromJson(json),
      listingId: _asInt(listingMap['id']),
      listingTitle: listingMap['title']?.toString() ?? '',
      purpose: listingMap['purpose']?.toString() ?? '',
      type: listingMap['type']?.toString() ?? '',
      address: listingMap['address']?.toString() ?? '',
      areaValue: _nullableDouble(listingMap['area_value']),
      areaUnit: _nullable(listingMap['area_unit']),
      areaM2: _nullableInt(listingMap['area_m2']),
      geoCellName: _nullable(json['geo_cell_name']),
    );
  }
}

int _asInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int? _nullableInt(dynamic value) {
  if (value == null || value.toString().trim().isEmpty) return null;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

double? _nullableDouble(dynamic value) {
  if (value == null || value.toString().trim().isEmpty) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

bool? _nullableBool(dynamic value) {
  if (value == null || value.toString().trim().isEmpty) return null;
  if (value is bool) return value;
  final normalized = value.toString().trim().toLowerCase();
  if (normalized == '1' || normalized == 'true') return true;
  if (normalized == '0' || normalized == 'false') return false;
  return null;
}

String? _nullable(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  return text;
}

DateTime? _date(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  return DateTime.tryParse(text);
}

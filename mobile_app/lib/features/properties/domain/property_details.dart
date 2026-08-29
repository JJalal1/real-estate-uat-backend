class PropertyImageItem {
  const PropertyImageItem({
    required this.id,
    required this.url,
    required this.isPrimary,
    required this.sortOrder,
  });

  final int id;
  final String url;
  final bool isPrimary;
  final int sortOrder;

  factory PropertyImageItem.fromJson(Map<String, dynamic> json) {
    return PropertyImageItem(
      id: _asInt(json['id']) ?? 0,
      url: json['url']?.toString() ?? '',
      isPrimary: json['is_primary'] == true || json['is_primary'] == 1,
      sortOrder: _asInt(json['sort_order']) ?? 0,
    );
  }
}

class PropertySummary {
  const PropertySummary({
    required this.id,
    required this.title,
    required this.purpose,
    required this.type,
    required this.price,
    required this.currency,
    required this.latitude,
    required this.longitude,
    this.areaM2,
    this.areaValue,
    this.areaUnit,
    this.bedrooms,
    this.bathrooms,
    this.hasParking,
    this.buildingFacade,
    this.address,
    this.status = 'published',
    this.mainImage,
  });

  final int id;
  final String title;
  final String purpose;
  final String type;
  final double price;
  final String currency;
  final double latitude;
  final double longitude;
  final int? areaM2;
  final double? areaValue;
  final String? areaUnit;
  final int? bedrooms;
  final int? bathrooms;
  final bool? hasParking;
  final String? buildingFacade;
  final String? address;
  final String status;
  final String? mainImage;

  factory PropertySummary.fromJson(Map<String, dynamic> json) {
    return PropertySummary(
      id: _asInt(json['id']) ?? 0,
      title: json['title']?.toString() ?? '',
      purpose: json['purpose']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      price: _asDouble(json['price']) ?? 0,
      currency: json['currency']?.toString() ?? 'YER',
      latitude: _asDouble(json['latitude']) ?? 0,
      longitude: _asDouble(json['longitude']) ?? 0,
      areaM2: _asInt(json['area_m2']),
      areaValue: _asDouble(json['area_value']) ?? _asDouble(json['area_m2']),
      areaUnit: _nullableString(json['area_unit']) ??
          (json['area_m2'] == null ? null : 'sqm'),
      bedrooms: _asInt(json['bedrooms']),
      bathrooms: _asInt(json['bathrooms']),
      hasParking: _asBool(json['has_parking']),
      buildingFacade: _nullableString(json['building_facade']),
      address: _nullableString(json['address']),
      status: json['status']?.toString() ?? 'published',
      mainImage: _nullableString(json['main_image']),
    );
  }
}

class AdvertiserCommunitySummary {
  const AdvertiserCommunitySummary({
    required this.id,
    required this.name,
    required this.ratingAverage,
    required this.ratingCount,
    this.verificationType,
    this.verificationLabel = 'معلن',
    this.verificationStatus = 'not_submitted',
    this.verificationFlags = const <String, bool>{},
  });

  final int id;
  final String name;
  final double ratingAverage;
  final int ratingCount;
  final String? verificationType;
  final String verificationLabel;
  final String verificationStatus;
  final Map<String, bool> verificationFlags;

  bool verificationFlag(String key) => verificationFlags[key] == true;

  factory AdvertiserCommunitySummary.fromJson(Map<String, dynamic> json) {
    final rawFlags = json['verification_flags'];
    final flags = <String, bool>{};
    if (rawFlags is Map) {
      for (final entry in rawFlags.entries) {
        flags[entry.key.toString()] = entry.value == true || entry.value == 1;
      }
    }
    return AdvertiserCommunitySummary(
      id: _asInt(json['id']) ?? 0,
      name: json['name']?.toString() ?? 'المعلن',
      ratingAverage: _asDouble(json['rating_average']) ?? 0,
      ratingCount: _asInt(json['rating_count']) ?? 0,
      verificationType: _nullableString(json['verification_type']),
      verificationLabel: json['verification_label']?.toString() ?? 'معلن',
      verificationStatus:
          json['verification_status']?.toString() ?? 'not_submitted',
      verificationFlags: Map.unmodifiable(flags),
    );
  }
}

class PropertyDetails {
  const PropertyDetails({
    required this.id,
    required this.title,
    required this.purpose,
    required this.type,
    required this.price,
    required this.currency,
    required this.latitude,
    required this.longitude,
    required this.images,
    this.description,
    this.areaM2,
    this.areaValue,
    this.areaUnit,
    this.bedrooms,
    this.bathrooms,
    this.hasParking,
    this.buildingFacade,
    this.address,
    this.status = 'published',
    this.reviewStatus = 'approved',
    this.lastReviewReason,
    this.propertyAssetId,
    this.proofDocumentCount = 0,
    this.canSubmit = false,
    this.canEdit = true,
    this.contactPhone,
    this.contactWhatsapp,
    this.isOwner = false,
    this.ownershipDocumentType,
    this.documentOwnerName,
    this.ownerRelationshipType,
    this.ownerRelationshipNote,
    this.ownershipProofPresent = false,
    this.advertiser,
    this.commentsCount = 0,
    this.similar = const <PropertySummary>[],
  });

  final int id;
  final String title;
  final String? description;
  final String purpose;
  final String type;
  final double price;
  final String currency;
  final int? areaM2;
  final double? areaValue;
  final String? areaUnit;
  final int? bedrooms;
  final int? bathrooms;
  final bool? hasParking;
  final String? buildingFacade;
  final String? address;
  final double latitude;
  final double longitude;
  final String status;
  final String reviewStatus;
  final String? lastReviewReason;
  final int? propertyAssetId;
  final int proofDocumentCount;
  final bool canSubmit;
  final bool canEdit;
  final String? contactPhone;
  final String? contactWhatsapp;
  final bool isOwner;
  final String? ownershipDocumentType;
  final String? documentOwnerName;
  final String? ownerRelationshipType;
  final String? ownerRelationshipNote;
  final bool ownershipProofPresent;
  final AdvertiserCommunitySummary? advertiser;
  final int commentsCount;
  final List<PropertyImageItem> images;
  final List<PropertySummary> similar;

  String? get mainImage => images.isEmpty ? null : images.first.url;

  factory PropertyDetails.fromJson(Map<String, dynamic> json) {
    final imageRows = json['images'] as List<dynamic>? ?? const <dynamic>[];
    final similarRows = json['similar'] as List<dynamic>? ?? const <dynamic>[];

    final images = imageRows
        .whereType<Map<String, dynamic>>()
        .map(PropertyImageItem.fromJson)
        .where((image) => image.url.isNotEmpty)
        .toList()
      ..sort((a, b) {
        if (a.isPrimary != b.isPrimary) {
          return a.isPrimary ? -1 : 1;
        }
        return a.sortOrder.compareTo(b.sortOrder);
      });

    return PropertyDetails(
      id: _asInt(json['id']) ?? 0,
      title: json['title']?.toString() ?? '',
      description: _nullableString(json['description']),
      purpose: json['purpose']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      price: _asDouble(json['price']) ?? 0,
      currency: json['currency']?.toString() ?? 'YER',
      areaM2: _asInt(json['area_m2']),
      areaValue: _asDouble(json['area_value']) ?? _asDouble(json['area_m2']),
      areaUnit: _nullableString(json['area_unit']) ??
          (json['area_m2'] == null ? null : 'sqm'),
      bedrooms: _asInt(json['bedrooms']),
      bathrooms: _asInt(json['bathrooms']),
      hasParking: _asBool(json['has_parking']),
      buildingFacade: _nullableString(json['building_facade']),
      address: _nullableString(json['address']),
      latitude: _asDouble(json['latitude']) ?? 0,
      longitude: _asDouble(json['longitude']) ?? 0,
      status: json['status']?.toString() ?? 'published',
      reviewStatus: json['review_status']?.toString() ??
          (json['status'] == 'published' ? 'approved' : 'draft'),
      lastReviewReason: _nullableString(json['last_review_reason']),
      propertyAssetId: _asInt(json['property_asset_id']),
      proofDocumentCount: _asInt(json['proof_document_count']) ?? 0,
      canSubmit: json['can_submit'] == true || json['can_submit'] == 1,
      canEdit: json['can_edit'] == null ||
          json['can_edit'] == true ||
          json['can_edit'] == 1,
      contactPhone: _nullableString(json['contact_phone']),
      contactWhatsapp: _nullableString(json['contact_whatsapp']),
      isOwner: json['is_owner'] == true || json['is_owner'] == 1,
      ownershipDocumentType: _nullableString(json['ownership_document_type']),
      documentOwnerName: _nullableString(json['document_owner_name']),
      ownerRelationshipType: _nullableString(json['owner_relationship_type']),
      ownerRelationshipNote: _nullableString(json['owner_relationship_note']),
      ownershipProofPresent: json['ownership_proof_present'] == true ||
          json['ownership_proof_present'] == 1,
      advertiser: json['advertiser'] is Map<String, dynamic>
          ? AdvertiserCommunitySummary.fromJson(
              json['advertiser'] as Map<String, dynamic>,
            )
          : null,
      commentsCount: json['community'] is Map<String, dynamic>
          ? _asInt((json['community']
                  as Map<String, dynamic>)['comments_count']) ??
              0
          : 0,
      images: images,
      similar: similarRows
          .whereType<Map<String, dynamic>>()
          .map(PropertySummary.fromJson)
          .toList(growable: false),
    );
  }

  PropertySummary toSummary() {
    return PropertySummary(
      id: id,
      title: title,
      purpose: purpose,
      type: type,
      price: price,
      currency: currency,
      latitude: latitude,
      longitude: longitude,
      areaM2: areaM2,
      areaValue: areaValue,
      areaUnit: areaUnit,
      bedrooms: bedrooms,
      bathrooms: bathrooms,
      hasParking: hasParking,
      buildingFacade: buildingFacade,
      address: address,
      status: status,
      mainImage: mainImage,
    );
  }
}

class PropertyListingInput {
  const PropertyListingInput({
    required this.title,
    required this.purpose,
    required this.type,
    required this.price,
    required this.latitude,
    required this.longitude,
    this.description,
    this.currency = 'YER',
    this.areaM2,
    this.areaValue,
    this.areaUnit,
    this.bedrooms,
    this.bathrooms,
    this.hasParking,
    this.buildingFacade,
    this.address,
    this.contactPhone,
    this.contactWhatsapp,
    this.ownershipDocumentType,
    this.documentOwnerName,
    this.ownerRelationshipType,
    this.ownerRelationshipNote,
  });

  final String title;
  final String? description;
  final String purpose;
  final String type;
  final double price;
  final String currency;
  final int? areaM2;
  final double? areaValue;
  final String? areaUnit;
  final int? bedrooms;
  final int? bathrooms;
  final bool? hasParking;
  final String? buildingFacade;
  final String? address;
  final double latitude;
  final double longitude;
  final String? contactPhone;
  final String? contactWhatsapp;
  final String? ownershipDocumentType;
  final String? documentOwnerName;
  final String? ownerRelationshipType;
  final String? ownerRelationshipNote;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'title': title.trim(),
      if (description != null && description!.trim().isNotEmpty)
        'description': description!.trim(),
      'purpose': purpose,
      'type': type,
      'price': price,
      'currency': currency.toUpperCase(),
      'listing_input_version': 2,
      if (areaValue != null) 'area_value': areaValue,
      if (areaUnit != null && areaUnit!.trim().isNotEmpty)
        'area_unit': areaUnit,
      if (areaValue == null && areaM2 != null) 'area_m2': areaM2,
      if (type != 'land' && bedrooms != null) 'bedrooms': bedrooms,
      if (type != 'land' && bathrooms != null) 'bathrooms': bathrooms,
      if (type != 'land' && hasParking != null) 'has_parking': hasParking,
      if (type != 'land' &&
          buildingFacade != null &&
          buildingFacade!.isNotEmpty)
        'building_facade': buildingFacade,
      if (address != null && address!.trim().isNotEmpty)
        'address': address!.trim(),
      'latitude': latitude,
      'longitude': longitude,
      'contact_phone': contactPhone?.trim() ?? '',
      'contact_whatsapp': contactWhatsapp?.trim() ?? '',
      if (ownershipDocumentType != null && ownershipDocumentType!.isNotEmpty)
        'ownership_document_type': ownershipDocumentType,
      if (documentOwnerName != null && documentOwnerName!.trim().isNotEmpty)
        'document_owner_name': documentOwnerName!.trim(),
      if (ownerRelationshipType != null && ownerRelationshipType!.isNotEmpty)
        'owner_relationship_type': ownerRelationshipType,
      if (ownerRelationshipNote != null &&
          ownerRelationshipNote!.trim().isNotEmpty)
        'owner_relationship_note': ownerRelationshipNote!.trim(),
    };
  }
}

int? _asInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}

double? _asDouble(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '');
}

bool? _asBool(dynamic value) {
  if (value == null) return null;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value.toString().trim().toLowerCase();
  if (text == 'true' || text == '1') return true;
  if (text == 'false' || text == '0') return false;
  return null;
}

String? _nullableString(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return text;
}

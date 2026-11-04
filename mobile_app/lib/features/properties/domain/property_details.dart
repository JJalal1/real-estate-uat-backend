import 'property_schema.dart';
import 'property_coordinates.dart';
import 'dart:convert';

class PropertyImageItem {
  const PropertyImageItem({
    required this.id,
    required this.url,
    required this.isPrimary,
    required this.sortOrder,
    this.variants = const {},
  });

  final int id;
  final String url;
  final bool isPrimary;
  final int sortOrder;
  final Map<String,String> variants;
  String get cardUrl => variants['card'] ?? url;
  String get detailUrl => variants['detail'] ?? url;
  String get galleryUrl => variants['gallery'] ?? detailUrl;
  String get zoomUrl => variants['zoom'] ?? galleryUrl;

  factory PropertyImageItem.fromJson(Map<String, dynamic> json) {
    return PropertyImageItem(
      id: _asInt(json['id']) ?? 0,
      url: json['url']?.toString() ?? '',
      isPrimary: json['is_primary'] == true || json['is_primary'] == 1,
      sortOrder: _asInt(json['sort_order']) ?? 0,
      variants: {for (final entry in (json['variants'] as Map? ?? const {}).entries) if (entry.value is String) entry.key.toString():entry.value as String},
    );
  }
}

class PropertySummary {
  const PropertySummary({
    required this.id,
    required this.title,
    required this.purpose,
    required this.type,
    this.tenureType,
    required this.price,
    required this.currency,
    required this.latitude,
    required this.longitude,
    this.basePrice,
    this.priceDisplayMode,
    this.priceDisplayNote,
    this.monthlyRent,
    this.rentalTermMonths,
    this.advanceMonths,
    this.areaM2,
    this.areaValue,
    this.areaUnit,
    this.bedrooms,
    this.bathrooms,
    this.hasParking,
    this.hasElevator,
    this.floorsCount,
    this.unitsPerFloor = const [],
    this.shopOpenings,
    this.buildingFacade,
    this.address,
    this.status = 'published',
    this.mainImage,
    this.imageUrls = const [],
    this.isSpotlight = false,
    this.floorNumber,
  });

  final int id;
  final String title;
  final String purpose;
  final String type;
  final String? tenureType;

  /// User-facing amount; Financial V1 uses display_price when returned.
  final double price;
  final double? basePrice;
  final String? priceDisplayMode;
  final String? priceDisplayNote;
  final double? monthlyRent;
  final int? rentalTermMonths;
  final int? advanceMonths;
  final String currency;
  final double latitude;
  final double longitude;
  final int? areaM2;
  final double? areaValue;
  final String? areaUnit;
  final int? bedrooms;
  final int? bathrooms;
  final bool? hasParking;
  final bool? hasElevator;
  final int? floorsCount;
  final List<int> unitsPerFloor;
  final int? shopOpenings;
  final String? buildingFacade;
  final String? address;
  final String status;
  final String? mainImage;
  final List<String> imageUrls;
  final bool isSpotlight;
  final String? floorNumber;

  factory PropertySummary.fromJson(Map<String, dynamic> json) {
    json = DynamicPropertySchema.sanitize(json);
    final rawPrice = _asDouble(json['price']) ?? 0;
    return PropertySummary(
      id: _asInt(json['id']) ?? 0,
      title: json['title']?.toString() ?? '',
      purpose: json['purpose']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      tenureType: _nullableString(json['tenure_type']),
      price: _asDouble(json['display_price']) ?? rawPrice,
      basePrice: _asDouble(json['base_price']) ?? rawPrice,
      priceDisplayMode: _nullableString(json['price_display_mode']),
      priceDisplayNote: _nullableString(json['price_display_note']),
      monthlyRent: _asDouble(json['monthly_rent']),
      rentalTermMonths: _asInt(json['rental_term_months']),
      advanceMonths: _asInt(json['advance_months']),
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
      hasElevator: null,
      floorsCount: _asInt(json['floors_count']),
      unitsPerFloor: (json['units_per_floor'] as List? ?? const []).whereType<num>().map((e) => e.toInt()).toList(),
      shopOpenings: _asInt(json['shop_openings']),
      buildingFacade: _nullableString(json['building_facade']),
      address: _nullableString(json['address']),
      status: json['status']?.toString() ?? 'published',
      mainImage: _nullableString(json['main_image']),
      imageUrls: List.unmodifiable((json['image_urls'] as List? ?? const []).whereType<String>().where((url) => url.isNotEmpty).take(12)),
      isSpotlight: _asBool(json['is_spotlight']) ?? false,
      floorNumber: _nullableString(json['floor_number']),
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
    this.tenureType,
    required this.price,
    required this.currency,
    required this.latitude,
    required this.longitude,
    this.locationProvided = true,
    required this.images,
    this.basePrice,
    this.priceDisplayMode,
    this.priceDisplayNote,
    this.rentalConditions = const [],
    this.monthlyRent,
    this.rentalTermMonths,
    this.advanceMonths,
    this.financialHold = false,
    this.availabilityStatus = 'available',
    this.availabilityConfirmedAt,
    this.availabilityDueAt,
    this.viewCount = 0,
    this.favoriteCount = 0,
    this.conversationCount = 0,
    this.viewingCount = 0,
    this.saiAttestationRequired = false,
    this.saiAttestationText,
    this.description,
    this.areaM2,
    this.areaValue,
    this.areaUnit,
    this.bedrooms,
    this.bathrooms,
    this.hasParking,
    this.hasElevator,
    this.floorsCount,
    this.unitsPerFloor = const [],
    this.shopOpenings,
    this.buildingFacade,
    this.address,
    this.buildingReference,
    this.unitNumber,
    this.floorNumber,
    this.unitOccupiesEntireFloor = false,
    this.landBoundaryGeoJson,
    this.duplicateCheckStatus,
    this.duplicateCheckScore = 0,
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
    this.isSpotlight = false,
  });

  final int id;
  final String title;
  final String? description;
  final String purpose;
  final String type;
  final String? tenureType;

  /// User-facing amount. Use [basePrice] when editing the listing itself.
  final double price;
  final double? basePrice;
  final String? priceDisplayMode;
  final String? priceDisplayNote;
  final List<Map<String, dynamic>> rentalConditions;
  final double? monthlyRent;
  final int? rentalTermMonths;
  final int? advanceMonths;
  final bool financialHold;
  final bool saiAttestationRequired;
  final String? saiAttestationText;
  final String currency;
  final int? areaM2;
  final double? areaValue;
  final String? areaUnit;
  final int? bedrooms;
  final int? bathrooms;
  final bool? hasParking;
  final bool? hasElevator;
  final int? floorsCount;
  final List<int> unitsPerFloor;
  final int? shopOpenings;
  final String? buildingFacade;
  final String? address;
  final String? buildingReference;
  final String? unitNumber;
  final String? floorNumber;
  final bool unitOccupiesEntireFloor;
  final Map<String, dynamic>? landBoundaryGeoJson;
  final String? duplicateCheckStatus;
  final int duplicateCheckScore;
  final double latitude;
  final double longitude;
  final bool locationProvided;
  bool get hasValidLocation => locationProvided && hasValidPropertyCoordinates(latitude, longitude);
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
  final String availabilityStatus;
  final DateTime? availabilityConfirmedAt, availabilityDueAt;
  final int viewCount, favoriteCount, conversationCount, viewingCount;
  final String? ownershipDocumentType;
  final String? documentOwnerName;
  final String? ownerRelationshipType;
  final String? ownerRelationshipNote;
  final bool ownershipProofPresent;
  final AdvertiserCommunitySummary? advertiser;
  final int commentsCount;
  final List<PropertyImageItem> images;
  final List<PropertySummary> similar;
  final bool isSpotlight;

  String? get mainImage => images.isEmpty ? null : images.first.url;
  List<String> get imageUrls => images.map((image) => image.galleryUrl).take(12).toList(growable: false);
  double get editablePrice => basePrice ?? price;

  factory PropertyDetails.fromJson(Map<String, dynamic> json) {
    json = DynamicPropertySchema.sanitize(json);
    final imageRows = json['images'] as List<dynamic>? ?? const <dynamic>[];
    final similarRows = json['similar'] as List<dynamic>? ?? const <dynamic>[];
    final rawPrice = _asDouble(json['price']) ?? 0;

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
      tenureType: _nullableString(json['tenure_type']),
      price: _asDouble(json['display_price']) ?? rawPrice,
      basePrice: _asDouble(json['base_price']) ?? rawPrice,
      priceDisplayMode: _nullableString(json['price_display_mode']),
      priceDisplayNote: _nullableString(json['price_display_note']),
      rentalConditions: (json['rental_conditions'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(),
      monthlyRent: _asDouble(json['monthly_rent']),
      rentalTermMonths: _asInt(json['rental_term_months']),
      advanceMonths: _asInt(json['advance_months']),
      financialHold: _asBool(json['financial_hold']) ?? false,
      availabilityStatus: json['availability_status']?.toString() ?? 'available',
      availabilityConfirmedAt: DateTime.tryParse('${json['availability_confirmed_at'] ?? ''}'),
      availabilityDueAt: DateTime.tryParse('${json['availability_due_at'] ?? ''}'),
      viewCount: _asInt(json['view_count']) ?? 0,
      favoriteCount: _asInt(json['favorite_count']) ?? 0,
      conversationCount: _asInt(json['conversation_count']) ?? 0,
      viewingCount: _asInt(json['viewing_count']) ?? 0,
      saiAttestationRequired:
          _asBool(json['sai_attestation_required']) ?? false,
      saiAttestationText: _nullableString(json['sai_attestation_text']),
      currency: json['currency']?.toString() ?? 'YER',
      areaM2: _asInt(json['area_m2']),
      areaValue: _asDouble(json['area_value']) ?? _asDouble(json['area_m2']),
      areaUnit: _nullableString(json['area_unit']) ??
          (json['area_m2'] == null ? null : 'sqm'),
      bedrooms: _asInt(json['bedrooms']),
      bathrooms: _asInt(json['bathrooms']),
      hasParking: _asBool(json['has_parking']),
      hasElevator: null,
      floorsCount: _asInt(json['floors_count']),
      unitsPerFloor: (json['units_per_floor'] as List? ?? const []).whereType<num>().map((e) => e.toInt()).toList(),
      shopOpenings: _asInt(json['shop_openings']),
      buildingFacade: _nullableString(json['building_facade']),
      address: _nullableString(json['address']),
      buildingReference: _nullableString(json['building_reference']),
      unitNumber: _nullableString(json['unit_number']),
      floorNumber: _nullableString(json['floor_number']),
      unitOccupiesEntireFloor: json['unit_occupies_entire_floor'] == true || json['type'] == 'floor',
      landBoundaryGeoJson: json['land_boundary_geojson'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(
              json['land_boundary_geojson'] as Map<String, dynamic>)
          : null,
      duplicateCheckStatus: _nullableString(json['duplicate_check_status']),
      duplicateCheckScore: _asInt(json['duplicate_check_score']) ?? 0,
      locationProvided: _asDouble(json['latitude']) != null && _asDouble(json['longitude']) != null,
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
      isSpotlight: _asBool(json['is_spotlight']) ?? false,
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
      tenureType: tenureType,
      price: price,
      basePrice: basePrice,
      priceDisplayMode: priceDisplayMode,
      priceDisplayNote: priceDisplayNote,
      monthlyRent: monthlyRent,
      rentalTermMonths: rentalTermMonths,
      advanceMonths: advanceMonths,
      currency: currency,
      latitude: latitude,
      longitude: longitude,
      areaM2: areaM2,
      areaValue: areaValue,
      areaUnit: areaUnit,
      bedrooms: bedrooms,
      bathrooms: bathrooms,
      hasParking: hasParking,
      floorsCount: floorsCount,
      unitsPerFloor: unitsPerFloor,
      shopOpenings: shopOpenings,
      buildingFacade: buildingFacade,
      address: address,
      status: status,
      mainImage: mainImage,
      imageUrls: images.map((image) => image.url).toList(growable: false),
      isSpotlight: isSpotlight,
      floorNumber: floorNumber,
    );
  }
}

class PropertyListingInput {
  const PropertyListingInput({
    this.inputVersion = 8,
    this.rentalConditions = const [],
    required this.title,
    required this.purpose,
    required this.type,
    required this.price,
    required this.latitude,
    required this.longitude,
    this.tenureType,
    this.description,
    this.currency = 'YER',
    this.priceDisplayMode,
    this.monthlyRent,
    this.rentalTermMonths,
    this.advanceMonths,
    this.areaM2,
    this.areaValue,
    this.areaUnit,
    this.bedrooms,
    this.bathrooms,
    this.hasParking,
    this.hasElevator,
    this.floorsCount,
    this.unitsPerFloor = const [],
    this.shopOpenings,
    this.buildingFacade,
    this.address,
    this.buildingReference,
    this.unitNumber,
    this.floorNumber,
    this.unitOccupiesEntireFloor = false,
    this.landBoundaryGeoJson,
    this.contactPhone,
    this.contactWhatsapp,
    this.ownershipDocumentType,
    this.documentOwnerName,
    this.ownerRelationshipType,
    this.ownerRelationshipNote,
  });

  final int inputVersion;
  final List<Map<String, dynamic>> rentalConditions;
  final String title;
  final String? description;
  final String purpose;
  final String type;
  final String? tenureType;
  final double price;
  final String currency;
  final String? priceDisplayMode;
  final double? monthlyRent;
  final int? rentalTermMonths;
  final int? advanceMonths;
  final int? areaM2;
  final double? areaValue;
  final String? areaUnit;
  final int? bedrooms;
  final int? bathrooms;
  final bool? hasParking;
  final bool? hasElevator;
  final int? floorsCount;
  final List<int> unitsPerFloor;
  final int? shopOpenings;
  final String? buildingFacade;
  final String? address;
  final String? buildingReference;
  final String? unitNumber;
  final String? floorNumber;
  final bool unitOccupiesEntireFloor;
  final Map<String, dynamic>? landBoundaryGeoJson;
  final double latitude;
  final double longitude;
  final String? contactPhone;
  final String? contactWhatsapp;
  final String? ownershipDocumentType;
  final String? documentOwnerName;
  final String? ownerRelationshipType;
  final String? ownerRelationshipNote;

  Map<String, dynamic> toMap() {
    return DynamicPropertySchema.sanitize(<String, dynamic>{
      'title': title.trim(),
      if (description != null)
        'description': description!.trim(),
      'purpose': purpose,
      'type': type,
      if (tenureType != null && tenureType!.trim().isNotEmpty)
        'tenure_type': tenureType,
      'price': price,
      'currency': currency.toUpperCase(),
      if (priceDisplayMode != null && priceDisplayMode!.isNotEmpty)
        'price_display_mode': priceDisplayMode,
      if (purpose == 'rent' && monthlyRent != null) 'monthly_rent': monthlyRent,
      if (purpose == 'rent' && rentalTermMonths != null)
        'rental_term_months': rentalTermMonths,
      if (purpose == 'rent' && advanceMonths != null)
        'advance_months': advanceMonths,
      'listing_input_version': inputVersion,
      if (inputVersion >= 6) 'rental_conditions': jsonEncode(purpose == 'rent' ? rentalConditions : []),
      if (inputVersion >= 6 && areaValue == null && areaM2 == null) ...{'area_value': null, 'area_unit': null},
      'unit_occupies_entire_floor': type == 'apartment' && unitOccupiesEntireFloor,
      if (areaValue != null) 'area_value': areaValue,
      if (areaUnit != null && areaUnit!.trim().isNotEmpty)
        'area_unit': areaUnit,
      if (areaValue == null && areaM2 != null) 'area_m2': areaM2,
      if (type != 'land' && bedrooms != null) 'bedrooms': bedrooms,
      if (type != 'land' && bathrooms != null) 'bathrooms': bathrooms,
      if (type != 'land' && hasParking != null) 'has_parking': hasParking,
      if (floorsCount != null) 'floors_count': floorsCount,
      if (unitsPerFloor.isNotEmpty) 'units_per_floor': jsonEncode(unitsPerFloor),
      if (shopOpenings != null) 'shop_openings': shopOpenings,
      if (buildingFacade != null &&
          buildingFacade!.isNotEmpty)
        'building_facade': buildingFacade,
      if (address != null && address!.trim().isNotEmpty)
        'address': address!.trim(),
      if (buildingReference != null && buildingReference!.trim().isNotEmpty)
        'building_reference': buildingReference!.trim(),
      if (unitNumber != null && unitNumber!.trim().isNotEmpty)
        'unit_number': unitNumber!.trim(),
      if (floorNumber != null && floorNumber!.trim().isNotEmpty)
        'floor_number': floorNumber!.trim(),
      if (landBoundaryGeoJson != null)
        'land_boundary_geojson': jsonEncode(landBoundaryGeoJson),
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
    });
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
  if (text == null || text.isEmpty) return null;
  return text;
}

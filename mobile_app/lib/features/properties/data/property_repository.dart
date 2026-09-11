import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../account/data/auth_repository.dart';
import '../domain/property_details.dart';
import '../domain/property_marker.dart';
import '../domain/property_location_address.dart';
import '../domain/property_sai.dart';

final propertyRepositoryProvider = Provider<PropertyRepository>((ref) {
  return PropertyRepository(
    ref.watch(dioProvider),
    ref.watch(authRepositoryProvider),
  );
});

/// Incremented after a successful listing mutation so every dependent screen
/// refreshes without retaining stale family-provider results.
final propertyDataRevisionProvider = StateProvider<int>((ref) => 0);

class PropertyRepository {
  PropertyRepository(this._dio, this._auth);

  final Dio _dio;
  final AuthRepository _auth;

  Future<List<PropertyMarker>> nearby({
    required double latitude,
    required double longitude,
    double radiusKm = 30,
    String? purpose,
    String? type,
    double? minPrice,
    double? maxPrice,
    int? minBedrooms,
    int? minBathrooms,
    double? minArea,
    double? maxArea,
    String? search,
    double? south,
    double? west,
    double? north,
    double? east,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/properties/nearby',
      queryParameters: {
        'latitude': latitude,
        'longitude': longitude,
        'radius_km': radiusKm,
        if (purpose != null && purpose.isNotEmpty) 'purpose': purpose,
        if (type != null && type.isNotEmpty) 'type': type,
        if (minPrice != null) 'min_price': minPrice,
        if (maxPrice != null) 'max_price': maxPrice,
        if (minBedrooms != null) 'min_bedrooms': minBedrooms,
        if (minBathrooms != null) 'min_bathrooms': minBathrooms,
        if (minArea != null) 'min_area_m2': minArea,
        if (maxArea != null) 'max_area_m2': maxArea,
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
        if (south != null && west != null && north != null && east != null) ...{
          'south': south,
          'west': west,
          'north': north,
          'east': east,
        },
      },
    );

    final rows = response.data?['data'] as List<dynamic>? ?? const <dynamic>[];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(PropertyMarker.fromJson)
        .toList(growable: false);
  }

  Future<PropertyLocationAddress> resolveLocationAddress({
    required double latitude,
    required double longitude,
  }) async {
    var result = const PropertyLocationAddress();

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/regions/reverse-address',
        queryParameters: {
          'latitude': latitude,
          'longitude': longitude,
        },
      );
      final data = response.data?['data'];
      if (data is Map<String, dynamic>) {
        result = PropertyLocationAddress(
          governorate: _nullableText(data['governorate']),
          district: _nullableText(data['district']),
          street: _nullableText(data['street']),
          formattedAddress: _nullableText(data['formatted_address']),
        );
      }
    } catch (_) {
      // Continue with device-side providers. Coordinates remain authoritative.
    }

    if (result.isComplete) return result;

    final nominatim = await _deviceNominatimAddress(latitude, longitude);
    result = result.mergeFallback(nominatim);
    if (result.isComplete) return result;

    final photon = await _devicePhotonAddress(latitude, longitude);
    return result.mergeFallback(photon);
  }

  Future<PropertyLocationAddress> _deviceNominatimAddress(
    double latitude,
    double longitude,
  ) async {
    try {
      final reverseGeocoder = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 7),
          headers: const {
            'Accept': 'application/json',
            'User-Agent': 'RealEstate-UAT/1.8 map-location-picker',
          },
        ),
      );
      final response = await reverseGeocoder.get<Map<String, dynamic>>(
        'https://nominatim.openstreetmap.org/reverse',
        queryParameters: {
          'format': 'jsonv2',
          'lat': latitude,
          'lon': longitude,
          'zoom': 18,
          'addressdetails': 1,
          'namedetails': 1,
          'accept-language': 'ar',
        },
      );
      final data = response.data;
      final address = data?['address'];
      if (address is! Map<String, dynamic>) {
        return const PropertyLocationAddress();
      }
      var street = _firstText(address, const [
        'road',
        'pedestrian',
        'residential',
        'footway',
        'path',
      ]);
      final formatted = _nullableText(data?['display_name']);
      if (street == null && formatted != null) {
        final first = formatted.split(',').first.trim();
        if (first.isNotEmpty) street = first;
      }
      return PropertyLocationAddress(
        governorate: _firstText(address, const [
          'state',
          'province',
          'state_district',
          'county',
        ]),
        district: _firstText(address, const [
          'neighbourhood',
          'suburb',
          'quarter',
          'city_district',
          'district',
          'village',
          'town',
          'city',
        ]),
        street: street,
        formattedAddress: formatted,
      );
    } catch (_) {
      return const PropertyLocationAddress();
    }
  }

  Future<PropertyLocationAddress> _devicePhotonAddress(
    double latitude,
    double longitude,
  ) async {
    try {
      final reverseGeocoder = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 7),
          headers: const {
            'Accept': 'application/json',
            'User-Agent': 'RealEstate-UAT/1.8 map-location-picker',
          },
        ),
      );
      final response = await reverseGeocoder.get<Map<String, dynamic>>(
        'https://photon.komoot.io/reverse',
        queryParameters: {
          'lat': latitude,
          'lon': longitude,
          'limit': 5,
          'radius': 10,
        },
      );
      final features = response.data?['features'];
      if (features is! List) return const PropertyLocationAddress();

      String? governorate;
      String? district;
      String? street;
      String? formatted;
      for (final feature in features.whereType<Map<String, dynamic>>()) {
        final properties = feature['properties'];
        if (properties is! Map<String, dynamic>) continue;
        governorate ??= _firstText(properties, const ['state', 'county']);
        district ??= _firstText(
          properties,
          const ['district', 'locality', 'city', 'county'],
        );
        street ??= _nullableText(properties['street']);
        if (street == null && properties['osm_key'] == 'highway') {
          street = _nullableText(properties['name']);
        }
        formatted ??= _nullableText(properties['name']);
        if (governorate != null && district != null && street != null) break;
      }
      return PropertyLocationAddress(
        governorate: governorate,
        district: district,
        street: street,
        formattedAddress: formatted,
      );
    } catch (_) {
      return const PropertyLocationAddress();
    }
  }

  Future<PropertyDetails> details(int propertyId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/properties/$propertyId',
      options: await _auth.optionalAuthOptions(),
    );
    return _detailsFromResponse(response);
  }

  Future<PropertySaiEnvelope> sai(int propertyId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/properties/$propertyId/sai',
      options: await _auth.optionalAuthOptions(),
    );
    return PropertySaiEnvelope.fromResponse(response.data);
  }

  Future<PropertySaiEnvelope> configureSai(
    int propertyId, {
    required String payer,
    double? brokerRatePercent,
    String? platformTermsDecision,
  }) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/properties/$propertyId/sai',
      data: <String, dynamic>{
        'sai_payer': payer,
        if (brokerRatePercent != null)
          'broker_sai_rate_percent': brokerRatePercent,
        if (platformTermsDecision != null)
          'platform_terms_decision': platformTermsDecision,
      },
      options: await _auth.requiredAuthOptions(),
    );
    return PropertySaiEnvelope.fromResponse(response.data);
  }

  Future<List<PropertyDetails>> myListings() async {
    final options = await _auth.requiredAuthOptions();
    final listings = <PropertyDetails>[];
    var page = 1;
    var lastPage = 1;

    do {
      final response = await _dio.get<Map<String, dynamic>>(
        '/properties/mine/list',
        queryParameters: {'page': page, 'per_page': 50, 'view': 'workspace'},
        options: options,
      );
      final rows =
          response.data?['data'] as List<dynamic>? ?? const <dynamic>[];
      listings.addAll(
        rows.whereType<Map<String, dynamic>>().map(PropertyDetails.fromJson),
      );

      final meta = response.data?['meta'];
      lastPage = meta is Map<String, dynamic>
          ? _positiveInt(meta['last_page'], fallback: page)
          : page;
      page++;
    } while (page <= lastPage && page <= 100);

    return List<PropertyDetails>.unmodifiable(listings);
  }

  Future<PropertyDetails> createListing(
    PropertyListingInput input, {
    List<String> imagePaths = const <String>[],
    bool submitForReview = false,
    List<String> proofPaths = const <String>[],
    String? ownerIdFrontPath,
    String? ownerIdBackPath,
    String? ownerSelfiePath,
    String? ownershipProofPath,
  }) async {
    final form = await _listingForm(
      input,
      imagePaths: imagePaths,
      submitForReview: submitForReview,
      proofPaths: proofPaths,
      ownerIdFrontPath: ownerIdFrontPath,
      ownerIdBackPath: ownerIdBackPath,
      ownerSelfiePath: ownerSelfiePath,
      ownershipProofPath: ownershipProofPath,
    );
    final response = await _dio.post<Map<String, dynamic>>(
      '/properties',
      data: form,
      options: await _listingUploadOptions(),
    );
    return _detailsFromResponse(response);
  }

  Future<PropertyDetails> updateListing(
    int propertyId,
    PropertyListingInput input, {
    List<String> imagePaths = const <String>[],
    bool replaceImages = false,
    bool submitForReview = false,
    List<String> proofPaths = const <String>[],
    String? ownerIdFrontPath,
    String? ownerIdBackPath,
    String? ownerSelfiePath,
    String? ownershipProofPath,
  }) async {
    final form = await _listingForm(
      input,
      imagePaths: imagePaths,
      submitForReview: submitForReview,
      proofPaths: proofPaths,
      replaceImages: replaceImages,
      ownerIdFrontPath: ownerIdFrontPath,
      ownerIdBackPath: ownerIdBackPath,
      ownerSelfiePath: ownerSelfiePath,
      ownershipProofPath: ownershipProofPath,
    );
    final response = await _dio.post<Map<String, dynamic>>(
      '/properties/$propertyId',
      data: form,
      options: await _listingUploadOptions(),
    );
    return _detailsFromResponse(response);
  }

  Future<void> deleteListing(int propertyId) async {
    await _dio.delete<void>(
      '/properties/$propertyId',
      options: await _auth.requiredAuthOptions(),
    );
  }

  Future<PropertyDetails> submitListing(int propertyId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/properties/$propertyId/submit',
      options: await _auth.requiredAuthOptions(),
    );
    return _detailsFromResponse(response);
  }

  Future<PropertyDetails> uploadProofDocuments(
    int propertyId,
    List<String> proofPaths,
  ) async {
    final form = FormData();
    for (final path in proofPaths.take(5)) {
      form.files.add(
        MapEntry('proof_documents[]', await MultipartFile.fromFile(path)),
      );
    }
    final response = await _dio.post<Map<String, dynamic>>(
      '/properties/$propertyId/proof-documents',
      data: form,
      options: await _listingUploadOptions(),
    );
    return _detailsFromResponse(response);
  }

  Future<Options> _listingUploadOptions() async {
    final authOptions = await _auth.requiredAuthOptions();
    return authOptions.copyWith(
      sendTimeout: const Duration(minutes: 2),
      receiveTimeout: const Duration(minutes: 2),
    );
  }

  PropertyDetails _detailsFromResponse(
      Response<Map<String, dynamic>> response) {
    final data = response.data?['data'];
    if (data is! Map<String, dynamic>) {
      throw StateError('Invalid property details response.');
    }
    return PropertyDetails.fromJson(data);
  }

  Future<FormData> _listingForm(
    PropertyListingInput input, {
    required List<String> imagePaths,
    bool submitForReview = false,
    List<String> proofPaths = const <String>[],
    bool replaceImages = false,
    String? ownerIdFrontPath,
    String? ownerIdBackPath,
    String? ownerSelfiePath,
    String? ownershipProofPath,
  }) async {
    final fields = Map<String, dynamic>.from(input.toMap());
    final parking = fields['has_parking'];
    if (parking is bool) {
      // Multipart form fields are text. Send an explicit 1/0 so a selected
      // "لا يوجد" can never be lost or interpreted as an empty value.
      fields['has_parking'] = parking ? 1 : 0;
    }
    if (submitForReview) {
      fields['submit_for_review'] = 1;
    }
    if (replaceImages) {
      fields['replace_images'] = 1;
    }

    final form = FormData.fromMap(fields);
    for (final path in imagePaths.take(12)) {
      form.files.add(
        MapEntry('images[]', await MultipartFile.fromFile(path)),
      );
    }
    for (final path in proofPaths.take(5)) {
      form.files.add(
        MapEntry('proof_documents[]', await MultipartFile.fromFile(path)),
      );
    }
    for (final entry in <String, String?>{
      'owner_id_front': ownerIdFrontPath,
      'owner_id_back': ownerIdBackPath,
      'owner_selfie': ownerSelfiePath,
      'ownership_proof': ownershipProofPath,
    }.entries) {
      final path = entry.value;
      if (path != null && path.trim().isNotEmpty) {
        form.files.add(MapEntry(entry.key, await MultipartFile.fromFile(path)));
      }
    }

    return form;
  }

  String? _firstText(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = _nullableText(source[key]);
      if (value != null) return value;
    }
    return null;
  }

  String? _nullableText(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  int _positiveInt(dynamic value, {required int fallback}) {
    final parsed =
        value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
    return parsed != null && parsed > 0 ? parsed : fallback;
  }
}

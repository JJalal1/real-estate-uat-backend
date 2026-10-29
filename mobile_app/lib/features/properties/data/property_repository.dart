import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../account/data/auth_repository.dart';
import '../domain/property_details.dart';
import '../domain/property_identity.dart';
import '../domain/property_marker.dart';
import '../domain/property_location_address.dart';
import '../domain/property_sai.dart';
import '../domain/listing_contact_policy.dart';

final propertyRepositoryProvider = Provider<PropertyRepository>((ref) {
  final repository = PropertyRepository(
    ref.watch(dioProvider),
    ref.watch(authRepositoryProvider),
  );
  ref.listen(propertyDataRevisionProvider, (_, __) => repository._invalidatePublicDiscoveryCache());
  return repository;
});

/// Incremented after a successful listing mutation so every dependent screen
/// refreshes without retaining stale family-provider results.
final propertyDataRevisionProvider = StateProvider<int>((ref) => 0);

class PropertyRepository {
  PropertyRepository(this._dio, this._auth);

  final Map<int,String> _alternateContactPhones = {};
  String? alternateContactPhone(int propertyId) => _alternateContactPhones[propertyId];
  final Dio _dio;
  final AuthRepository _auth;
  static const Duration _publicDiscoveryCacheTtl = Duration(seconds: 20);
  static const int _publicDiscoveryCacheLimit = 32;
  final Map<String, ({DateTime storedAt, Object value})> _publicDiscoveryCache = {};
  int _publicCacheEpoch = 0;

  String _publicCacheKey(String path, Map<String, dynamic> params) {
    final entries = params.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return Uri(path: path, queryParameters: {
      for (final entry in entries) entry.key: entry.value.toString(),
    }).toString();
  }

  Future<T> _cachedPublic<T>(
    String path,
    Map<String, dynamic> params,
    Future<T> Function() loader,
    {bool refresh = false, CancelToken? cancelToken}
  ) async {
    if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
    final key = _publicCacheKey(path, params);
    if (refresh) { _publicCacheEpoch++; _publicDiscoveryCache.remove(key); }
    final now = DateTime.now();
    final cached = _publicDiscoveryCache[key];
    if (cached != null && now.difference(cached.storedAt) <= _publicDiscoveryCacheTtl) {
      return cached.value as T;
    }
    if (cached != null) _publicDiscoveryCache.remove(key);

    final epoch = _publicCacheEpoch;
    final value = await loader();
    // Even an already-completed HTTP response can be superseded while being
    // decoded. Never hand it to a canceled viewport or seed a reusable cache.
    if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
    // A pre-mutation request may finish late but must never repopulate the cache.
    if (epoch != _publicCacheEpoch) return value;
    _publicDiscoveryCache[key] = (storedAt: DateTime.now(), value: value as Object);
    if (_publicDiscoveryCache.length > _publicDiscoveryCacheLimit) {
      final oldest = _publicDiscoveryCache.entries.reduce(
        (a, b) => a.value.storedAt.isBefore(b.value.storedAt) ? a : b,
      );
      _publicDiscoveryCache.remove(oldest.key);
    }
    return value;
  }

  void _invalidatePublicDiscoveryCache() {
    _publicCacheEpoch++; _publicDiscoveryCache.clear(); clearPublicDiscoveryHttpCache(_dio);
  }

  Future<(List<PropertySummary>, bool)> advertiserListings(int id, {int page = 1, String? purpose}) async {
    final response = await _dio.get<Map<String, dynamic>>('/properties', queryParameters: {'advertiser_id': id, 'page': page, 'per_page': 20, if (purpose != null) 'purpose': purpose});
    final rows = (response.data?['data'] as List? ?? const []).whereType<Map>().map((j) => PropertySummary.fromJson(Map<String, dynamic>.from(j))).toList();
    final meta = response.data?['meta'] as Map? ?? const {};
    return (rows, (meta['current_page'] as num? ?? 1) < (meta['last_page'] as num? ?? 1));
  }

  Future<void> recordView(int propertyId, String viewerKey) async {
    await _dio.post<void>('/properties/$propertyId/view', data: {'viewer_key': viewerKey}, options: await _auth.optionalAuthOptions());
  }

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
    CancelToken? cancelToken,
  }) async {
    final params = <String, dynamic>{
      'latitude': latitude,
      'longitude': longitude,
      'radius_km': radiusKm,
      if (purpose != null && purpose.isNotEmpty) 'purpose': purpose,
      if (type != null && type.isNotEmpty) 'type': type,
      if (minPrice != null) (purpose == 'rent' ? 'min_monthly_rent' : 'min_price'): minPrice,
      if (maxPrice != null) (purpose == 'rent' ? 'max_monthly_rent' : 'max_price'): maxPrice,
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
    };
    return _cachedPublic<List<PropertyMarker>>('/properties/nearby', params, () async {
      final response = await _dio.get<Map<String, dynamic>>(
        '/properties/nearby',
        queryParameters: params,
        cancelToken: cancelToken,
      );
      final rows = response.data?['data'] as List<dynamic>? ?? const <dynamic>[];
      return rows
          .whereType<Map<String, dynamic>>()
          .map(PropertyMarker.fromJson)
          .toList(growable: false);
    }, cancelToken: cancelToken);
  }

  Future<List<PropertyMarker>> nearbyFiltered(Map<String, dynamic> filters, {CancelToken? cancelToken}) async {
    final params = Map<String, dynamic>.from(filters);
    return _cachedPublic<List<PropertyMarker>>('/properties/nearby', params, () async {
      final response = await _dio.get<Map<String, dynamic>>('/properties/nearby', queryParameters: params, cancelToken: cancelToken);
      final rows = response.data?['data'] as List? ?? const [];
      return rows.whereType<Map<String, dynamic>>().map(PropertyMarker.fromJson).toList(growable: false);
    }, cancelToken: cancelToken);
  }

  Future<ListingContactPolicy> listingContactPolicy() async {
    final response = await _dio.get<Map<String,dynamic>>('/listing-access', options: await _auth.requiredAuthOptions());
    final data = response.data?['data'];
    final policy = data is Map ? data['contact_phone_policy'] : null;
    final prefixes = policy is Map ? (policy['prefixes'] as List? ?? const []).whereType<String>().where((v) => RegExp(r'^7[0-9]$').hasMatch(v)).toList() : <String>[];
    return prefixes.isEmpty ? const ListingContactPolicy() : ListingContactPolicy(prefixes: prefixes);
  }

  Future<String> contactPhone(int propertyId) async {
    final response = await _dio.get<Map<String, dynamic>>('/properties/$propertyId/contact', options: await _auth.requiredAuthOptions());
    final data = response.data?['data'];
    final phone = data is Map ? data['phone']?.toString() ?? '' : '';
    _alternateContactPhones.remove(propertyId);
    final alternate = data is Map ? data['phone_alt']?.toString() ?? '' : '';
    if (RegExp(r'^7[0-9]{8}$').hasMatch(alternate) && alternate != phone) _alternateContactPhones[propertyId] = alternate;
    if (!RegExp(r'^\+?[0-9]{7,15}$').hasMatch(phone)) throw StateError('لم يتوفر رقم اتصال صالح لهذا الإعلان.');
    return phone;
  }

  Future<PropertyLocationAddress> resolveLocationAddress({
    required double latitude, required double longitude, bool includeLandmarks = false,
  }) async {
    final key = '${latitude.toStringAsFixed(6)}:${longitude.toStringAsFixed(6)}:$includeLandmarks';
    final cached = _addressCache[key];
    if (cached != null) return cached;
    final pending = _addressRequests[key];
    if (pending != null) return pending;
    final future = _resolveAddress(latitude, longitude, includeLandmarks);
    _addressRequests[key] = future;
    try { final value = await future; if (value.isComplete && (!includeLandmarks || value.landmarks.isNotEmpty)) _addressCache[key] = value; return value; }
    finally { _addressRequests.remove(key); if (_addressCache.length > 20) _addressCache.remove(_addressCache.keys.first); }
  }
  final _addressCache = <String, PropertyLocationAddress>{};
  final _addressRequests = <String, Future<PropertyLocationAddress>>{};
  Future<PropertyLocationAddress> _resolveAddress(double latitude, double longitude, bool landmarks) async {
    final token = CancelToken();
    try {
      // Coordinates are in the HTTPS body, absent from URLs and access logs.
      // A short debounce coalesces UI requests; the shared server enforces the fleet budget.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final response = await _dio.post<Map<String, dynamic>>('/regions/reverse-address',
        data: {'latitude': latitude, 'longitude': longitude, 'include_landmarks': landmarks}, cancelToken: token,
        options: Options(sendTimeout: const Duration(seconds: 4), receiveTimeout: const Duration(seconds: 7)))
        .timeout(const Duration(seconds: 8), onTimeout: () { token.cancel('Address lookup deadline'); throw StateError('Address unavailable'); });
      final data = response.data?['data'];
      return data is Map<String, dynamic> ? PropertyLocationAddress.fromJson(data) : const PropertyLocationAddress();
    } catch (_) { return const PropertyLocationAddress(providerStatus: 'unavailable'); }
  }

  Future<PropertySaiEnvelope> saiForEditor(int propertyId) async {
    final response = await _dio.get<Map<String, dynamic>>('/properties/$propertyId/sai-management',
      options: await _auth.requiredAuthOptions());
    return PropertySaiEnvelope.fromResponse(response.data);
  }

  Future<PropertySaiManagement> saiPolicy(String purpose) async {
    final response = await _dio.get<Map<String, dynamic>>('/listing-sai-policy',
      queryParameters: {'purpose': purpose}, options: await _auth.requiredAuthOptions());
    final data = response.data?['data'];
    if (data is! Map<String, dynamic>) throw StateError('Invalid listing policy.');
    return PropertySaiManagement.fromJson(data);
  }

  Future<(List<PropertySummary>, bool)> searchListings(Map<String, dynamic> filters, {int page = 1, CancelToken? cancelToken, bool refresh = false}) async {
    if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
    final params = <String, dynamic>{...filters, 'page': page, 'per_page': 20, 'sort': 'latest'};
    return _cachedPublic<(List<PropertySummary>, bool)>('/properties', params, () async {
      final response = await _dio.get<Map<String, dynamic>>('/properties', queryParameters: params, cancelToken: cancelToken);
      final rows = (response.data?['data'] as List? ?? const []).whereType<Map>()
        .map((row) => PropertySummary.fromJson(Map<String, dynamic>.from(row))).toList(growable: false);
      final meta = response.data?['meta'] as Map? ?? const {};
      return (rows, (meta['current_page'] as num? ?? 1) < (meta['last_page'] as num? ?? 1));
    }, refresh: refresh, cancelToken: cancelToken);
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
    bool deferPlatformTerms = false,
    String amountType = 'percentage',
    double? fixedAmount,
  }) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/properties/$propertyId/sai',
      data: <String, dynamic>{
        'sai_payer': payer,
        'sai_amount_type': amountType,
        if (amountType == 'fixed' && fixedAmount != null) 'fixed_sai_amount': fixedAmount,
        if (deferPlatformTerms) 'defer_platform_terms': true,
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
    String? editorDraftKey, int? editorDraftRevision,
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
      editorDraftKey: editorDraftKey, editorDraftRevision: editorDraftRevision,
    );
    final response = await _dio.post<Map<String, dynamic>>(
      '/properties',
      data: form,
      options: await _listingUploadOptions(),
    );
    _invalidatePublicDiscoveryCache();
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
    String? editorDraftKey, int? editorDraftRevision,
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
      editorDraftKey: editorDraftKey, editorDraftRevision: editorDraftRevision,
    );
    final response = await _dio.post<Map<String, dynamic>>(
      '/properties/$propertyId',
      data: form,
      options: await _listingUploadOptions(),
    );
    _invalidatePublicDiscoveryCache();
    return _detailsFromResponse(response);
  }

  Future<void> deleteListing(int propertyId) async {
    await _dio.delete<void>(
      '/properties/$propertyId',
      options: await _auth.requiredAuthOptions(),
    );
    _invalidatePublicDiscoveryCache();
  }

  Future<PropertyIdentityResult> checkPropertyIdentity(int propertyId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/properties/$propertyId/identity/check',
      options: await _auth.requiredAuthOptions(),
    );
    final data = response.data?['data'];
    if (data is! Map<String, dynamic>) {
      throw StateError('Invalid property identity response.');
    }
    return PropertyIdentityResult.fromJson(data);
  }

  Future<PropertyIdentityResult> selfVerifyPropertyIdentity(
    int propertyId, {
    required String differenceType,
    required String differenceNote,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/properties/$propertyId/identity/self-verify',
      data: <String, dynamic>{
        'assert_different': true,
        'difference_type': differenceType,
        'difference_note': differenceNote.trim(),
      },
      options: await _auth.requiredAuthOptions(),
    );
    final data = response.data?['data'];
    if (data is! Map<String, dynamic>) {
      throw StateError('Invalid property identity response.');
    }
    return PropertyIdentityResult.fromJson(data);
  }

  Future<PropertyDetails> submitListing(int propertyId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/properties/$propertyId/submit',
      options: await _auth.requiredAuthOptions(),
    );
    _invalidatePublicDiscoveryCache();
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
    String? editorDraftKey, int? editorDraftRevision,
  }) async {
    final fields = Map<String, dynamic>.from(input.toMap());
    if (editorDraftKey != null) { fields['editor_draft_key'] = editorDraftKey; fields['editor_draft_revision'] = editorDraftRevision; }
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

    final elevator = fields['has_elevator'];
    if (elevator is bool) fields['has_elevator'] = elevator ? 1 : 0;
    final wholeFloor = fields['unit_occupies_entire_floor'];
    if (wholeFloor is bool) fields['unit_occupies_entire_floor'] = wholeFloor ? 1 : 0;
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



  int _positiveInt(dynamic value, {required int fallback}) {
    final parsed =
        value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
    return parsed != null && parsed > 0 ? parsed : fallback;
  }
}

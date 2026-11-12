import 'dart:typed_data';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/local/stage6_secure_session_store.dart';
import '../../account/data/auth_repository.dart';
import '../../account/data/auth_controller.dart';
import '../../account/data/account_request_scope.dart';
import '../domain/listing_duplicate_candidate.dart';
import '../domain/listing_review_models.dart';

final listingReviewRepositoryProvider =
    Provider<ListingReviewRepository>((ref) {
  final actor = ref.watch(authControllerProvider.select((s) => s.asData?.value?.id));
  return ListingReviewRepository(
    ref.watch(dioProvider),
    ref.watch(authRepositoryProvider), actorId: actor, currentActor: () => ref.read(authControllerProvider).asData?.value?.id,
    requestScope: ref.watch(accountRequestScopeProvider),
  );
});

class ListingReviewRepository {
  ListingReviewRepository(this._dio, this._auth, {int? actorId, int? Function()? currentActor, AccountRequestScope? requestScope}): _actorId = actorId, _currentActor = currentActor, _requestScope = requestScope;

  final Dio _dio;
  final AuthRepository _auth;
  final int? _actorId;
  final int? Function()? _currentActor;
  final AccountRequestScope? _requestScope;
  Future<Options> _sessionOptions() async {
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    if (_currentActor != null && (_actorId == null || _currentActor() != _actorId)) {
      throw StateError('ACCOUNT_CHANGED');
    }
    final options = await (_requestScope?.options() ?? _auth.requiredAuthOptions());
    _requestScope?.verify();
    if ((_currentActor != null && _currentActor() != _actorId) ||
        epoch != Stage6SecureSessionStore.instance.sessionEpoch) {
      throw StateError('ACCOUNT_CHANGED');
    }
    return options;
  }


  Future<ReviewListingPage> queue({int page = 1, int perPage = 25}) async {
    if (page < 1 || perPage < 1 || perPage > 50) {
      throw ArgumentError('Invalid listing review page.');
    }
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    final options = await _sessionOptions();
    void verifySession() {
      _requestScope?.verify();
      if ((_currentActor != null && _currentActor() != _actorId) ||
          epoch != Stage6SecureSessionStore.instance.sessionEpoch) {
        throw StateError('ACCOUNT_CHANGED');
      }
    }
    verifySession();
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/listing-review/queue',
      queryParameters: {'page': page, 'per_page': perPage},
      options: options,
    );
    verifySession();
    final rows = response.data?['data'];
    final meta = response.data?['meta'];
    if (rows is! List || meta is! Map ||
        meta['current_page'] is! int || meta['current_page'] != page ||
        meta['last_page'] is! int || (meta['last_page'] as int) < 1 ||
        meta['total'] is! int || (meta['total'] as int) < 0 ||
        rows.any((row) => row is! Map<String, dynamic>)) {
      throw StateError('Invalid listing review page response.');
    }
    return ReviewListingPage(
      items: rows.cast<Map<String, dynamic>>()
          .map(ReviewListingItem.fromJson).toList(growable: false),
      currentPage: page,
      lastPage: meta['last_page'] as int,
      total: meta['total'] as int,
    );
  }

  Future<ReviewListingDetail> detail(int id) async {
    final row = await _detailJson(id);
    return ReviewListingDetail.fromJson(row);
  }

  Future<List<ListingDuplicateCandidate>> duplicateCandidates(int id) async {
    final row = await _detailJson(id);
    final raw = row['likely_duplicate_candidates'];
    if (raw is! List) return const <ListingDuplicateCandidate>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(ListingDuplicateCandidate.fromJson)
        .toList(growable: false);
  }

  Future<(ReviewListingDetail, List<ListingDuplicateCandidate>)> evidence(int id) async {
    final row = await _detailJson(id);
    final raw = row['likely_duplicate_candidates'];
    return (ReviewListingDetail.fromJson(row), raw is List
      ? raw.whereType<Map<String, dynamic>>().map(ListingDuplicateCandidate.fromJson).toList(growable: false)
      : const <ListingDuplicateCandidate>[]);
  }

  Future<Map<String, dynamic>> _detailJson(int id) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/listing-review/listings/$id',
      options: await _sessionOptions(),
    );
    _requestScope?.verify();
    final row = response.data?['data'];
    if (row is! Map<String, dynamic>) {
      throw StateError('Invalid review detail response.');
    }
    return row;
  }

  Future<Uint8List> protectedImage(String url, {CancelToken? cancelToken}) async {
    final base=Uri.parse(_dio.options.baseUrl), target=Uri.parse(_dio.options.baseUrl).resolve(url);
    if (target.origin != base.origin || !RegExp('^${RegExp.escape(base.path)}/(?:property-media|listing-documents)/[0-9]+\$').hasMatch(target.path)) {
      throw StateError('Invalid protected image location');
    }
    final cancel=cancelToken ?? CancelToken();
    final response = await _dio.get<List<int>>(target.toString(),
      options: (await _sessionOptions()).copyWith(responseType: ResponseType.bytes), cancelToken: cancel)
      .timeout(const Duration(seconds: 25), onTimeout: () { cancel.cancel('Image deadline'); throw TimeoutException('تعذر تحميل الصورة.'); });
    _requestScope?.verify();
    final bytes=response.data;
    if (bytes==null || bytes.isEmpty || bytes.length>12*1024*1024) throw StateError('Invalid protected image response');
    return Uint8List.fromList(bytes);
  }

  Future<void> reviewMedia(int listingId, int imageId, String imageToken, String decision, String reason) async {
    final response = await _dio.post<Map<String, dynamic>>('/admin/listing-review/listings/$listingId/media-review',
      data: {'image_id': imageId, 'image_token': imageToken, 'decision': decision, 'reason': reason.trim()},
      options: await _sessionOptions());
    _requestScope?.verify();
    final data = response.data?['data'];
    if (data is! Map || data['checker'] != 'human_review' || data['decision'] != decision || data['review_id'] == null) throw StateError('Invalid media review receipt');
  }

  Future<void> start(int id) => _action(id, 'start');

  Future<void> approve(
    int id, {
    String? reason,
    String? duplicateReviewReason,
  }) async {
    await _dio.post<void>(
      '/admin/listing-review/listings/$id/approve',
      data: <String, dynamic>{
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
        if (duplicateReviewReason != null &&
            duplicateReviewReason.trim().isNotEmpty)
          'duplicate_review_reason': duplicateReviewReason.trim(),
      },
      options: await _sessionOptions(),
    );
    _requestScope?.verify();
  }

  Future<void> returnForCorrection(int id, String reason) =>
      _action(id, 'return', reason: reason);

  Future<void> rejectFinal(int id, String reason) =>
      _action(id, 'reject-final', reason: reason);

  Future<void> linkPropertyAsset(
    int listingId,
    int propertyAssetId,
    String reason,
  ) async {
    await _dio.post<void>(
      '/admin/listing-review/listings/$listingId/link-property',
      data: <String, dynamic>{
        'property_asset_id': propertyAssetId,
        'reason': reason.trim(),
      },
      options: await _sessionOptions(),
    );
    _requestScope?.verify();
  }

  Future<void> _action(int id, String action, {String? reason}) async {
    await _dio.post<void>(
      '/admin/listing-review/listings/$id/$action',
      data: reason == null ? null : <String, dynamic>{'reason': reason.trim()},
      options: await _sessionOptions(),
    );
    _requestScope?.verify();
  }

  /// Compatibility shim for the retired broker-region verification screen.
  Future<List<BrokerVerificationQueueItem>> brokerVerifications({
    String status = 'pending',
  }) async {
    return const <BrokerVerificationQueueItem>[];
  }

  Future<BrokerVerificationRecord> respondBrokerVerification(
    int verificationId,
    String status, {
    String? note,
  }) {
    throw StateError(
      'Broker region verification workflow is retired. Use support review.',
    );
  }

  Future<PublicationBlockPage> blocks({int page = 1, int perPage = 50}) async {
    if (page < 1 || perPage < 1 || perPage > 100) {
      throw ArgumentError('Invalid publication block page.');
    }
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    final options = await _sessionOptions();
    void verifySession() {
      _requestScope?.verify();
      if ((_currentActor != null && _currentActor() != _actorId) ||
          epoch != Stage6SecureSessionStore.instance.sessionEpoch) {
        throw StateError('ACCOUNT_CHANGED');
      }
    }
    verifySession();
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/listing-review/blocks',
      queryParameters: {'active': 1, 'page': page, 'per_page': perPage},
      options: options,
    );
    verifySession();
    final rows = response.data?['data'];
    final meta = response.data?['meta'];
    if (rows is! List || meta is! Map ||
        meta['current_page'] is! int || meta['current_page'] != page ||
        meta['last_page'] is! int || (meta['last_page'] as int) < 1 ||
        meta['total'] is! int || (meta['total'] as int) < 0 ||
        rows.any((row) => row is! Map<String, dynamic>)) {
      throw StateError('Invalid publication block page response.');
    }
    return PublicationBlockPage(
      items: rows.cast<Map<String, dynamic>>()
          .map(PublicationBlockItem.fromJson).toList(growable: false),
      currentPage: page,
      lastPage: meta['last_page'] as int,
      total: meta['total'] as int,
    );
  }

  Future<void> liftBlock(int id, String reason) async {
    await _dio.post<void>(
      '/admin/listing-review/blocks/$id/lift',
      data: <String, dynamic>{'reason': reason.trim()},
      options: await _sessionOptions(),
    );
    _requestScope?.verify();
  }
}

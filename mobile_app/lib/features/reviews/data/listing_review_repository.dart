import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../account/data/auth_repository.dart';
import '../domain/listing_duplicate_candidate.dart';
import '../domain/listing_review_models.dart';

final listingReviewRepositoryProvider =
    Provider<ListingReviewRepository>((ref) {
  return ListingReviewRepository(
    ref.watch(dioProvider),
    ref.watch(authRepositoryProvider),
  );
});

class ListingReviewRepository {
  ListingReviewRepository(this._dio, this._auth);

  final Dio _dio;
  final AuthRepository _auth;

  Future<List<ReviewListingItem>> queue() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/listing-review/queue',
      options: await _auth.requiredAuthOptions(),
    );
    final rows = response.data?['data'];
    if (rows is! List) return const <ReviewListingItem>[];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(ReviewListingItem.fromJson)
        .toList(growable: false);
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

  Future<Map<String, dynamic>> _detailJson(int id) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/listing-review/listings/$id',
      options: await _auth.requiredAuthOptions(),
    );
    final row = response.data?['data'];
    if (row is! Map<String, dynamic>) {
      throw StateError('Invalid review detail response.');
    }
    return row;
  }

  Future<Uint8List> protectedImage(String url) async {
    final response = await _dio.get<List<int>>(
      url,
      options: (await _auth.requiredAuthOptions()).copyWith(
        responseType: ResponseType.bytes,
      ),
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Empty protected image response.');
    }
    return Uint8List.fromList(bytes);
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
      options: await _auth.requiredAuthOptions(),
    );
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
      options: await _auth.requiredAuthOptions(),
    );
  }

  Future<void> _action(int id, String action, {String? reason}) async {
    await _dio.post<void>(
      '/admin/listing-review/listings/$id/$action',
      data: reason == null ? null : <String, dynamic>{'reason': reason.trim()},
      options: await _auth.requiredAuthOptions(),
    );
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

  Future<List<PublicationBlockItem>> blocks() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/listing-review/blocks',
      queryParameters: const <String, dynamic>{'active': 1},
      options: await _auth.requiredAuthOptions(),
    );
    final rows = response.data?['data'];
    if (rows is! List) return const <PublicationBlockItem>[];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(PublicationBlockItem.fromJson)
        .toList(growable: false);
  }

  Future<void> liftBlock(int id, String reason) async {
    await _dio.post<void>(
      '/admin/listing-review/blocks/$id/lift',
      data: <String, dynamic>{'reason': reason.trim()},
      options: await _auth.requiredAuthOptions(),
    );
  }
}

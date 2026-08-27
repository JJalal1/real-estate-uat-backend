import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../account/data/auth_repository.dart';
import '../domain/community_models.dart';

final communityRepositoryProvider = Provider<CommunityRepository>((ref) {
  return CommunityRepository(
    ref.watch(dioProvider),
    ref.watch(authRepositoryProvider),
  );
});

class CommunityRepository {
  CommunityRepository(this._dio, this._auth);

  final Dio _dio;
  final AuthRepository _auth;

  Future<List<ListingCommentItem>> comments(int propertyId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/properties/$propertyId/comments',
      options: await _auth.optionalAuthOptions(),
    );
    final rows = response.data?['data'] as List<dynamic>? ?? const <dynamic>[];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(ListingCommentItem.fromJson)
        .toList(growable: false);
  }

  Future<ListingCommentItem> addComment(int propertyId, String body) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/properties/$propertyId/comments',
      data: {'body': body.trim()},
      options: await _auth.requiredAuthOptions(),
    );
    return _comment(response.data);
  }

  Future<ListingCommentItem> updateComment(int commentId, String body) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/comments/$commentId',
      data: {'body': body.trim()},
      options: await _auth.requiredAuthOptions(),
    );
    return _comment(response.data);
  }

  Future<void> deleteComment(int commentId) async {
    await _dio.delete<void>(
      '/comments/$commentId',
      options: await _auth.requiredAuthOptions(),
    );
  }

  Future<AdvertiserRatingSummary> ratingSummary(int advertiserId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/advertisers/$advertiserId/ratings/summary',
      options: await _auth.optionalAuthOptions(),
    );
    return _ratingSummary(response.data);
  }

  Future<AdvertiserRatingSummary> rateAdvertiser({
    required int advertiserId,
    required int rating,
    required int propertyId,
    String? comment,
  }) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/advertisers/$advertiserId/rating',
      data: {
        'rating': rating,
        'property_id': propertyId,
        if (comment != null && comment.trim().isNotEmpty)
          'comment': comment.trim(),
      },
      options: await _auth.requiredAuthOptions(),
    );
    return _ratingSummary(response.data);
  }

  Future<void> deleteRating(int advertiserId) async {
    await _dio.delete<void>(
      '/advertisers/$advertiserId/rating',
      options: await _auth.requiredAuthOptions(),
    );
  }

  Future<void> report({
    required String targetType,
    required int targetId,
    required String reason,
    required String details,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/reports',
      data: {
        'target_type': targetType,
        'target_id': targetId,
        'reason': reason,
        'details': details.trim(),
      },
      options: await _auth.requiredAuthOptions(),
    );
    final data = response.data?['data'];
    if (data is! Map<String, dynamic>) {
      throw StateError('Invalid report response.');
    }
  }

  ListingCommentItem _comment(Map<String, dynamic>? body) {
    final data = body?['data'];
    if (data is! Map<String, dynamic>) {
      throw StateError('Invalid comment response.');
    }
    return ListingCommentItem.fromJson(data);
  }

  AdvertiserRatingSummary _ratingSummary(Map<String, dynamic>? body) {
    final data = body?['data'];
    if (data is! Map<String, dynamic>) {
      throw StateError('Invalid advertiser rating response.');
    }
    return AdvertiserRatingSummary.fromJson(data);
  }
}

import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../account/data/auth_repository.dart';

final aiRepositoryProvider = Provider<AiRepository>((ref) => AiRepository(ref.watch(dioProvider), ref.watch(authRepositoryProvider)));

class AiRepository {
  AiRepository(this._dio, this._auth);
  final Dio _dio;
  final AuthRepository _auth;
  final Map<String, Future<Map<String, dynamic>>> _descriptions = {};
  DateTime? descriptionRetryAt;

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> data, {bool private = false, Options? authOptions}) async {
    final auth = authOptions ?? (private ? await _auth.requiredAuthOptions() : Options());
    final response = await _dio.post<Map<String, dynamic>>(path, data: data,
      options: auth.copyWith(receiveTimeout: const Duration(seconds: 40)));
    final body = response.data?['data'];
    if (body is! Map) throw StateError('Invalid assistant response.');
    return Map<String, dynamic>.from(body);
  }

  Future<Map<String, dynamic>> refine(String message, Map<String, dynamic> filters, int revision) =>
    _post('/ai/search', {'message': message.trim(), 'filters': filters, 'revision': revision});

  Future<Map<String, dynamic>> listingFields(String message, Map<String, dynamic> facts, {int? propertyId, String? draftKey}) =>
    _post('/ai/listing-fields', {'message': message.trim(), 'facts': facts, if (propertyId != null) 'property_id': propertyId, if (draftKey != null) 'editor_draft_key': draftKey}, private: true);

  Future<Map<String, dynamic>> prepareListing(String message, Map<String, dynamic> facts, {int? propertyId, String? draftKey}) =>
    _post('/ai/listing-draft', {'mode': 'prepare', 'message': message.trim(), 'facts': facts,
      if (propertyId != null) 'property_id': propertyId, if (draftKey != null) 'editor_draft_key': draftKey}, private: true);

  Future<Map<String, dynamic>> listingCopy(Map<String, dynamic> facts, {int? propertyId, String? draftKey}) =>
    _post('/ai/listing-draft', {'mode': 'copy', 'facts': facts,
      if (propertyId != null) 'property_id': propertyId, if (draftKey != null) 'editor_draft_key': draftKey}, private: true);

  Future<Map<String, dynamic>> description(Map<String, dynamic> facts, {int? propertyId, String? draftKey, String sourceDescription = ''}) async {
    final auth = await _auth.requiredAuthOptions();
    final input = {'facts': facts, if (sourceDescription.trim().isNotEmpty) 'description': sourceDescription.trim(),
      if (propertyId != null) 'property_id': propertyId, if (draftKey != null) 'editor_draft_key': draftKey};
    // In-memory only; requests from different authenticated sessions never coalesce.
    final key = jsonEncode([auth.headers, input]);
    final pending = _descriptions[key];
    if (pending != null) return pending;
    if (descriptionRetryAt?.isAfter(DateTime.now()) == true) return Future.error(DescriptionRateLimit(descriptionRetryAt!));
    final request = _description(input, auth).whenComplete(() { _descriptions.remove(key); });
    _descriptions[key] = request;
    return request;
  }

  Future<Map<String, dynamic>> _description(Map<String, dynamic> input, Options auth) async {
    try { return await _post('/ai/listing-description', input, authOptions: auth); }
    on DioException catch (error) {
      if (error.response?.statusCode == 429) {
        final raw = error.response?.headers.value('retry-after');
        int? seconds = int.tryParse(raw ?? '');
        if (seconds == null && raw != null) {
          try { seconds = HttpDate.parse(raw).difference(DateTime.now().toUtc()).inSeconds; } catch (_) {}
        }
        final data = error.response?.data;
        if (seconds == null && data is Map && data['retry_after_seconds'] is num) seconds = (data['retry_after_seconds'] as num).toInt();
        descriptionRetryAt = DateTime.now().add(Duration(seconds: (seconds ?? 60).clamp(1, 86400).toInt()));
        throw DescriptionRateLimit(descriptionRetryAt!);
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> rentalConditions(List<Map<String, dynamic>> conditions, {int? propertyId, String? draftKey}) =>
    _post('/ai/rental-conditions', {'rental_conditions': conditions, if (propertyId != null) 'property_id': propertyId, if (draftKey != null) 'editor_draft_key': draftKey}, private: true);

  Future<Map<String, dynamic>> question(int id, String question) => _post('/properties/$id/ask', {'question': question.trim()});
}

class DescriptionRateLimit implements Exception {
  const DescriptionRateLimit(this.retryAt);
  final DateTime retryAt;
}

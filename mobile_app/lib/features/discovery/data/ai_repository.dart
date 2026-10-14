import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../account/data/auth_repository.dart';

final aiRepositoryProvider = Provider<AiRepository>((ref) => AiRepository(ref.watch(dioProvider), ref.watch(authRepositoryProvider)));

class AiRepository {
  AiRepository(this._dio, this._auth);
  final Dio _dio;
  final AuthRepository _auth;

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> data, {bool private = false}) async {
    final auth = private ? await _auth.requiredAuthOptions() : Options();
    final response = await _dio.post<Map<String, dynamic>>(path, data: data,
      options: auth.copyWith(receiveTimeout: const Duration(seconds: 40)));
    final body = response.data?['data'];
    if (body is! Map) throw StateError('Invalid assistant response.');
    return Map<String, dynamic>.from(body);
  }

  Future<Map<String, dynamic>> refine(String message, Map<String, dynamic> filters, int revision) =>
    _post('/ai/search', {'message': message.trim(), 'filters': filters, 'revision': revision});

  Future<Map<String, dynamic>> listingFields(String message, Map<String, dynamic> facts, {int? propertyId}) =>
    _post('/ai/listing-fields', {'message': message.trim(), 'facts': facts, if (propertyId != null) 'property_id': propertyId}, private: true);

  Future<Map<String, dynamic>> description(Map<String, dynamic> facts, {int? propertyId}) =>
    _post('/ai/listing-description', {'facts': facts, if (propertyId != null) 'property_id': propertyId}, private: true);

  Future<Map<String, dynamic>> question(int id, String question) => _post('/properties/$id/ask', {'question': question.trim()});
}

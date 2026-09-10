import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../account/data/auth_repository.dart';
import '../domain/general_manager_insights.dart';

final generalManagerRepositoryProvider = Provider<GeneralManagerRepository>((ref) {
  return GeneralManagerRepository(
    ref.watch(dioProvider),
    ref.watch(authRepositoryProvider),
  );
});

class GeneralManagerRepository {
  GeneralManagerRepository(this._dio, this._auth);

  final Dio _dio;
  final AuthRepository _auth;

  Future<GeneralManagerInsights> insights() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/workspace/general-manager/insights',
      options: await _auth.requiredAuthOptions(),
    );
    final data = response.data?['data'];
    if (data is! Map) {
      throw StateError('Invalid general manager insights response.');
    }
    return GeneralManagerInsights.fromJson(
      data.map((key, value) => MapEntry(key.toString(), value)),
    );
  }
}

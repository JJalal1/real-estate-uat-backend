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

  Future<List<GeneralManagerTeamMember>> team() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/workspace/general-manager/team',
      options: await _auth.requiredAuthOptions(),
    );
    final data = response.data?['data'];
    if (data is! List) return const <GeneralManagerTeamMember>[];
    return data
        .whereType<Map>()
        .map((item) => GeneralManagerTeamMember.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ))
        .toList(growable: false);
  }

  Future<List<GeneralManagerPlaceResult>> searchPlaces(String query) async {
    final q = query.trim();
    if (q.length < 2) return const <GeneralManagerPlaceResult>[];
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/workspace/general-manager/place-search',
      queryParameters: {'q': q},
      options: await _auth.requiredAuthOptions(),
    );
    final data = response.data?['data'];
    if (data is! List) return const <GeneralManagerPlaceResult>[];
    return data
        .whereType<Map>()
        .map((item) => GeneralManagerPlaceResult.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ))
        .toList(growable: false);
  }
}

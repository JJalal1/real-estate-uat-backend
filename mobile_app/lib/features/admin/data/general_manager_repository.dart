import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../account/data/account_request_scope.dart';
import '../../account/data/auth_repository.dart';
import '../../support/domain/support_workspace_models.dart';
import '../domain/general_manager_insights.dart';

final generalManagerRepositoryProvider = Provider<GeneralManagerRepository>((ref) {
  return GeneralManagerRepository(
    ref.watch(dioProvider),
    ref.watch(authRepositoryProvider),
    requestScope: ref.watch(accountRequestScopeProvider),
  );
});

class GeneralManagerRepository {
  GeneralManagerRepository(this._dio, this._auth, {AccountRequestScope? requestScope})
      : _requestScope = requestScope;

  final Dio _dio;
  final AuthRepository _auth;
  final AccountRequestScope? _requestScope;

  static const _path = '/admin/workspace/general-manager';

  Future<GeneralManagerOperations> operations(String period, {int? governorateId}) async {
    final result = await _request('GET', '$_path/operations', query: {
      'period': period,
      if (governorateId != null) 'governorate_id': governorateId,
    });
    return GeneralManagerOperations.fromJson(_map(result['data']));
  }

  Future<SupportTaskPage> decisions({int? governorateId, int page = 1}) async {
    final result = await _request('GET', '$_path/decisions', query: {
      'page': page,
      if (governorateId != null) 'governorate_id': governorateId,
    });
    final meta = _map(result['meta']);
    return SupportTaskPage(
      items: (result['data'] as List).map((row) => SupportTaskItem.fromJson(_map(row))).toList(),
      currentPage: meta['current_page'] as int,
      lastPage: meta['last_page'] as int,
      total: meta['total'] as int,
    );
  }

  Future<SupportTaskItem> decision(int id) async {
    final result = await _request('GET', '$_path/decisions/$id');
    return SupportTaskItem.fromJson(_map(result['data']));
  }

  Future<void> resolveDecision(int id, String note) async {
    await _request('POST', '$_path/decisions/$id/resolve', data: {'note': note});
  }

  Future<Map<String, dynamic>> _request(String method, String path,
      {Map<String, dynamic>? query, Object? data}) async {
    final options = await (_requestScope?.options() ?? _auth.requiredAuthOptions());
    final response = await _dio.request<Map<String, dynamic>>(
      path, queryParameters: query, data: data, options: options.copyWith(method: method),
    );
    _requestScope?.verify();
    return _map(response.data);
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is! Map) throw StateError('Invalid general manager response.');
    return Map<String, dynamic>.from(value);
  }

  Future<GeneralManagerInsights> insights() async {
    final result = await _request('GET', '$_path/insights');
    return GeneralManagerInsights.fromJson(_map(result['data']));
  }

  Future<List<GeneralManagerTeamMember>> team() async {
    final response = await _request('GET', '$_path/team');
    final data = response['data'];
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
    final response = await _request('GET', '$_path/place-search', query: {'q': q});
    final data = response['data'];
    if (data is! List) return const <GeneralManagerPlaceResult>[];
    return data
        .whereType<Map>()
        .map((item) => GeneralManagerPlaceResult.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ))
        .toList(growable: false);
  }
}

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../account/data/auth_repository.dart';
import '../domain/admin_workspace_models.dart';

final adminWorkspaceRepositoryProvider =
    Provider<AdminWorkspaceRepository>((ref) {
  return AdminWorkspaceRepository(
      ref.watch(dioProvider), ref.watch(authRepositoryProvider));
});

class AdminWorkspaceRepository {
  AdminWorkspaceRepository(this._dio, this._auth);
  final Dio _dio;
  final AuthRepository _auth;

  Future<AdminDashboardSummary> dashboard() async {
    final response = await _dio.get<Map<String, dynamic>>('/admin/dashboard',
        options: await _auth.requiredAuthOptions());
    final data = response.data?['data'];
    if (data is! Map<String, dynamic>) {
      throw StateError('Invalid admin dashboard response.');
    }
    return AdminDashboardSummary.fromJson(data);
  }

  Future<List<PlatformSettingItem>> settings() async {
    final response = await _dio.get<Map<String, dynamic>>('/admin/settings',
        options: await _auth.requiredAuthOptions());
    final rows = response.data?['data'] as List<dynamic>? ?? const [];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(PlatformSettingItem.fromJson)
        .toList(growable: false);
  }

  Future<List<PlatformSettingItem>> updateSettings(
      Map<String, dynamic> values) async {
    final response = await _dio.patch<Map<String, dynamic>>('/admin/settings',
        data: {
          'settings': values.entries
              .map((entry) => {'key': entry.key, 'value': entry.value})
              .toList(growable: false)
        },
        options: await _auth.requiredAuthOptions());
    final rows = response.data?['data'] as List<dynamic>? ?? const [];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(PlatformSettingItem.fromJson)
        .toList(growable: false);
  }
}

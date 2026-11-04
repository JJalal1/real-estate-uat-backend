import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/access_models.dart';
import 'auth_repository.dart';
import 'account_request_scope.dart';

final accessControlRepositoryProvider =
    Provider<AccessControlRepository>((ref) {
  return AccessControlRepository(
    ref.watch(dioProvider),
    ref.watch(authRepositoryProvider), requestScope: ref.watch(accountRequestScopeProvider),
  );
});

class AccessControlRepository {
  AccessControlRepository(this._dio, this._auth, {AccountRequestScope? requestScope}) : _requestScope = requestScope;
  final Dio _dio;
  final AuthRepository _auth;
  final AccountRequestScope? _requestScope;
  Future<Options> _sessionOptions() => _requestScope?.options() ?? _auth.requiredAuthOptions();

  Future<AccessCatalog> catalog() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/access/catalog',
      options: await _sessionOptions(),
    );
    _requestScope?.verify();
    final data = response.data?['data'];
    if (data is! Map<String, dynamic>) {
      throw StateError('Invalid access catalog.');
    }
    return AccessCatalog(
      roles: _mapList(data['roles'], AccessRole.fromJson),
      permissions: _mapList(data['permissions'], AccessPermission.fromJson),
    );
  }

  Future<List<AccessUserSummary>> users({String? search}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/access/users',
      queryParameters: <String, dynamic>{
        if (search != null && search.trim().isNotEmpty) 'search': search.trim()
      },
      options: await _sessionOptions(),
    );
    return _mapList(response.data?['data'], AccessUserSummary.fromJson);
  }

  Future<List<AuditEntry>> auditLogs() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/access/audit-logs?per_page=50',
      options: await _sessionOptions(),
    );
    return _mapList(response.data?['data'], AuditEntry.fromJson);
  }

  Future<void> updateStatus(int userId, String accountStatus) async {
    await _dio.patch<void>(
      '/admin/access/users/$userId/status',
      data: {'account_status': accountStatus},
      options: await _sessionOptions(),
    );
  }

  Future<void> updateRoles(int userId, List<String> roleKeys) async {
    await _dio.put<void>(
      '/admin/access/users/$userId/roles',
      data: {'role_keys': roleKeys},
      options: await _sessionOptions(),
    );
  }

  Future<void> updatePermissionOverrides(
    int userId,
    Map<String, String> effects,
  ) async {
    final overrides = effects.entries
        .where((entry) => entry.value == 'allow' || entry.value == 'deny')
        .map((entry) => {
              'permission_key': entry.key,
              'effect': entry.value,
              'reason': 'Updated from admin access control',
            })
        .toList(growable: false);
    await _dio.put<void>(
      '/admin/access/users/$userId/permission-overrides',
      data: {'overrides': overrides},
      options: await _sessionOptions(),
    );
  }

  List<T> _mapList<T>(dynamic value, T Function(Map<String, dynamic>) convert) {
    _requestScope?.verify();
    if (value is! List) {
      return <T>[];
    }
    return value
        .whereType<Map<String, dynamic>>()
        .map(convert)
        .toList(growable: false);
  }
}

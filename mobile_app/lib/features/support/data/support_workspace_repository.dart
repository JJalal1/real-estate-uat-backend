import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../account/data/auth_repository.dart';
import '../domain/support_workspace_models.dart';

final supportWorkspaceRepositoryProvider =
    Provider<SupportWorkspaceRepository>((ref) {
  return SupportWorkspaceRepository(
    ref.watch(dioProvider),
    ref.watch(authRepositoryProvider),
  );
});

class SupportWorkspaceRepository {
  SupportWorkspaceRepository(this._dio, this._auth);

  final Dio _dio;
  final AuthRepository _auth;

  Future<SupportWorkspaceDashboard> dashboard() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/workspace/dashboard',
      options: await _auth.requiredAuthOptions(),
    );
    final data = response.data?['data'];
    if (data is! Map) {
      throw StateError('Invalid workspace dashboard response.');
    }
    return SupportWorkspaceDashboard.fromJson(
      data.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  Future<List<SupportTaskItem>> tasks({
    String scope = 'inbox',
    String? type,
    String? status,
    String? priority,
    String? severity,
    int? assigneeId,
    DateTime? createdFrom,
    DateTime? createdTo,
    bool overdue = false,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/workspace/tasks',
      queryParameters: {
        'scope': scope,
        if (type != null && type.isNotEmpty) 'type': type,
        if (status != null && status.isNotEmpty) 'status': status,
        if (priority != null && priority.isNotEmpty) 'priority': priority,
        if (severity != null && severity.isNotEmpty) 'severity': severity,
        if (assigneeId != null) 'assignee_id': assigneeId,
        if (createdFrom != null) 'created_from': createdFrom.toIso8601String(),
        if (createdTo != null) 'created_to': createdTo.toIso8601String(),
        if (overdue) 'overdue': 1,
        'per_page': 100,
      },
      options: await _auth.requiredAuthOptions(),
    );
    final rows = response.data?['data'];
    if (rows is! List) return const <SupportTaskItem>[];
    return rows
        .whereType<Map>()
        .map(
          (row) => SupportTaskItem.fromJson(
            row.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList(growable: false);
  }

  Future<SupportTaskItem> claim(int taskId) =>
      _taskPost('/admin/workspace/tasks/$taskId/claim');

  Future<SupportTaskItem> assign(int taskId, int userId) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/admin/workspace/tasks/$taskId/assign',
      data: {'user_id': userId},
      options: await _auth.requiredAuthOptions(),
    );
    return _task(response.data);
  }

  Future<SupportTaskItem> classify(
    int taskId, {
    required String priority,
    String? severity,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/admin/workspace/tasks/$taskId/classification',
      data: {
        'priority': priority,
        if (severity != null) 'severity': severity,
      },
      options: await _auth.requiredAuthOptions(),
    );
    return _task(response.data);
  }

  Future<SupportTaskItem> setOperationalStatus(
    int taskId,
    String status,
  ) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/admin/workspace/tasks/$taskId/operational-status',
      data: {'status': status},
      options: await _auth.requiredAuthOptions(),
    );
    return _task(response.data);
  }

  Future<SupportTaskItem> escalate(int taskId) =>
      _taskPost('/admin/workspace/tasks/$taskId/escalate');

  Future<SupportTaskItem> reopen(int taskId) =>
      _taskPost('/admin/workspace/tasks/$taskId/reopen');

  Future<SupportTaskItem> requestDocuments(int taskId, String note) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/admin/workspace/tasks/$taskId/request-documents',
      data: {'note': note},
      options: await _auth.requiredAuthOptions(),
    );
    return _task(response.data);
  }

  Future<SupportTaskItem> rejectVerification(
    int taskId,
    String reason,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/admin/workspace/tasks/$taskId/reject-verification',
      data: {'reason': reason},
      options: await _auth.requiredAuthOptions(),
    );
    return _task(response.data);
  }

  Future<List<SupportTaskEventItem>> taskEvents(int taskId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/workspace/tasks/$taskId/events',
      options: await _auth.requiredAuthOptions(),
    );
    final rows = response.data?['data'];
    if (rows is! List) return const <SupportTaskEventItem>[];
    return rows
        .whereType<Map>()
        .map(
          (row) => SupportTaskEventItem.fromJson(
            row.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList(growable: false);
  }

  Future<List<SupportTeamMember>> team() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/workspace/team',
      options: await _auth.requiredAuthOptions(),
    );
    final rows = response.data?['data'];
    if (rows is! List) return const <SupportTeamMember>[];
    return rows
        .whereType<Map>()
        .map(
          (row) => SupportTeamMember.fromJson(
            row.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList(growable: false);
  }

  Future<SupportTaskItem> _taskPost(String path) async {
    final response = await _dio.post<Map<String, dynamic>>(
      path,
      options: await _auth.requiredAuthOptions(),
    );
    return _task(response.data);
  }

  SupportTaskItem _task(Map<String, dynamic>? body) {
    final data = body?['data'];
    if (data is! Map) throw StateError('Invalid support task response.');
    return SupportTaskItem.fromJson(
      data.map((key, value) => MapEntry(key.toString(), value)),
    );
  }
}

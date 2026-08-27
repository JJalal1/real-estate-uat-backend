import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../account/data/auth_repository.dart';
import '../domain/support_models.dart';

final supportRepositoryProvider = Provider<SupportRepository>((ref) {
  return SupportRepository(
    ref.watch(dioProvider),
    ref.watch(authRepositoryProvider),
  );
});

class SupportRepository {
  SupportRepository(this._dio, this._auth);

  final Dio _dio;
  final AuthRepository _auth;

  Future<List<SupportCaseSummary>> mine() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/support/cases/mine',
      options: await _auth.requiredAuthOptions(),
    );
    return _summaries(response.data);
  }

  Future<SupportCaseDetails> openTicket({
    required String subject,
    required String description,
    String category = 'other',
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/support/cases',
      data: {
        'subject': subject.trim(),
        'description': description.trim(),
        'category': category,
      },
      options: await _auth.requiredAuthOptions(),
    );
    return _details(response.data);
  }

  Future<SupportCaseDetails> details(int caseId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/support/cases/$caseId',
      options: await _auth.requiredAuthOptions(),
    );
    return _details(response.data);
  }

  Future<SupportCaseDetails> reply(int caseId, String body) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/support/cases/$caseId/messages',
      data: {'body': body.trim()},
      options: await _auth.requiredAuthOptions(),
    );
    return _details(response.data);
  }

  Future<SupportAdminSummary> adminSummary() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/support/summary',
      options: await _auth.requiredAuthOptions(),
    );
    final data = response.data?['data'];
    if (data is! Map<String, dynamic>) {
      throw StateError('Invalid support summary response.');
    }
    return SupportAdminSummary.fromJson(data);
  }

  Future<List<SupportCaseSummary>> adminCases({
    String? kind,
    String? status,
    bool? escalated,
    bool assignedToMe = false,
    int? assignedToUserId,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/support/cases',
      queryParameters: {
        if (kind != null && kind.isNotEmpty) 'kind': kind,
        if (status != null && status.isNotEmpty) 'status': status,
        if (escalated != null) 'escalated': escalated ? 1 : 0,
        if (assignedToMe) 'assigned_to_me': 1,
        if (assignedToUserId != null) 'assigned_to_user_id': assignedToUserId,
      },
      options: await _auth.requiredAuthOptions(),
    );
    return _summaries(response.data);
  }

  Future<SupportCaseDetails> adminDetails(int caseId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/support/cases/$caseId',
      options: await _auth.requiredAuthOptions(),
    );
    return _details(response.data);
  }

  Future<SupportCaseDetails> start(int caseId) =>
      _casePost('/admin/support/cases/$caseId/start');

  Future<SupportCaseDetails> adminReply(int caseId, String body) =>
      _casePost('/admin/support/cases/$caseId/reply',
          data: {'body': body.trim()});

  Future<SupportCaseDetails> internalNote(int caseId, String body) =>
      _casePost('/admin/support/cases/$caseId/note',
          data: {'body': body.trim()});

  Future<SupportCaseDetails> setStatus(int caseId, String status) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/admin/support/cases/$caseId/status',
      data: {'status': status},
      options: await _auth.requiredAuthOptions(),
    );
    return _details(response.data);
  }

  Future<SupportCaseDetails> assign(int caseId, int userId) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/admin/support/cases/$caseId/assign',
      data: {'user_id': userId},
      options: await _auth.requiredAuthOptions(),
    );
    return _details(response.data);
  }

  Future<SupportCaseDetails> reopen(int caseId, String reason) =>
      _casePost('/admin/support/cases/$caseId/reopen',
          data: {'reason': reason.trim()});

  Future<SupportCaseDetails> escalate(int caseId, String reason) =>
      _casePost('/admin/support/cases/$caseId/escalate',
          data: {'reason': reason.trim()});

  Future<List<SupportAgentItem>> agents() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/support/agents',
      options: await _auth.requiredAuthOptions(),
    );
    final rows = response.data?['data'] as List<dynamic>? ?? const [];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(SupportAgentItem.fromJson)
        .toList(growable: false);
  }

  Future<SupportUserContext> userContext(int userId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/support/users/$userId',
      options: await _auth.requiredAuthOptions(),
    );
    final data = response.data?['data'];
    if (data is! Map<String, dynamic>) {
      throw StateError('Invalid support user response.');
    }
    return SupportUserContext.fromJson(data);
  }

  Future<List<SupportWorkLogItem>> worklog({int? userId, int days = 14}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/support/worklog',
      queryParameters: {
        if (userId != null) 'user_id': userId,
        'days': days,
      },
      options: await _auth.requiredAuthOptions(),
    );
    final rows = response.data?['data'] as List<dynamic>? ?? const [];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(SupportWorkLogItem.fromJson)
        .toList(growable: false);
  }

  Future<void> hideComment(int commentId, String reason) =>
      _moderate('/admin/community/comments/$commentId/hide', reason);
  Future<void> hideRating(int ratingId, String reason) =>
      _moderate('/admin/community/ratings/$ratingId/hide', reason);

  Future<int> escalateOverdue() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/admin/support/escalate-overdue',
      options: await _auth.requiredAuthOptions(),
    );
    final data = response.data?['data'];
    if (data is Map<String, dynamic>) {
      final raw = data['escalated_count'];
      if (raw is num) return raw.toInt();
      return int.tryParse(raw?.toString() ?? '') ?? 0;
    }
    return 0;
  }

  Future<SupportCaseDetails> _casePost(String path,
      {Map<String, dynamic>? data}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      path,
      data: data,
      options: await _auth.requiredAuthOptions(),
    );
    return _details(response.data);
  }

  Future<void> _moderate(String path, String reason) async {
    await _dio.post<void>(
      path,
      data: {'reason': reason.trim()},
      options: await _auth.requiredAuthOptions(),
    );
  }

  List<SupportCaseSummary> _summaries(Map<String, dynamic>? body) {
    final rows = body?['data'] as List<dynamic>? ?? const <dynamic>[];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(SupportCaseSummary.fromJson)
        .toList(growable: false);
  }

  SupportCaseDetails _details(Map<String, dynamic>? body) {
    final data = body?['data'];
    if (data is! Map<String, dynamic>) {
      throw StateError('Invalid support case response.');
    }
    return SupportCaseDetails.fromJson(data);
  }
}

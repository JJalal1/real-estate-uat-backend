import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../account/data/auth_repository.dart';
import '../domain/message_models.dart';

final messageDataRevisionProvider = StateProvider<int>((ref) => 0);

final messageRepositoryProvider = Provider<MessageRepository>((ref) {
  return MessageRepository(
      ref.watch(dioProvider), ref.watch(authRepositoryProvider));
});

class MessageRepository {
  MessageRepository(this._dio, this._auth);
  final Dio _dio;
  final AuthRepository _auth;

  Future<List<MessageThreadSummary>> threads() async {
    final response = await _dio.get<Map<String, dynamic>>('/messages/threads',
        options: await _auth.requiredAuthOptions());
    return _list(response.data)
        .map(MessageThreadSummary.fromJson)
        .toList(growable: false);
  }

  Future<MessageThreadSummary> startForProperty(int propertyId) async {
    final response = await _dio.post<Map<String, dynamic>>(
        '/properties/$propertyId/conversation',
        options: await _auth.requiredAuthOptions());
    return MessageThreadSummary.fromJson(_dataMap(response.data));
  }

  Future<MessageThreadDetails> details(int threadId) async {
    final response = await _dio.get<Map<String, dynamic>>(
        '/messages/threads/$threadId',
        options: await _auth.requiredAuthOptions());
    return MessageThreadDetails.fromJson(_dataMap(response.data));
  }

  Future<PrivateMessageItem> send(int threadId, String body) async {
    final response = await _dio.post<Map<String, dynamic>>(
        '/messages/threads/$threadId/messages',
        data: {'body': body.trim()},
        options: await _auth.requiredAuthOptions());
    return PrivateMessageItem.fromJson(_dataMap(response.data));
  }

  Future<void> markRead(int threadId) async {
    await _dio.post<void>('/messages/threads/$threadId/read',
        options: await _auth.requiredAuthOptions());
  }

  Future<void> report(int threadId,
      {required String reason, required String details}) async {
    final response = await _dio.post<Map<String, dynamic>>(
        '/messages/threads/$threadId/report',
        data: {'reason': reason, 'details': details.trim()},
        options: await _auth.requiredAuthOptions());
    final data = response.data?['data'];
    if (data is! Map<String, dynamic>) {
      throw StateError('Invalid conversation report response.');
    }
  }

  Future<List<AppNotificationItem>> notifications() async {
    final response = await _dio.get<Map<String, dynamic>>('/notifications',
        options: await _auth.requiredAuthOptions());
    return _list(response.data)
        .map(AppNotificationItem.fromJson)
        .toList(growable: false);
  }

  Future<int> unreadNotificationCount() async {
    final response = await _dio.get<Map<String, dynamic>>(
        '/notifications/unread-count',
        options: await _auth.requiredAuthOptions());
    final data = _dataMap(response.data);
    final raw = data['count'];
    return raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  Future<void> readNotification(int id) async {
    await _dio.post<void>('/notifications/$id/read',
        options: await _auth.requiredAuthOptions());
  }

  Future<void> readAllNotifications() async {
    await _dio.post<void>('/notifications/read-all',
        options: await _auth.requiredAuthOptions());
  }

  Future<List<ConversationReportSummary>> adminReports({String? status}) async {
    final response = await _dio.get<Map<String, dynamic>>(
        '/admin/messages/reports',
        queryParameters: {
          if (status != null && status.isNotEmpty) 'status': status
        },
        options: await _auth.requiredAuthOptions());
    return _list(response.data)
        .map(ConversationReportSummary.fromJson)
        .toList(growable: false);
  }

  Future<ReportedConversationContent> openReportedContent(int reportId) async {
    final response = await _dio.get<Map<String, dynamic>>(
        '/admin/messages/reports/$reportId/content',
        options: await _auth.requiredAuthOptions());
    return ReportedConversationContent.fromJson(_dataMap(response.data));
  }

  Future<ConversationReportSummary> resolveReport(int reportId,
      {required String status, required String note}) async {
    final response = await _dio.patch<Map<String, dynamic>>(
        '/admin/messages/reports/$reportId/resolve',
        data: {'status': status, 'resolution_note': note.trim()},
        options: await _auth.requiredAuthOptions());
    return ConversationReportSummary.fromJson(_dataMap(response.data));
  }

  List<Map<String, dynamic>> _list(Map<String, dynamic>? body) {
    final rows = body?['data'] as List<dynamic>? ?? const <dynamic>[];
    return rows.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  Map<String, dynamic> _dataMap(Map<String, dynamic>? body) {
    final data = body?['data'];
    if (data is! Map<String, dynamic>) {
      throw StateError('Invalid messaging response.');
    }
    return data;
  }
}

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/local/stage6_secure_session_store.dart';
import '../../account/data/auth_repository.dart';
import '../../account/data/auth_controller.dart';
import '../../account/data/account_request_scope.dart';
import '../domain/message_models.dart';

final messageDataRevisionProvider = StateProvider<int>((ref) => 0);

final messageRepositoryProvider = Provider<MessageRepository>((ref) {
  final actor = ref.watch(authControllerProvider.select((s) => s.asData?.value?.id));
  return MessageRepository(
      ref.watch(dioProvider), ref.watch(authRepositoryProvider), requestScope: ref.watch(accountRequestScopeProvider), actorId: actor, currentActor: () => ref.read(authControllerProvider).asData?.value?.id);
});

class MessageRepository {
  MessageRepository(this._dio, this._auth, {int? actorId, int? Function()? currentActor, AccountRequestScope? requestScope})
    : _actorId = actorId, _currentActor = currentActor, _requestScope = requestScope;
  final Dio _dio;
  final AuthRepository _auth;
  final int? _actorId;
  final AccountRequestScope? _requestScope;
  final int? Function()? _currentActor;
  Future<Options> _sessionOptions() async {
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    _requestScope?.verify();
    if (_currentActor != null && (_actorId == null || _currentActor() != _actorId)) throw StateError('ACCOUNT_CHANGED');
    final options = await (_requestScope?.options() ?? _auth.requiredAuthOptions());
    _requestScope?.verify();
    if (epoch != Stage6SecureSessionStore.instance.sessionEpoch) throw StateError('ACCOUNT_CHANGED');
    if (_currentActor != null && _currentActor() != _actorId) throw StateError('ACCOUNT_CHANGED');
    return options;
  }


  Future<List<MessageThreadSummary>> threads() async {
    final response = await _dio.get<Map<String, dynamic>>('/messages/threads',
        options: await _sessionOptions());
    return _list(response.data)
        .map(MessageThreadSummary.fromJson)
        .toList(growable: false);
  }

  Future<MessageThreadPage> threadsPage({int page = 1, int perPage = 40,
      bool unreadOnly = false}) async {
    return _inboxPage('/messages/threads', MessageThreadSummary.fromJson,
      page: page, perPage: perPage, maxPerPage: 250,
      filters: {if (unreadOnly) 'unread_only': 1});
  }

  Future<NotificationPage> notificationsPage({int page = 1, int perPage = 40}) =>
      _inboxPage('/notifications', AppNotificationItem.fromJson,
        page: page, perPage: perPage, maxPerPage: 200);

  Future<ConversationReportPage> adminReportsPage({int page = 1,
      int perPage = 40, String? status}) =>
      _inboxPage('/admin/messages/reports', ConversationReportSummary.fromJson,
        page: page, perPage: perPage, maxPerPage: 200,
        filters: {if (status != null && status.isNotEmpty) 'status': status});

  Future<MessageInboxPage<T>> _inboxPage<T>(String path,
      T Function(Map<String, dynamic>) decode, {required int page,
      required int perPage, required int maxPerPage,
      Map<String, Object> filters = const {}}) async {
    if (page < 1 || perPage < 1 || perPage > maxPerPage) {
      throw ArgumentError('Invalid private inbox page.');
    }
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    void verifySession() {
      _requestScope?.verify();
      if ((_currentActor != null &&
          (_actorId == null || _currentActor() != _actorId)) ||
          epoch != Stage6SecureSessionStore.instance.sessionEpoch) {
        throw StateError('ACCOUNT_CHANGED');
      }
    }
    verifySession();
    final options = await _sessionOptions();
    verifySession();
    final response = await _dio.get<Map<String, dynamic>>(path,
      queryParameters: {'page': page, 'per_page': perPage, ...filters}, options: options);
    verifySession();
    final rows = response.data?['data'];
    final meta = response.data?['meta'];
    if (rows is! List || meta is! Map ||
        meta['current_page'] is! int || meta['current_page'] != page ||
        meta['last_page'] is! int || (meta['last_page'] as int) < 1 ||
        meta['total'] is! int || (meta['total'] as int) < 0 ||
        rows.any((row) => row is! Map<String, dynamic>)) {
      throw StateError('Invalid private inbox page response.');
    }
    return MessageInboxPage<T>(
      items: rows.cast<Map<String, dynamic>>().map(decode).toList(growable: false),
      currentPage: meta['current_page'] as int,
      lastPage: meta['last_page'] as int,
      total: meta['total'] as int,
    );
  }

  Future<MessageThreadSummary> startForProperty(int propertyId) async {
    final response = await _dio.post<Map<String, dynamic>>(
        '/properties/$propertyId/conversation',
        options: await _sessionOptions());
    return MessageThreadSummary.fromJson(_dataMap(response.data));
  }

  Future<MessageThreadSummary> startForBroker(int brokerId) async {
    final response=await _dio.post<Map<String,dynamic>>('/brokers/$brokerId/conversation',options:await _sessionOptions());
    return MessageThreadSummary.fromJson(_dataMap(response.data));
  }

  Future<MessageThreadDetails> details(int threadId, {int? beforeId}) async {
    final response = await _dio.get<Map<String, dynamic>>(
        '/messages/threads/$threadId',
        queryParameters: {if (beforeId != null) 'before_id': beforeId},
        options: await _sessionOptions());
    return MessageThreadDetails.fromJson(_dataMap(response.data));
  }

  Future<PrivateMessageItem> send(int threadId, String body,
      {String? clientMessageId}) async {
    final response = await _dio.post<Map<String, dynamic>>(
        '/messages/threads/$threadId/messages',
        data: {
          'body': body.trim(),
          if (clientMessageId != null) 'client_message_id': clientMessageId,
        },
        options: await _sessionOptions());
    return PrivateMessageItem.fromJson(_dataMap(response.data));
  }


  Future<ExternalCallStart> startExternalCall(int threadId) async {
    final response = await _dio.post<Map<String, dynamic>>(
        '/messages/threads/$threadId/external-call',
        options: await _sessionOptions());
    return ExternalCallStart.fromJson(_dataMap(response.data));
  }

  Future<void> markRead(int threadId) async {
    await _dio.post<void>('/messages/threads/$threadId/read',
        options: await _sessionOptions());
    _requestScope?.verify();
  }

  Future<void> report(int threadId,
      {required String reason, required String details}) async {
    final response = await _dio.post<Map<String, dynamic>>(
        '/messages/threads/$threadId/report',
        data: {'reason': reason, 'details': details.trim()},
        options: await _sessionOptions());
    _requestScope?.verify();
    final data = response.data?['data'];
    if (data is! Map<String, dynamic>) {
      throw StateError('Invalid conversation report response.');
    }
  }

  Future<List<AppNotificationItem>> notifications() async {
    final response = await _dio.get<Map<String, dynamic>>('/notifications',
        options: await _sessionOptions());
    return _list(response.data)
        .map(AppNotificationItem.fromJson)
        .toList(growable: false);
  }

  Future<int> unreadNotificationCount() async {
    final response = await _dio.get<Map<String, dynamic>>(
        '/notifications/unread-count',
        options: await _sessionOptions());
    final data = _dataMap(response.data);
    final raw = data['count'];
    return raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  Future<void> readNotification(int id) async {
    await _dio.post<void>('/notifications/$id/read',
        options: await _sessionOptions());
    _requestScope?.verify();
  }

  Future<void> readAllNotifications() async {
    await _dio.post<void>('/notifications/read-all',
        options: await _sessionOptions());
    _requestScope?.verify();
  }

  Future<List<ConversationReportSummary>> adminReports({String? status}) async {
    final response = await _dio.get<Map<String, dynamic>>(
        '/admin/messages/reports',
        queryParameters: {
          if (status != null && status.isNotEmpty) 'status': status
        },
        options: await _sessionOptions());
    return _list(response.data)
        .map(ConversationReportSummary.fromJson)
        .toList(growable: false);
  }

  Future<ReportedConversationContent> openReportedContent(int reportId) async {
    final response = await _dio.get<Map<String, dynamic>>(
        '/admin/messages/reports/$reportId/content',
        options: await _sessionOptions());
    return ReportedConversationContent.fromJson(_dataMap(response.data));
  }

  Future<ConversationReportSummary> resolveReport(int reportId,
      {required String status, required String note}) async {
    final response = await _dio.patch<Map<String, dynamic>>(
        '/admin/messages/reports/$reportId/resolve',
        data: {'status': status, 'resolution_note': note.trim()},
        options: await _sessionOptions());
    return ConversationReportSummary.fromJson(_dataMap(response.data));
  }

  List<Map<String, dynamic>> _list(Map<String, dynamic>? body) {
    _requestScope?.verify();
    final rows = body?['data'] as List<dynamic>? ?? const <dynamic>[];
    return rows.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  Map<String, dynamic> _dataMap(Map<String, dynamic>? body) {
    _requestScope?.verify();
    final data = body?['data'];
    if (data is! Map<String, dynamic>) {
      throw StateError('Invalid messaging response.');
    }
    return data;
  }
}

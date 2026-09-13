class MessageThreadSummary {
  const MessageThreadSummary({
    required this.id,
    required this.otherUserId,
    required this.otherUserName,
    required this.unreadCount,
    this.propertyId,
    this.propertyTitle,
    this.propertyStatus,
    this.lastMessagePreview,
    this.lastMessageAt,
  });

  final int id;
  final int otherUserId;
  final String otherUserName;
  final int unreadCount;
  final int? propertyId;
  final String? propertyTitle;
  final String? propertyStatus;
  final String? lastMessagePreview;
  final DateTime? lastMessageAt;

  bool get isPropertyUnavailable =>
      propertyId != null && propertyStatus != null && propertyStatus != 'published';

  factory MessageThreadSummary.fromJson(Map<String, dynamic> json) {
    final other = json['other_user'];
    final otherMap =
        other is Map<String, dynamic> ? other : const <String, dynamic>{};
    return MessageThreadSummary(
      id: _asInt(json['id']) ?? 0,
      otherUserId: _asInt(otherMap['id']) ?? 0,
      otherUserName: otherMap['name']?.toString() ?? 'مستخدم',
      unreadCount: _asInt(json['unread_count']) ?? 0,
      propertyId: _asInt(json['property_id']),
      propertyTitle: _nullable(json['property_title']),
      propertyStatus: _nullable(json['property_status']),
      lastMessagePreview: _nullable(json['last_message_preview']),
      lastMessageAt: _date(json['last_message_at']),
    );
  }
}

class PrivateMessageItem {
  const PrivateMessageItem({
    required this.id,
    required this.senderUserId,
    required this.senderName,
    required this.body,
    required this.isMine,
    this.clientMessageId,
    this.createdAt,
  });

  final int id;
  final int senderUserId;
  final String senderName;
  final String body;
  final bool isMine;
  final String? clientMessageId;
  final DateTime? createdAt;

  factory PrivateMessageItem.fromJson(Map<String, dynamic> json) {
    return PrivateMessageItem(
      id: _asInt(json['id']) ?? 0,
      senderUserId: _asInt(json['sender_user_id']) ?? 0,
      senderName: json['sender_name']?.toString() ?? 'مستخدم',
      body: json['body']?.toString() ?? '',
      isMine: json['is_mine'] == true || json['is_mine'] == 1,
      clientMessageId: _nullable(json['client_message_id']),
      createdAt: _date(json['created_at']),
    );
  }
}

class MessageThreadDetails {
  const MessageThreadDetails({
    required this.thread,
    required this.messages,
    this.hasMore = false,
    this.nextBeforeId,
  });

  final MessageThreadSummary thread;
  final List<PrivateMessageItem> messages;
  final bool hasMore;
  final int? nextBeforeId;

  factory MessageThreadDetails.fromJson(Map<String, dynamic> json) {
    final threadJson = json['thread'];
    final rows = json['messages'] as List<dynamic>? ?? const <dynamic>[];
    final pagination = json['pagination'];
    final paginationMap = pagination is Map<String, dynamic>
        ? pagination
        : const <String, dynamic>{};
    if (threadJson is! Map<String, dynamic>) {
      throw StateError('Invalid message thread response.');
    }
    return MessageThreadDetails(
      thread: MessageThreadSummary.fromJson(threadJson),
      messages: rows
          .whereType<Map<String, dynamic>>()
          .map(PrivateMessageItem.fromJson)
          .toList(growable: false),
      hasMore: paginationMap['has_more'] == true,
      nextBeforeId: _asInt(paginationMap['next_before_id']),
    );
  }
}

class AppNotificationItem {
  const AppNotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.isRead,
    this.body,
    this.entityType,
    this.entityId,
    this.data = const <String, dynamic>{},
    this.createdAt,
  });

  final int id;
  final String type;
  final String title;
  final String? body;
  final String? entityType;
  final int? entityId;
  final Map<String, dynamic> data;
  final bool isRead;
  final DateTime? createdAt;

  int? get bookingId => _asInt(data['booking_id']);
  int? get messageThreadId => _asInt(data['message_thread_id']);
  int? get agreementId => _asInt(data['agreement_id']);
  int? get rentalContractId => _asInt(data['rental_contract_id']);

  factory AppNotificationItem.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    final data = rawData is Map<String, dynamic>
        ? rawData
        : rawData is Map
            ? Map<String, dynamic>.from(rawData)
            : const <String, dynamic>{};
    return AppNotificationItem(
      id: _asInt(json['id']) ?? 0,
      type: json['type']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      body: _nullable(json['body']),
      entityType: _nullable(json['entity_type']),
      entityId: _asInt(json['entity_id']),
      data: data,
      isRead: json['read_at'] != null,
      createdAt: _date(json['created_at']),
    );
  }
}

class ConversationReportSummary {
  const ConversationReportSummary({
    required this.id,
    required this.threadId,
    required this.reporterName,
    required this.reasonCode,
    required this.status,
    this.supportCaseId,
    this.propertyTitle,
    this.createdAt,
  });

  final int id;
  final int threadId;
  final int? supportCaseId;
  final String reporterName;
  final String reasonCode;
  final String status;
  final String? propertyTitle;
  final DateTime? createdAt;

  factory ConversationReportSummary.fromJson(Map<String, dynamic> json) {
    return ConversationReportSummary(
      id: _asInt(json['id']) ?? 0,
      threadId: _asInt(json['thread_id']) ?? 0,
      supportCaseId: _asInt(json['support_case_id']),
      reporterName: json['reporter_name']?.toString() ?? 'مستخدم',
      reasonCode: json['reason_code']?.toString() ?? 'other',
      status: json['status']?.toString() ?? 'open',
      propertyTitle: _nullable(json['property_title']),
      createdAt: _date(json['created_at']),
    );
  }
}

class ReportedConversationContent {
  const ReportedConversationContent(
      {required this.report, required this.messages});
  final ConversationReportSummary report;
  final List<PrivateMessageItem> messages;

  factory ReportedConversationContent.fromJson(Map<String, dynamic> json) {
    final reportJson = json['report'];
    final rows = json['messages'] as List<dynamic>? ?? const <dynamic>[];
    if (reportJson is! Map<String, dynamic>) {
      throw StateError('Invalid reported conversation response.');
    }
    return ReportedConversationContent(
      report: ConversationReportSummary.fromJson(reportJson),
      messages: rows.whereType<Map<String, dynamic>>().map((row) {
        return PrivateMessageItem(
          id: _asInt(row['id']) ?? 0,
          senderUserId: _asInt(row['sender_user_id']) ?? 0,
          senderName: row['sender_name']?.toString() ?? 'مستخدم',
          body: row['body']?.toString() ?? '',
          isMine: false,
          createdAt: _date(row['created_at']),
        );
      }).toList(growable: false),
    );
  }
}

int? _asInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}

String? _nullable(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

DateTime? _date(dynamic value) {
  final text = value?.toString();
  return text == null ? null : DateTime.tryParse(text);
}

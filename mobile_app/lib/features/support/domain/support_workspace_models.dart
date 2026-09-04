class SupportTaskItem {
  const SupportTaskItem({
    required this.id,
    required this.sourceType,
    required this.sourceId,
    required this.subject,
    required this.status,
    required this.priority,
    required this.isMine,
    required this.canClaim,
    required this.isOverdue,
    this.sourceReference,
    this.requesterUserId,
    this.requesterName,
    this.severity,
    this.assignedToUserId,
    this.assignedToName,
    this.createdAt,
    this.claimedAt,
    this.lastActivityAt,
    this.slaDueAt,
    this.remainingMinutes,
    this.metadata = const <String, dynamic>{},
  });

  final int id;
  final String sourceType;
  final int sourceId;
  final String? sourceReference;
  final String subject;
  final int? requesterUserId;
  final String? requesterName;
  final String status;
  final String priority;
  final String? severity;
  final int? assignedToUserId;
  final String? assignedToName;
  final DateTime? createdAt;
  final DateTime? claimedAt;
  final DateTime? lastActivityAt;
  final DateTime? slaDueAt;
  final int? remainingMinutes;
  final bool isMine;
  final bool canClaim;
  final bool isOverdue;
  final Map<String, dynamic> metadata;

  bool get isClosed => status == 'completed' || status == 'rejected';

  factory SupportTaskItem.fromJson(Map<String, dynamic> json) {
    return SupportTaskItem(
      id: _int(json['id']),
      sourceType: json['source_type']?.toString() ?? '',
      sourceId: _int(json['source_id']),
      sourceReference: _text(json['source_reference']),
      subject: json['subject']?.toString() ?? '',
      requesterUserId: _nullableInt(json['requester_user_id']),
      requesterName: _text(json['requester_name']),
      status: json['status']?.toString() ?? 'new',
      priority: json['priority']?.toString() ?? 'normal',
      severity: _text(json['severity']),
      assignedToUserId: _nullableInt(json['assigned_to_user_id']),
      assignedToName: _text(json['assigned_to_name']),
      createdAt: _date(json['created_at']),
      claimedAt: _date(json['claimed_at']),
      lastActivityAt: _date(json['last_activity_at']),
      slaDueAt: _date(json['sla_due_at']),
      remainingMinutes: json['remaining_minutes'] == null
          ? null
          : _int(json['remaining_minutes']),
      isMine: json['is_mine'] == true,
      canClaim: json['can_claim'] == true,
      isOverdue: json['is_overdue'] == true,
      metadata: json['metadata'] is Map
          ? (json['metadata'] as Map).map(
              (key, value) => MapEntry(key.toString(), value),
            )
          : const <String, dynamic>{},
    );
  }
}

class SupportTeamMember {
  const SupportTeamMember({
    required this.id,
    required this.name,
    required this.role,
    required this.openTasks,
    required this.closedTasks,
    required this.overdueTasks,
    required this.urgentTasks,
    required this.tickets,
    required this.verifications,
    required this.listingReviews,
    required this.reports,
    this.averageClaimMinutes,
    this.averageResponseMinutes,
    this.lastActivityAt,
  });

  final int id;
  final String name;
  final String role;
  final int openTasks;
  final int closedTasks;
  final int overdueTasks;
  final int urgentTasks;
  final int tickets;
  final int verifications;
  final int listingReviews;
  final int reports;
  final int? averageClaimMinutes;
  final int? averageResponseMinutes;
  final DateTime? lastActivityAt;

  factory SupportTeamMember.fromJson(Map<String, dynamic> json) {
    return SupportTeamMember(
      id: _int(json['id']),
      name: json['name']?.toString() ?? '',
      role: json['role']?.toString() ?? 'support_agent',
      openTasks: _int(json['open_tasks']),
      closedTasks: _int(json['closed_tasks']),
      overdueTasks: _int(json['overdue_tasks']),
      urgentTasks: _int(json['urgent_tasks']),
      tickets: _int(json['tickets']),
      verifications: _int(json['verifications']),
      listingReviews: _int(json['listing_reviews']),
      reports: _int(json['reports']),
      averageClaimMinutes: json['average_claim_minutes'] == null
          ? null
          : _int(json['average_claim_minutes']),
      averageResponseMinutes: json['average_response_minutes'] == null
          ? null
          : _int(json['average_response_minutes']),
      lastActivityAt: _date(json['last_activity_at']),
    );
  }
}

class SupportTaskEventItem {
  const SupportTaskEventItem({
    required this.id,
    required this.event,
    this.fromStatus,
    this.toStatus,
    this.actorName,
    this.createdAt,
    this.metadata = const <String, dynamic>{},
  });

  final int id;
  final String event;
  final String? fromStatus;
  final String? toStatus;
  final String? actorName;
  final DateTime? createdAt;
  final Map<String, dynamic> metadata;

  factory SupportTaskEventItem.fromJson(Map<String, dynamic> json) =>
      SupportTaskEventItem(
        id: _int(json['id']),
        event: json['event']?.toString() ?? '',
        fromStatus: _text(json['from_status']),
        toStatus: _text(json['to_status']),
        actorName: _text(json['actor_name']),
        createdAt: _date(json['created_at']),
        metadata: json['metadata'] is Map
            ? (json['metadata'] as Map).map(
                (key, value) => MapEntry(key.toString(), value),
              )
            : const <String, dynamic>{},
      );
}

class SupportWorkspaceDashboard {
  const SupportWorkspaceDashboard(this.values);

  final Map<String, dynamic> values;

  String get mode => values['mode']?.toString() ?? '';
  int count(String key) => _int(values[key]);
  int? optionalInt(String key) =>
      values[key] == null ? null : _int(values[key]);

  Map<String, dynamic> get today {
    final raw = values['today'];
    if (raw is! Map) return const <String, dynamic>{};
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }

  List<SupportTaskItem> get attention {
    final rows = values['attention'];
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

  factory SupportWorkspaceDashboard.fromJson(Map<String, dynamic> json) =>
      SupportWorkspaceDashboard(json);
}

int _int(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _nullableInt(dynamic value) {
  if (value == null) return null;
  final parsed = _int(value);
  return parsed == 0 ? null : parsed;
}

String? _text(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

DateTime? _date(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : DateTime.tryParse(text);
}

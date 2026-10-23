class SupportCaseSummary {
  const SupportCaseSummary({
    required this.id,
    required this.reference,
    required this.kind,
    required this.subject,
    required this.status,
    required this.priority,
    required this.escalationLevel,
    this.targetType,
    this.targetId,
    this.reasonCode,
    this.assignedToUserId,
    this.assignedToName,
    this.slaDueAt,
    this.firstResponseAt,
    this.resolvedAt,
    this.escalatedAt,
    this.createdAt,
    this.lastActivityAt,
  });

  final int id;
  final String reference;
  final String kind;
  final String subject;
  final String status;
  final String priority;
  final String? targetType;
  final int? targetId;
  final String? reasonCode;
  final int? assignedToUserId;
  final String? assignedToName;
  final DateTime? slaDueAt;
  final DateTime? firstResponseAt;
  final DateTime? resolvedAt;
  final DateTime? escalatedAt;
  final int escalationLevel;
  final DateTime? createdAt;
  final DateTime? lastActivityAt;

  bool get isEscalated => escalatedAt != null || escalationLevel > 0;
  bool get isClosed => status == 'resolved' || status == 'dismissed';

  factory SupportCaseSummary.fromJson(Map<String, dynamic> json) {
    return SupportCaseSummary(
      id: _int(json['id']),
      reference: json['reference']?.toString() ?? '',
      kind: json['kind']?.toString() ?? 'support_ticket',
      subject: json['subject']?.toString() ?? '',
      status: json['status']?.toString() ?? 'open',
      priority: json['priority']?.toString() ?? 'normal',
      targetType: _nullable(json['target_type']),
      targetId: _nullableInt(json['target_id']),
      reasonCode: _nullable(json['reason_code']),
      assignedToUserId: _nullableInt(json['assigned_to_user_id']),
      assignedToName: _nullable(json['assigned_to_name']),
      slaDueAt: _date(json['sla_due_at']),
      firstResponseAt: _date(json['first_response_at']),
      resolvedAt: _date(json['resolved_at']),
      escalatedAt: _date(json['escalated_at']),
      escalationLevel: _int(json['escalation_level']),
      createdAt: _date(json['created_at']),
      lastActivityAt: _date(json['last_activity_at']),
    );
  }
}

class SupportMessageItem {
  const SupportMessageItem({
    required this.id,
    required this.actorRole,
    required this.isInternal,
    required this.body,
    this.actorUserId,
    this.actorName,
    this.createdAt,
  });

  final int id;
  final int? actorUserId;
  final String? actorName;
  final String actorRole;
  final bool isInternal;
  final String body;
  final DateTime? createdAt;

  factory SupportMessageItem.fromJson(Map<String, dynamic> json) {
    return SupportMessageItem(
      id: _int(json['id']),
      actorUserId: _nullableInt(json['actor_user_id']),
      actorName: _nullable(json['actor_name']),
      actorRole: json['actor_role']?.toString() ?? 'requester',
      isInternal: json['is_internal'] == true || json['is_internal'] == 1,
      body: json['body']?.toString() ?? '',
      createdAt: _date(json['created_at']),
    );
  }
}

class SupportCaseDetails {
  const SupportCaseDetails({
    required this.summary,
    required this.description,
    required this.messages,
    required this.events,
    this.targetPreview,
    this.requesterId,
    this.requesterName,
    this.requesterEmail,
  });

  final SupportCaseSummary summary;
  final String description;
  final int? requesterId;
  final String? requesterName;
  final String? requesterEmail;
  final List<SupportMessageItem> messages;
  final List<SupportEventItem> events;
  final Map<String, dynamic>? targetPreview;

  factory SupportCaseDetails.fromJson(Map<String, dynamic> json) {
    final requester = json['requester'];
    final requesterMap = requester is Map<String, dynamic>
        ? requester
        : const <String, dynamic>{};
    final rows = json['messages'] as List<dynamic>? ?? const <dynamic>[];
    final eventRows = json['events'] as List<dynamic>? ?? const <dynamic>[];
    return SupportCaseDetails(
      summary: SupportCaseSummary.fromJson(json),
      description: json['description']?.toString() ?? '',
      requesterId: _nullableInt(requesterMap['id']),
      requesterName: _nullable(requesterMap['name']),
      requesterEmail: _nullable(requesterMap['email']),
      messages: rows
          .whereType<Map<String, dynamic>>()
          .map(SupportMessageItem.fromJson)
          .toList(growable: false),
      events: eventRows
          .whereType<Map<String, dynamic>>()
          .map(SupportEventItem.fromJson)
          .toList(growable: false),
      targetPreview: json['target_preview'] is Map<String, dynamic>
          ? json['target_preview'] as Map<String, dynamic>
          : null,
    );
  }
}

class SupportEventItem {
  const SupportEventItem(
      {required this.event,
      this.actorName,
      this.fromStatus,
      this.toStatus,
      this.createdAt});
  final String event;
  final String? actorName;
  final String? fromStatus;
  final String? toStatus;
  final DateTime? createdAt;
  factory SupportEventItem.fromJson(Map<String, dynamic> json) =>
      SupportEventItem(
        event: json['event']?.toString() ?? '',
        actorName: _nullable(json['actor_name']),
        fromStatus: _nullable(json['from_status']),
        toStatus: _nullable(json['to_status']),
        createdAt: _date(json['created_at']),
      );
}

class SupportTeamMetric {
  const SupportTeamMetric(
      {required this.id,
      required this.name,
      required this.roles,
      required this.assignedActive,
      required this.actions7d});
  final int id;
  final String name;
  final List<String> roles;
  final int assignedActive;
  final int actions7d;
  factory SupportTeamMetric.fromJson(Map<String, dynamic> json) =>
      SupportTeamMetric(
        id: _int(json['id']),
        name: json['name']?.toString() ?? '',
        roles: _strings(json['roles']),
        assignedActive: _int(json['assigned_active']),
        actions7d: _int(json['actions_7d']),
      );
}

class SupportAdminSummary {
  const SupportAdminSummary({
    required this.newTickets,
    required this.assignedToMe,
    required this.open,
    required this.inProgress,
    required this.waitingRequester,
    required this.escalated,
    required this.overdueUnescalated,
    required this.newReports,
    required this.slaWarning,
    required this.team,
  });
  final int newTickets;
  final int assignedToMe;
  final int open;
  final int inProgress;
  final int waitingRequester;
  final int escalated;
  final int overdueUnescalated;
  final int newReports;
  final int slaWarning;
  final List<SupportTeamMetric> team;

  factory SupportAdminSummary.fromJson(Map<String, dynamic> json) {
    final teamRows = json['team'] as List<dynamic>? ?? const [];
    return SupportAdminSummary(
      newTickets: _int(json['new_tickets']),
      assignedToMe: _int(json['assigned_to_me']),
      open: _int(json['open']),
      inProgress: _int(json['in_progress']),
      waitingRequester: _int(json['waiting_requester']),
      escalated: _int(json['escalated']),
      overdueUnescalated: _int(json['overdue_unescalated']),
      newReports: _int(json['new_reports']),
      slaWarning: _int(json['sla_warning']),
      team: teamRows
          .whereType<Map<String, dynamic>>()
          .map(SupportTeamMetric.fromJson)
          .toList(growable: false),
    );
  }
}

class SupportAgentItem {
  const SupportAgentItem(
      {required this.id,
      required this.name,
      required this.roles,
      required this.activeCases});
  final int id;
  final String name;
  final List<String> roles;
  final int activeCases;
  factory SupportAgentItem.fromJson(Map<String, dynamic> json) =>
      SupportAgentItem(
          id: _int(json['id']),
          name: json['name']?.toString() ?? '',
          roles: _strings(json['roles']),
          activeCases: _int(json['active_cases']));
}

class SupportUserContext {
  const SupportUserContext(
      {required this.user, required this.cases, required this.counts});
  final Map<String, dynamic> user;
  final List<SupportCaseSummary> cases;
  final Map<String, dynamic> counts;
  factory SupportUserContext.fromJson(Map<String, dynamic> json) {
    final rows = json['support_cases'] as List<dynamic>? ?? const [];
    return SupportUserContext(
      user: json['user'] is Map<String, dynamic>
          ? json['user'] as Map<String, dynamic>
          : const {},
      cases: rows
          .whereType<Map<String, dynamic>>()
          .map(SupportCaseSummary.fromJson)
          .toList(growable: false),
      counts: json['counts'] is Map<String, dynamic>
          ? json['counts'] as Map<String, dynamic>
          : const {},
    );
  }
}

class SupportWorkLogItem {
  const SupportWorkLogItem(
      {required this.id,
      required this.action,
      this.actorName,
      this.subjectType,
      this.subjectId,
      this.createdAt});
  final int id;
  final String action;
  final String? actorName;
  final String? subjectType;
  final int? subjectId;
  final DateTime? createdAt;
  factory SupportWorkLogItem.fromJson(Map<String, dynamic> json) =>
      SupportWorkLogItem(
          id: _int(json['id']),
          action: json['action']?.toString() ?? '',
          actorName: _nullable(json['actor_name']),
          subjectType: _nullable(json['subject_type']),
          subjectId: _nullableInt(json['subject_id']),
          createdAt: _date(json['created_at']));
}

int _int(dynamic value) {
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

List<String> _strings(dynamic value) => value is List
    ? value.map((e) => e.toString()).toList(growable: false)
    : const [];

int? _nullableInt(dynamic value) {
  if (value == null) {
    return null;
  }
  final parsed = _int(value);
  return parsed == 0 ? null : parsed;
}

String? _nullable(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return text;
}

DateTime? _date(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return DateTime.tryParse(text);
}

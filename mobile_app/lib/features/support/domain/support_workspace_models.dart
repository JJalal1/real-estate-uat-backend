class SupportTaskPage {
  const SupportTaskPage({
    required this.items,
    required this.currentPage,
    required this.lastPage,
    required this.total,
  });

  final List<SupportTaskItem> items;
  final int currentPage;
  final int lastPage;
  final int total;

  bool get hasMore => currentPage < lastPage;
}

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
    this.lastMessagePreview,
    this.category,
    this.assignmentSource,
    this.isUnreceivedOverdue = false,
    this.pickupDueAt,
    this.requesterUserId,
    this.requesterName,
    this.severity,
    this.supportTeamId,
    this.supportTeamName,
    this.governorateId,
    this.governorateName,
    this.assignedToUserId,
    this.assignedToName,
    this.createdAt,
    this.claimedAt,
    this.completedAt,
    this.lastActivityAt,
    this.slaDueAt,
    this.remainingMinutes,
    this.escalatedAt,
    this.escalationReason,
    this.metadata = const <String, dynamic>{},
  });

  final int id;
  final String sourceType;
  final int sourceId;
  final String? sourceReference;
  final String? lastMessagePreview;
  final String? category;
  final String? assignmentSource;
  final bool isUnreceivedOverdue;
  final DateTime? pickupDueAt;
  final String subject;
  final int? requesterUserId;
  final String? requesterName;
  final String status;
  final String priority;
  final String? severity;
  final int? supportTeamId;
  final String? supportTeamName;
  final int? governorateId;
  final String? governorateName;
  final int? assignedToUserId;
  final String? assignedToName;
  final DateTime? createdAt;
  final DateTime? claimedAt;
  final DateTime? completedAt;
  final DateTime? lastActivityAt;
  final DateTime? slaDueAt;
  final int? remainingMinutes;
  final DateTime? escalatedAt;
  final String? escalationReason;
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
      lastMessagePreview: _text(json['last_message_preview']),
      category: _text(json['category']),
      assignmentSource: _text(json['assignment_source']),
      isUnreceivedOverdue: json['is_unreceived_overdue'] == true,
      pickupDueAt: _date(json['pickup_due_at']),
      subject: json['subject']?.toString() ?? '',
      requesterUserId: _nullableInt(json['requester_user_id']),
      requesterName: _text(json['requester_name']),
      status: json['status']?.toString() ?? 'new',
      priority: json['priority']?.toString() ?? 'normal',
      severity: _text(json['severity']),
      supportTeamId: _nullableInt(json['support_team_id']),
      supportTeamName: _text(json['support_team_name']),
      governorateId: _nullableInt(json['governorate_id']),
      governorateName: _text(json['governorate_name']),
      assignedToUserId: _nullableInt(json['assigned_to_user_id']),
      assignedToName: _text(json['assigned_to_name']),
      createdAt: _date(json['created_at']),
      claimedAt: _date(json['claimed_at']),
      completedAt: _date(json['completed_at']),
      lastActivityAt: _date(json['last_activity_at']),
      slaDueAt: _date(json['sla_due_at']),
      remainingMinutes: json['remaining_minutes'] == null
          ? null
          : _int(json['remaining_minutes']),
      escalatedAt: _date(json['escalated_at']),
      escalationReason: _text(json['escalation_reason']),
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
    required this.isAvailable,
    required this.capacity,
    required this.completedToday,
    required this.workloadPercent,
    this.teamId,
    this.teamName,
    this.averageClaimMinutes,
    this.averageResponseMinutes,
    this.averageCompletionMinutes,
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
  final int? teamId;
  final String? teamName;
  final bool isAvailable;
  final int capacity;
  final int completedToday;
  final int workloadPercent;
  final int? averageClaimMinutes;
  final int? averageResponseMinutes;
  final int? averageCompletionMinutes;
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
      teamId: _nullableInt(json['team_id']),
      teamName: _text(json['team_name']),
      isAvailable: json['is_available'] != false,
      capacity: _int(json['capacity']) == 0 ? 10 : _int(json['capacity']),
      completedToday: _int(json['completed_today']),
      workloadPercent: _int(json['workload_percent']),
      averageClaimMinutes: json['average_claim_minutes'] == null
          ? null
          : _int(json['average_claim_minutes']),
      averageResponseMinutes: json['average_response_minutes'] == null
          ? null
          : _int(json['average_response_minutes']),
      averageCompletionMinutes: json['average_completion_minutes'] == null
          ? null
          : _int(json['average_completion_minutes']),
      lastActivityAt: _date(json['last_activity_at']),
    );
  }
}

class SupportTeamSummary {
  const SupportTeamSummary({
    required this.id,
    required this.code,
    required this.name,
    required this.isFallback,
    required this.agents,
    required this.availableAgents,
    required this.openTasks,
    required this.unassigned,
    this.governorateId,
    this.governorateName,
    this.managerUserId,
    this.managerName,
  });

  final int id;
  final String code;
  final String name;
  final int? governorateId;
  final String? governorateName;
  final int? managerUserId;
  final String? managerName;
  final bool isFallback;
  final int agents;
  final int availableAgents;
  final int openTasks;
  final int unassigned;

  factory SupportTeamSummary.fromJson(Map<String, dynamic> json) => SupportTeamSummary(
        id: _int(json['id']),
        code: json['code']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        governorateId: _nullableInt(json['governorate_id']),
        governorateName: _text(json['governorate_name']),
        managerUserId: _nullableInt(json['manager_user_id']),
        managerName: _text(json['manager_name']),
        isFallback: json['is_fallback'] == true,
        agents: _int(json['agents']),
        availableAgents: _int(json['available_agents']),
        openTasks: _int(json['open_tasks']),
        unassigned: _int(json['unassigned']),
      );
}

class SupportTeamCandidate {
  const SupportTeamCandidate({
    required this.id,
    required this.name,
    this.phone,
    this.email,
  });

  final int id;
  final String name;
  final String? phone;
  final String? email;

  factory SupportTeamCandidate.fromJson(Map<String, dynamic> json) =>
      SupportTeamCandidate(
        id: _int(json['id']),
        name: _text(json['name']) ?? 'مستخدم',
        phone: _text(json['phone']),
        email: _text(json['email']),
      );
}

class SupportTeamMembership {
  const SupportTeamMembership({
    required this.userId,
    required this.name,
    required this.agent,
    required this.manager,
    required this.reviewPayments,
    required this.reviewListings,
  });

  final int userId;
  final String name;
  final bool agent;
  final bool manager;
  final bool reviewPayments;
  final bool reviewListings;

  factory SupportTeamMembership.fromJson(Map<String, dynamic> json) =>
      SupportTeamMembership(
        userId: _int(json['user_id']),
        name: _text(json['name']) ?? 'مستخدم',
        agent: json['agent'] == true,
        manager: json['manager'] == true,
        reviewPayments: json['review_payments'] == true,
        reviewListings: json['review_listings'] == true,
      );
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

  Set<int> get governorateIds => values['governorate_ids'] is List
      ? (values['governorate_ids'] as List).map(_int).where((id) => id > 0).toSet()
      : const <int>{};

  Set<String> get governorateCodes => values['governorate_codes'] is List
      ? (values['governorate_codes'] as List).whereType<String>().toSet()
      : const <String>{};

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

class SupportStaffThread {
  const SupportStaffThread({required this.id, required this.name, required this.channel,
    this.team, this.preview, this.messages = const []});

  final int id;
  final String name;
  final String channel;
  final String? team;
  final String? preview;
  final List<SupportStaffMessage> messages;

  factory SupportStaffThread.fromJson(Map<String, dynamic> json) => SupportStaffThread(
    id: _int(json['id']),
    name: json['name']?.toString() ?? '',
    channel: json['channel']?.toString() ?? '',
    team: _text(json['team']),
    preview: _text(json['preview']),
    messages: (json['messages'] as List? ?? const [])
        .whereType<Map<String, dynamic>>().map(SupportStaffMessage.fromJson).toList(growable: false),
  );
}

class SupportStaffMessage {
  const SupportStaffMessage(this.id, this.body, this.mine, this.taskId);

  final int id;
  final String body;
  final bool mine;
  final int? taskId;

  factory SupportStaffMessage.fromJson(Map<String, dynamic> json) => SupportStaffMessage(
    _int(json['id']), json['body']?.toString() ?? '', json['mine'] == true, _nullableInt(json['task_id']),
  );
}

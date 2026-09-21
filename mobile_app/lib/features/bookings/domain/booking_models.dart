class ViewingBooking {
  const ViewingBooking({
    required this.id,
    required this.reference,
    required this.requesterUserId,
    required this.requesterName,
    required this.hostUserId,
    required this.hostName,
    required this.messageThreadId,
    required this.targetType,
    required this.targetId,
    required this.targetTitle,
    required this.targetAddress,
    required this.startsAt,
    required this.endsAt,
    required this.timezone,
    required this.status,
    required this.requesterNote,
    required this.hostNote,
    required this.cancellationReason,
    required this.isRequester,
    required this.canManage,
    required this.canCancel,
    required this.canReschedule,
    required this.canConfirm,
    required this.canDecline,
    required this.canAcceptReschedule,
    required this.awaitingRequesterConfirmation,
  });

  factory ViewingBooking.fromJson(Map<String, dynamic> json) => ViewingBooking(
        id: _int(json['id']),
        reference: json['reference']?.toString() ?? '',
        requesterUserId: _int(json['requester_user_id']),
        requesterName: json['requester_name']?.toString() ?? '',
        hostUserId: _nullableInt(json['host_user_id']),
        hostName: json['host_name']?.toString(),
        messageThreadId: _nullableInt(json['message_thread_id']),
        targetType: json['target_type']?.toString() ?? 'property',
        targetId: _int(json['target_id']),
        targetTitle: json['target_title']?.toString() ?? '',
        targetAddress: json['target_address']?.toString(),
        startsAt: DateTime.parse(json['starts_at'].toString()),
        endsAt: DateTime.parse(json['ends_at'].toString()),
        timezone: json['timezone']?.toString() ?? 'UTC',
        status: json['status']?.toString() ?? 'requested',
        requesterNote: json['requester_note']?.toString(),
        hostNote: json['host_note']?.toString(),
        cancellationReason: json['cancellation_reason']?.toString(),
        isRequester: json['is_requester'] == true,
        canManage: json['can_manage'] == true,
        canCancel: json['can_cancel'] == true,
        canReschedule: json['can_reschedule'] == true,
        canConfirm: json['can_confirm'] == true,
        canDecline: json['can_decline'] == true,
        canAcceptReschedule: json['can_accept_reschedule'] == true,
        awaitingRequesterConfirmation:
            json['awaiting_requester_confirmation'] == true,
      );

  final int id;
  final String reference;
  final int requesterUserId;
  final String requesterName;
  final int? hostUserId;
  final String? hostName;
  final int? messageThreadId;
  final String targetType;
  final int targetId;
  final String targetTitle;
  final String? targetAddress;
  final DateTime startsAt;
  final DateTime endsAt;
  final String timezone;
  final String status;
  final String? requesterNote;
  final String? hostNote;
  final String? cancellationReason;
  final bool isRequester;
  final bool canManage;
  final bool canCancel;
  final bool canReschedule;
  final bool canConfirm;
  final bool canDecline;
  final bool canAcceptReschedule;
  final bool awaitingRequesterConfirmation;

  bool get isActive => status == 'requested' || status == 'confirmed';
  bool get canComplete =>
      canManage && status == 'confirmed' && !endsAt.isAfter(DateTime.now());
  String get targetLabel =>
      targetType == 'development_unit' ? 'وحدة مشروع' : 'عقار';
  String get statusLabel => switch (status) {
        'confirmed' => 'مؤكد',
        'declined' => 'مرفوض',
        'cancelled' => 'ملغي',
        'completed' => 'مكتمل',
        'requested' when awaitingRequesterConfirmation && isRequester =>
          'بانتظار موافقتك',
        'requested' when awaitingRequesterConfirmation =>
          'بانتظار موافقة طالب المعاينة',
        _ => 'بانتظار التأكيد',
      };
}

int _int(Object? value) =>
    value is num ? value.toInt() : int.parse(value.toString());
int? _nullableInt(Object? value) => value == null ? null : _int(value);

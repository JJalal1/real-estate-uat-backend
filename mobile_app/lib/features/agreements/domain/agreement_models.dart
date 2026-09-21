class AgreementRevision {
  const AgreementRevision({
    required this.id,
    required this.revisionNumber,
    required this.agreedAmount,
    required this.currency,
    required this.createdByUserId,
    required this.createdByName,
    this.rentCadence,
    this.securityDepositAmount,
    this.rentalStartDate,
    this.rentalEndDate,
    this.conditions,
    this.createdAt,
  });

  final int id;
  final int revisionNumber;
  final double agreedAmount;
  final String currency;
  final String? rentCadence;
  final double? securityDepositAmount;
  final DateTime? rentalStartDate;
  final DateTime? rentalEndDate;
  final String? conditions;
  final int createdByUserId;
  final String createdByName;
  final DateTime? createdAt;

  String get cadenceLabel => cadenceLabelFor(rentCadence);

  factory AgreementRevision.fromJson(Map<String, dynamic> json) {
    return AgreementRevision(
      id: _int(json['id']) ?? 0,
      revisionNumber: _int(json['revision_number']) ?? 0,
      agreedAmount: _double(json['agreed_amount']) ?? 0,
      currency: json['currency']?.toString() ?? '',
      rentCadence: _nullable(json['rent_cadence']),
      securityDepositAmount: _double(json['security_deposit_amount']),
      rentalStartDate: _date(json['rental_start_date']),
      rentalEndDate: _date(json['rental_end_date']),
      conditions: _nullable(json['conditions']),
      createdByUserId: _int(json['created_by_user_id']) ?? 0,
      createdByName: json['created_by_name']?.toString() ?? 'مستخدم',
      createdAt: _date(json['created_at']),
    );
  }
}

class PropertyAgreement {
  const PropertyAgreement({
    required this.id,
    required this.reference,
    required this.propertyId,
    required this.messageThreadId,
    required this.requesterUserId,
    required this.advertiserUserId,
    required this.transactionType,
    required this.status,
    required this.currentRevision,
    required this.requesterAccepted,
    required this.advertiserAccepted,
    required this.myAccepted,
    required this.canRevise,
    required this.canAccept,
    required this.canCancel,
    this.viewingBookingId,
    this.rentalContractId,
    this.acceptedAt,
    this.cancelledAt,
    this.cancellationReason,
    this.createdAt,
    this.revisions = const <AgreementRevision>[],
  });

  final int id;
  final String reference;
  final int propertyId;
  final int messageThreadId;
  final int? viewingBookingId;
  final int requesterUserId;
  final int advertiserUserId;
  final String transactionType;
  final String status;
  final AgreementRevision currentRevision;
  final bool requesterAccepted;
  final bool advertiserAccepted;
  final bool myAccepted;
  final bool canRevise;
  final bool canAccept;
  final bool canCancel;
  final int? rentalContractId;
  final DateTime? acceptedAt;
  final DateTime? cancelledAt;
  final String? cancellationReason;
  final DateTime? createdAt;
  final List<AgreementRevision> revisions;

  bool get isRental => transactionType == 'rent';
  bool get isAccepted => status == 'accepted';
  bool get isDraft => status == 'draft';

  String get transactionLabel => isRental ? 'إيجار' : 'بيع';

  String get statusLabel => switch (status) {
        'accepted' => 'مقبول من الطرفين',
        'cancelled' => 'ملغي',
        _ => 'مسودة اتفاق',
      };

  factory PropertyAgreement.fromJson(Map<String, dynamic> json) {
    final current = json['current_revision'];
    if (current is! Map<String, dynamic>) {
      throw StateError('Invalid agreement response: missing current revision.');
    }
    final rawRevisions = json['revisions'] as List<dynamic>? ?? const [];
    return PropertyAgreement(
      id: _int(json['id']) ?? 0,
      reference: json['reference']?.toString() ?? '',
      propertyId: _int(json['property_id']) ?? 0,
      messageThreadId: _int(json['message_thread_id']) ?? 0,
      viewingBookingId: _int(json['viewing_booking_id']),
      requesterUserId: _int(json['requester_user_id']) ?? 0,
      advertiserUserId: _int(json['advertiser_user_id']) ?? 0,
      transactionType: json['transaction_type']?.toString() ?? 'sale',
      status: json['status']?.toString() ?? 'draft',
      currentRevision: AgreementRevision.fromJson(current),
      requesterAccepted: _bool(json['requester_accepted']),
      advertiserAccepted: _bool(json['advertiser_accepted']),
      myAccepted: _bool(json['my_accepted']),
      canRevise: _bool(json['can_revise']),
      canAccept: _bool(json['can_accept']),
      canCancel: _bool(json['can_cancel']),
      rentalContractId: _int(json['rental_contract_id']),
      acceptedAt: _date(json['accepted_at']),
      cancelledAt: _date(json['cancelled_at']),
      cancellationReason: _nullable(json['cancellation_reason']),
      createdAt: _date(json['created_at']),
      revisions: rawRevisions
          .whereType<Map<String, dynamic>>()
          .map(AgreementRevision.fromJson)
          .toList(growable: false),
    );
  }
}

class RentalContractRevision {
  const RentalContractRevision({
    required this.id,
    required this.revisionNumber,
    required this.rentAmount,
    required this.currency,
    required this.rentCadence,
    required this.startDate,
    required this.endDate,
    required this.createdByUserId,
    required this.createdByName,
    this.securityDepositAmount,
    this.paymentDueDay,
    this.additionalTerms,
    this.createdAt,
  });

  final int id;
  final int revisionNumber;
  final double rentAmount;
  final String currency;
  final String rentCadence;
  final DateTime startDate;
  final DateTime endDate;
  final double? securityDepositAmount;
  final int? paymentDueDay;
  final String? additionalTerms;
  final int createdByUserId;
  final String createdByName;
  final DateTime? createdAt;

  String get cadenceLabel => cadenceLabelFor(rentCadence);

  factory RentalContractRevision.fromJson(Map<String, dynamic> json) {
    final start = _date(json['start_date']);
    final end = _date(json['end_date']);
    if (start == null || end == null) {
      throw StateError('Invalid rental contract response: dates are missing.');
    }
    return RentalContractRevision(
      id: _int(json['id']) ?? 0,
      revisionNumber: _int(json['revision_number']) ?? 0,
      rentAmount: _double(json['rent_amount']) ?? 0,
      currency: json['currency']?.toString() ?? '',
      rentCadence: json['rent_cadence']?.toString() ?? 'monthly',
      startDate: start,
      endDate: end,
      securityDepositAmount: _double(json['security_deposit_amount']),
      paymentDueDay: _int(json['payment_due_day']),
      additionalTerms: _nullable(json['additional_terms']),
      createdByUserId: _int(json['created_by_user_id']) ?? 0,
      createdByName: json['created_by_name']?.toString() ?? 'مستخدم',
      createdAt: _date(json['created_at']),
    );
  }
}

class RentalContract {
  const RentalContract({
    required this.id,
    required this.reference,
    required this.propertyAgreementId,
    required this.propertyId,
    required this.messageThreadId,
    required this.tenantUserId,
    required this.advertiserUserId,
    required this.propertyTitle,
    required this.tenantName,
    required this.advertiserName,
    required this.status,
    required this.currentRevision,
    required this.tenantAccepted,
    required this.advertiserAccepted,
    required this.myAccepted,
    required this.canRevise,
    required this.canAccept,
    required this.canCancel,
    required this.canTerminate,
    required this.inAppOnly,
    required this.officialRegistration,
    this.propertyAddress,
    this.activatedAt,
    this.cancelledAt,
    this.terminatedAt,
    this.closureReason,
    this.createdAt,
    this.revisions = const <RentalContractRevision>[],
  });

  final int id;
  final String reference;
  final int propertyAgreementId;
  final int propertyId;
  final int messageThreadId;
  final int tenantUserId;
  final int advertiserUserId;
  final String propertyTitle;
  final String? propertyAddress;
  final String tenantName;
  final String advertiserName;
  final String status;
  final RentalContractRevision currentRevision;
  final bool tenantAccepted;
  final bool advertiserAccepted;
  final bool myAccepted;
  final bool canRevise;
  final bool canAccept;
  final bool canCancel;
  final bool canTerminate;
  final DateTime? activatedAt;
  final DateTime? cancelledAt;
  final DateTime? terminatedAt;
  final String? closureReason;
  final DateTime? createdAt;
  final bool inAppOnly;
  final bool officialRegistration;
  final List<RentalContractRevision> revisions;

  bool get isActive => status == 'active';
  bool get isDraft => status == 'draft';

  String get statusLabel => switch (status) {
        'active' => 'مقبول داخل التطبيق',
        'cancelled' => 'ملغى',
        'terminated' => 'منتهٍ داخل التطبيق',
        _ => 'مسودة عقد إيجار',
      };

  factory RentalContract.fromJson(Map<String, dynamic> json) {
    final current = json['current_revision'];
    if (current is! Map<String, dynamic>) {
      throw StateError('Invalid rental contract response: missing current revision.');
    }
    final rawRevisions = json['revisions'] as List<dynamic>? ?? const [];
    return RentalContract(
      id: _int(json['id']) ?? 0,
      reference: json['reference']?.toString() ?? '',
      propertyAgreementId: _int(json['property_agreement_id']) ?? 0,
      propertyId: _int(json['property_id']) ?? 0,
      messageThreadId: _int(json['message_thread_id']) ?? 0,
      tenantUserId: _int(json['tenant_user_id']) ?? 0,
      advertiserUserId: _int(json['advertiser_user_id']) ?? 0,
      propertyTitle: json['property_title']?.toString() ?? 'عقار',
      propertyAddress: _nullable(json['property_address']),
      tenantName: json['tenant_name']?.toString() ?? 'المستأجر',
      advertiserName: json['advertiser_name']?.toString() ?? 'المعلن',
      status: json['status']?.toString() ?? 'draft',
      currentRevision: RentalContractRevision.fromJson(current),
      tenantAccepted: _bool(json['tenant_accepted']),
      advertiserAccepted: _bool(json['advertiser_accepted']),
      myAccepted: _bool(json['my_accepted']),
      canRevise: _bool(json['can_revise']),
      canAccept: _bool(json['can_accept']),
      canCancel: _bool(json['can_cancel']),
      canTerminate: _bool(json['can_terminate']),
      activatedAt: _date(json['activated_at']),
      cancelledAt: _date(json['cancelled_at']),
      terminatedAt: _date(json['terminated_at']),
      closureReason: _nullable(json['closure_reason']),
      createdAt: _date(json['created_at']),
      inAppOnly: json['in_app_only'] != false,
      officialRegistration: _bool(json['official_registration']),
      revisions: rawRevisions
          .whereType<Map<String, dynamic>>()
          .map(RentalContractRevision.fromJson)
          .toList(growable: false),
    );
  }
}

String cadenceLabelFor(String? value) => switch (value) {
      'quarterly' => 'كل 3 أشهر',
      'semiannual' => 'كل 6 أشهر',
      'annual' => 'سنوي',
      'monthly' => 'شهري',
      _ => '-',
    };

String moneyLabel(double value, String currency) {
  final rounded = value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
  return '$rounded $currency';
}

int? _int(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

double? _double(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

bool _bool(dynamic value) => value == true || value == 1 || value == '1';

String? _nullable(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

DateTime? _date(dynamic value) {
  final text = value?.toString();
  return text == null || text.isEmpty ? null : DateTime.tryParse(text);
}

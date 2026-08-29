class VerificationProfileSummary {
  const VerificationProfileSummary({
    required this.type,
    required this.status,
    required this.submittedAt,
    required this.reviewedAt,
    required this.note,
    required this.flags,
  });

  final String? type;
  final String status;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final String? note;
  final Map<String, bool> flags;

  bool get isApproved => status == 'approved' && reviewedAt != null;
  bool get identityReviewed => flags['identity_reviewed'] == true;
  bool get professionalDocumentReviewed =>
      flags['professional_document_reviewed'] == true;
  bool get commercialRegisterReviewed =>
      flags['commercial_register_reviewed'] == true;
  bool get officeDocumentsReviewed =>
      flags['office_documents_reviewed'] == true;
  bool get officeLocationRegistered =>
      flags['office_location_registered'] == true;

  String get typeLabel => switch (type) {
        'owner' => 'مالك',
        'broker' => professionalDocumentReviewed ? 'دلال مهني' : 'دلال',
        'office' => 'مكتب عقارات',
        _ => 'باحث / متصفح / مشتري',
      };

  String get statusLabel => switch (status) {
        'pending' => 'قيد المراجعة',
        'approved' => 'موثق',
        'rejected' => 'مرفوض',
        'needs_more_info' => 'يحتاج مستند أو توضيح إضافي',
        _ => 'لم يرسل طلب تحقق',
      };

  factory VerificationProfileSummary.fromJson(dynamic value) {
    final json = value is Map<String, dynamic>
        ? value
        : const <String, dynamic>{};
    final rawFlags = json['flags'];
    final flags = <String, bool>{};
    if (rawFlags is Map) {
      for (final entry in rawFlags.entries) {
        flags[entry.key.toString()] = entry.value == true || entry.value == 1;
      }
    }
    return VerificationProfileSummary(
      type: _nullable(json['type']),
      status: json['status']?.toString() ?? 'not_submitted',
      submittedAt: _date(json['submitted_at']),
      reviewedAt: _date(json['reviewed_at']),
      note: _nullable(json['note']),
      flags: Map.unmodifiable(flags),
    );
  }
}

class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.accountType,
    required this.accountStatus,
    required this.phoneVerifiedAt,
    required this.profileCompletedAt,
    required this.brokerVerificationStatus,
    required this.brokerVerificationSubmittedAt,
    required this.brokerVerifiedAt,
    required this.brokerVerificationNote,
    required this.verificationProfile,
    required this.isPlatformOwner,
    required this.roles,
    required this.permissions,
  });

  final int id;
  final String name;
  final String email;
  final String? phone;
  final String accountType;
  final String accountStatus;
  final DateTime? phoneVerifiedAt;
  final DateTime? profileCompletedAt;
  final String brokerVerificationStatus;
  final DateTime? brokerVerificationSubmittedAt;
  final DateTime? brokerVerifiedAt;
  final String? brokerVerificationNote;
  final VerificationProfileSummary verificationProfile;
  final bool isPlatformOwner;
  final List<String> roles;
  final List<String> permissions;

  bool get isPhoneVerified => phoneVerifiedAt != null;
  bool get isActive => accountStatus == 'active' && isPhoneVerified;
  bool get needsPhoneVerification =>
      accountStatus == 'pending_verification' || !isPhoneVerified;
  bool get needsProfileCompletion => profileCompletedAt == null;
  bool get isOwner => verificationProfile.type == 'owner';
  bool get isOffice => verificationProfile.type == 'office';
  bool get isBroker => verificationProfile.type == 'broker' ||
      (verificationProfile.type == null && accountType == 'broker');
  bool get isRegular => !isBroker;
  bool get isBrokerVerified =>
      (verificationProfile.type == 'broker' && verificationProfile.isApproved) ||
      (verificationProfile.type == null &&
          accountType == 'broker' &&
          brokerVerificationStatus == 'approved' &&
          brokerVerifiedAt != null);
  bool get hasVerifiedPublishingProfile =>
      verificationProfile.isApproved &&
      const {'owner', 'broker', 'office'}.contains(verificationProfile.type);
  bool get canCreateListing =>
      isActive && !needsProfileCompletion && hasVerifiedPublishingProfile;
  String get accountTypeLabel => verificationProfile.typeLabel;

  bool hasRole(String key) => roles.contains(key);
  bool hasPermission(String key) =>
      isPlatformOwner || permissions.contains(key);
  bool get canAccessAdminPanel =>
      isPlatformOwner ||
      hasPermission('users.view') ||
      hasPermission('audit.view') ||
      hasPermission('regions.manage') ||
      hasPermission('support.handle_reports') ||
      hasPermission('accounts.verify_profiles') ||
      hasPermission('brokers.verify_accounts') ||
      hasPermission('content.moderate');

  bool get canAccessSystemWorkspace =>
      isPlatformOwner || hasPermission('dashboard.view');

  bool get canAccessSupportWorkspace =>
      isPlatformOwner ||
      hasPermission('support.handle_reports') ||
      hasPermission('support.manage');

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] is num
            ? (json['id'] as num).toInt()
            : int.tryParse(json['id']?.toString() ?? '') ?? 0,
        name: json['name']?.toString() ?? '',
        email: json['email']?.toString() ?? '',
        phone: _nullable(json['phone']),
        accountType: json['account_type']?.toString() ?? 'regular',
        accountStatus:
            json['account_status']?.toString() ?? 'pending_verification',
        phoneVerifiedAt: _date(json['phone_verified_at']),
        profileCompletedAt: _date(json['profile_completed_at']),
        brokerVerificationStatus:
            json['broker_verification_status']?.toString() ?? 'not_required',
        brokerVerificationSubmittedAt:
            _date(json['broker_verification_submitted_at']),
        brokerVerifiedAt: _date(json['broker_verified_at']),
        brokerVerificationNote: _nullable(json['broker_verification_note']),
        verificationProfile:
            VerificationProfileSummary.fromJson(json['verification_profile']),
        isPlatformOwner: json['is_platform_owner'] == true,
        roles: _strings(json['roles']),
        permissions: _strings(json['permissions']),
      );

  static List<String> _strings(dynamic value) {
    if (value is! List) return const [];
    return value.map((item) => item.toString()).toList(growable: false);
  }
}

class AuthResult {
  const AuthResult({required this.user, required this.legacyListingsClaimed});
  final AuthUser user;
  final int legacyListingsClaimed;
}

class WhatsAppAuthPending {
  const WhatsAppAuthPending({
    required this.phone,
    required this.isNewAccount,
    this.debugCode,
  });

  final String phone;
  final bool isNewAccount;
  final String? debugCode;
}

String? _nullable(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

DateTime? _date(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : DateTime.tryParse(text);
}

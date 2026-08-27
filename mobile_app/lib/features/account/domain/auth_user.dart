class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.accountType,
    required this.accountStatus,
    required this.phoneVerifiedAt,
    required this.brokerVerificationStatus,
    required this.brokerVerificationSubmittedAt,
    required this.brokerVerifiedAt,
    required this.brokerVerificationNote,
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
  final String brokerVerificationStatus;
  final DateTime? brokerVerificationSubmittedAt;
  final DateTime? brokerVerifiedAt;
  final String? brokerVerificationNote;
  final bool isPlatformOwner;
  final List<String> roles;
  final List<String> permissions;

  bool get isPhoneVerified => phoneVerifiedAt != null;
  bool get isActive => accountStatus == 'active' && isPhoneVerified;
  bool get needsPhoneVerification =>
      accountStatus == 'pending_verification' || !isPhoneVerified;
  bool get isBroker => accountType == 'broker';
  bool get isRegular => !isBroker;
  bool get isBrokerVerified =>
      isBroker &&
      brokerVerificationStatus == 'approved' &&
      brokerVerifiedAt != null;
  bool get canCreateListing => isActive && (isRegular || isBrokerVerified);
  String get accountTypeLabel => isBroker ? 'دلال' : 'مستخدم عادي';

  bool hasRole(String key) => roles.contains(key);
  bool hasPermission(String key) =>
      isPlatformOwner || permissions.contains(key);
  bool get canAccessAdminPanel =>
      isPlatformOwner ||
      hasPermission('users.view') ||
      hasPermission('audit.view') ||
      hasPermission('regions.manage') ||
      hasPermission('support.handle_reports') ||
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
        brokerVerificationStatus:
            json['broker_verification_status']?.toString() ?? 'not_required',
        brokerVerificationSubmittedAt:
            _date(json['broker_verification_submitted_at']),
        brokerVerifiedAt: _date(json['broker_verified_at']),
        brokerVerificationNote: _nullable(json['broker_verification_note']),
        isPlatformOwner: json['is_platform_owner'] == true,
        roles: _strings(json['roles']),
        permissions: _strings(json['permissions']),
      );

  static List<String> _strings(dynamic value) {
    if (value is! List) return const [];
    return value.map((item) => item.toString()).toList(growable: false);
  }

  static String? _nullable(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static DateTime? _date(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : DateTime.tryParse(text);
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
    required this.accountType,
    required this.intent,
    this.name,
    this.debugCode,
  });

  final String phone;
  final String accountType;
  final String intent;
  final String? name;
  final String? debugCode;
}

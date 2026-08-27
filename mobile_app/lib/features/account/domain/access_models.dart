class AccessRole {
  const AccessRole(
      {required this.key, required this.nameAr, required this.nameEn});
  final String key;
  final String nameAr;
  final String nameEn;
  factory AccessRole.fromJson(Map<String, dynamic> json) => AccessRole(
        key: json['key']?.toString() ?? '',
        nameAr: json['name_ar']?.toString() ?? '',
        nameEn: json['name_en']?.toString() ?? '',
      );
}

class AccessPermission {
  const AccessPermission({
    required this.key,
    required this.nameAr,
    required this.nameEn,
    required this.scope,
  });
  final String key;
  final String nameAr;
  final String nameEn;
  final String scope;
  factory AccessPermission.fromJson(Map<String, dynamic> json) =>
      AccessPermission(
        key: json['key']?.toString() ?? '',
        nameAr: json['name_ar']?.toString() ?? '',
        nameEn: json['name_en']?.toString() ?? '',
        scope: json['scope']?.toString() ?? 'general',
      );
}

class AccessCatalog {
  const AccessCatalog({required this.roles, required this.permissions});
  final List<AccessRole> roles;
  final List<AccessPermission> permissions;
}

class PermissionOverrideValue {
  const PermissionOverrideValue({
    required this.permissionKey,
    required this.effect,
    this.reason,
  });
  final String permissionKey;
  final String effect;
  final String? reason;
}

class AccessUserSummary {
  const AccessUserSummary({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.accountStatus,
    required this.accountType,
    required this.brokerVerificationStatus,
    required this.isPlatformOwner,
    required this.roles,
    required this.permissions,
    required this.permissionOverrides,
  });
  final int id;
  final String name;
  final String email;
  final String? phone;
  final String accountStatus;
  final String accountType;
  final String brokerVerificationStatus;
  final bool isPlatformOwner;
  final List<String> roles;
  final List<String> permissions;
  final List<PermissionOverrideValue> permissionOverrides;

  factory AccessUserSummary.fromJson(Map<String, dynamic> json) =>
      AccessUserSummary(
        id: json['id'] is num
            ? (json['id'] as num).toInt()
            : int.tryParse('${json['id']}') ?? 0,
        name: json['name']?.toString() ?? '',
        email: json['email']?.toString() ?? '',
        phone: json['phone']?.toString(),
        accountStatus: json['account_status']?.toString() ?? '',
        accountType: json['account_type']?.toString() ?? 'regular',
        brokerVerificationStatus:
            json['broker_verification_status']?.toString() ?? 'not_required',
        isPlatformOwner: json['is_platform_owner'] == true,
        roles: _strings(json['roles']),
        permissions: _strings(json['permissions']),
        permissionOverrides: _overrideList(json['permission_overrides']),
      );

  static List<String> _strings(dynamic value) => value is List
      ? value.map((e) => e.toString()).toList(growable: false)
      : const [];

  static List<PermissionOverrideValue> _overrideList(dynamic value) {
    if (value is! List) {
      return const [];
    }
    return value
        .whereType<Map<String, dynamic>>()
        .map((json) => PermissionOverrideValue(
              permissionKey: json['permission_key']?.toString() ?? '',
              effect: json['effect']?.toString() ?? '',
              reason: json['reason']?.toString(),
            ))
        .toList(growable: false);
  }
}

class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.action,
    required this.actorName,
    required this.targetUserId,
    required this.subjectType,
    required this.subjectId,
    required this.createdAt,
  });
  final int id;
  final String action;
  final String? actorName;
  final int? targetUserId;
  final String? subjectType;
  final int? subjectId;
  final DateTime? createdAt;

  factory AuditEntry.fromJson(Map<String, dynamic> json) => AuditEntry(
        id: json['id'] is num
            ? (json['id'] as num).toInt()
            : int.tryParse('${json['id']}') ?? 0,
        action: json['action']?.toString() ?? '',
        actorName: json['actor_name']?.toString(),
        targetUserId: json['target_user_id'] is num
            ? (json['target_user_id'] as num).toInt()
            : null,
        subjectType: json['subject_type']?.toString(),
        subjectId: json['subject_id'] is num
            ? (json['subject_id'] as num).toInt()
            : null,
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      );
}

class AccountVerificationDocumentItem {
  const AccountVerificationDocumentItem({
    required this.kind,
    required this.originalName,
    required this.mimeType,
    required this.sizeBytes,
    required this.url,
  });

  final String kind;
  final String originalName;
  final String? mimeType;
  final int? sizeBytes;
  final String? url;

  factory AccountVerificationDocumentItem.fromJson(Map<String, dynamic> json) {
    return AccountVerificationDocumentItem(
      kind: json['kind']?.toString() ?? '',
      originalName: json['original_name']?.toString() ?? '',
      mimeType: _nullable(json['mime_type']),
      sizeBytes: _asInt(json['size_bytes']),
      url: _nullable(json['url']),
    );
  }
}

class AccountVerificationApplication {
  const AccountVerificationApplication({
    required this.userId,
    required this.name,
    required this.phone,
    required this.type,
    required this.status,
    required this.details,
    required this.documents,
    required this.verificationFlags,
    required this.submittedAt,
    required this.reviewedAt,
    required this.note,
  });

  final int userId;
  final String name;
  final String? phone;
  final String? type;
  final String status;
  final Map<String, dynamic> details;
  final List<AccountVerificationDocumentItem> documents;
  final Map<String, bool> verificationFlags;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final String? note;

  bool get pending => status == 'pending';
  bool get approved => status == 'approved';
  bool get needsMoreInfo => status == 'needs_more_info';
  bool get rejected => status == 'rejected';
  bool get hasApplication => type != null;
  bool get canResubmit => !approved;

  String get typeLabel => switch (type) {
        'owner' => 'مالك',
        'broker' => verificationFlags['professional_document_reviewed'] == true
            ? 'دلال مهني'
            : 'دلال',
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

  String? detailText(String key) => _nullable(details[key]);
  double? detailDouble(String key) => _asDouble(details[key]);

  List<String> detailStrings(String key) {
    final value = details[key];
    if (value is! List) return const <String>[];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  bool hasDocument(String kind) =>
      documents.any((document) => document.kind == kind);

  factory AccountVerificationApplication.fromJson(Map<String, dynamic> json) {
    final detailsValue = json['details'];
    final details = <String, dynamic>{};
    if (detailsValue is Map) {
      for (final entry in detailsValue.entries) {
        details[entry.key.toString()] = entry.value;
      }
    }
    final documentsValue = json['documents'];
    final documents = documentsValue is List
        ? documentsValue
            .whereType<Map<String, dynamic>>()
            .map(AccountVerificationDocumentItem.fromJson)
            .toList(growable: false)
        : const <AccountVerificationDocumentItem>[];
    final flagsValue = json['verification_flags'];
    final flags = <String, bool>{};
    if (flagsValue is Map) {
      for (final entry in flagsValue.entries) {
        flags[entry.key.toString()] = entry.value == true || entry.value == 1;
      }
    }
    return AccountVerificationApplication(
      userId: _asInt(json['user_id']) ?? 0,
      name: json['name']?.toString() ?? '',
      phone: _nullable(json['phone']),
      type: _nullable(json['type']),
      status: json['status']?.toString() ?? 'not_submitted',
      details: Map.unmodifiable(details),
      documents: List.unmodifiable(documents),
      verificationFlags: Map.unmodifiable(flags),
      submittedAt: _date(json['submitted_at']),
      reviewedAt: _date(json['reviewed_at']),
      note: _nullable(json['note']),
    );
  }
}

String accountVerificationTypeLabel(String? type) => switch (type) {
      'owner' => 'مالك',
      'broker' => 'دلال',
      'office' => 'مكتب عقارات',
      _ => 'باحث / متصفح / مشتري',
    };

String accountVerificationDocumentLabel(String kind) => switch (kind) {
      'identity_document' => 'البطاقة الشخصية أو جواز السفر',
      'responsible_identity' => 'هوية مسؤول المكتب',
      'identity_back' => 'الوجه الخلفي للهوية',
      'selfie' => 'الصورة الحية / السيلفي',
      'professional_license' => 'الوثيقة المهنية للدلال',
      'commercial_register' => 'السجل التجاري',
      'office_license' => 'ترخيص المكتب العقاري',
      'office_frontage' => 'صورة واجهة المكتب',
      'office_logo' => 'شعار المكتب',
      _ => kind,
    };

String? _nullable(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

double? _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

DateTime? _date(dynamic value) {
  final text = _nullable(value);
  return text == null ? null : DateTime.tryParse(text);
}

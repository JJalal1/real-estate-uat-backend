class BrokerVerificationDocumentInfo {
  const BrokerVerificationDocumentInfo({required this.kind, required this.url});
  final String kind;
  final String url;

  factory BrokerVerificationDocumentInfo.fromJson(Map<String, dynamic> json) =>
      BrokerVerificationDocumentInfo(
        kind: json['kind']?.toString() ?? '',
        url: json['url']?.toString() ?? '',
      );
}

class BrokerVerificationApplication {
  const BrokerVerificationApplication({
    required this.userId,
    required this.name,
    required this.phone,
    required this.status,
    required this.documents,
    this.note,
  });

  final int userId;
  final String name;
  final String? phone;
  final String status;
  final String? note;
  final List<BrokerVerificationDocumentInfo> documents;

  bool get approved => status == 'approved';
  bool get pending => status == 'pending';

  factory BrokerVerificationApplication.fromJson(Map<String, dynamic> json) {
    final docs = json['documents'];
    return BrokerVerificationApplication(
      userId: json['user_id'] is num
          ? (json['user_id'] as num).toInt()
          : int.tryParse(json['user_id']?.toString() ?? '') ?? 0,
      name: json['name']?.toString() ?? '',
      phone: _nullable(json['phone']),
      status: json['status']?.toString() ?? 'not_submitted',
      note: _nullable(json['note']),
      documents: docs is List
          ? docs
              .whereType<Map<String, dynamic>>()
              .map(BrokerVerificationDocumentInfo.fromJson)
              .toList(growable: false)
          : const [],
    );
  }

  static String? _nullable(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}

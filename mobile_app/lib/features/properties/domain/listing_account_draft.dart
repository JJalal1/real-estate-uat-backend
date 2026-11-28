import '../../../core/platform/client_request_key.dart';

String newListingDraftKey() => newClientRequestKey();

class ListingAccountDraft {
  const ListingAccountDraft({required this.key, required this.revision, required this.payload,
    this.title = 'إعلان غير مكتمل', this.progress = 0, this.images = const {}, this.propertyId,
    this.updatedAt, this.firstSavedAt});
  final String key, title;
  final int revision, progress;
  final int? propertyId;
  final DateTime? updatedAt, firstSavedAt;
  final Map<String, dynamic> payload;
  final Map<String, String> images;
  // Legacy checkpoints may have been explicitly saved. Unknown means protected.
  bool get isRecovery => propertyId == null && isAutomaticListingRecovery(payload);
  bool get isRetired => payload['draft_kind'] == 'retired';
  String get entryMethod => payload['entry_method'] == 'assistant' ? 'assistant' : 'manual';
  factory ListingAccountDraft.fromJson(Map<String, dynamic> data) => ListingAccountDraft(
    key: data['key'] as String, revision: (data['revision'] as num).toInt(),
    payload: Map<String, dynamic>.from(data['payload'] as Map), title: data['title']?.toString() ?? 'إعلان غير مكتمل',
    progress: (data['progress'] as num? ?? 0).toInt(), propertyId: (data['property_id'] as num?)?.toInt(),
    firstSavedAt: DateTime.tryParse(data['first_saved_at']?.toString() ?? ''),
    updatedAt: DateTime.tryParse(data['updated_at']?.toString() ?? ''),
    images: {for (final image in data['images'] as List? ?? const []) (image as Map)['key'] as String: image['url'] as String},
  );
}

bool isAutomaticListingRecovery(Map<String, dynamic> data) =>
  data['draft_kind'] == 'recovery' && (data['editor_version'] as num? ?? 0) >= 10 &&
  data['server_property_id'] == null;

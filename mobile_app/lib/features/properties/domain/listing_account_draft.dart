import 'dart:math';

String newListingDraftKey() {
  final random = Random.secure(), bytes = List<int>.generate(16, (_) => 0);
  for (var i = 0; i < 16; i++) { bytes[i] = random.nextInt(256); }
  bytes[6] = (bytes[6] & 15) | 64; bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0,8)}-${hex.substring(8,12)}-${hex.substring(12,16)}-${hex.substring(16,20)}-${hex.substring(20)}';
}

class ListingAccountDraft {
  const ListingAccountDraft({required this.key, required this.revision, required this.payload,
    this.title = 'إعلان غير مكتمل', this.progress = 0, this.images = const {}, this.propertyId});
  final String key, title;
  final int revision, progress;
  final int? propertyId;
  final Map<String, dynamic> payload;
  final Map<String, String> images;
  factory ListingAccountDraft.fromJson(Map<String, dynamic> data) => ListingAccountDraft(
    key: data['key'] as String, revision: (data['revision'] as num).toInt(),
    payload: Map<String, dynamic>.from(data['payload'] as Map), title: data['title']?.toString() ?? 'إعلان غير مكتمل',
    progress: (data['progress'] as num? ?? 0).toInt(), propertyId: (data['property_id'] as num?)?.toInt(),
    images: {for (final image in data['images'] as List? ?? const []) (image as Map)['key'] as String: image['url'] as String},
  );
}

import 'dart:async';
import 'package:real_estate_mobile/core/platform/voice_input.dart';
import 'package:real_estate_mobile/features/discovery/data/ai_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_repository.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';

PropertySummary wave3Property(int id) => PropertySummary.fromJson({'id': id, 'title': 'عقار تجريبي $id', 'type': 'apartment',
  'purpose': 'rent', 'price': 300000, 'monthly_rent': 100000, 'currency': 'YER', 'address': 'صنعاء، حدة', 'latitude': 15.3694, 'longitude': 44.1910});

class Wave3AiFake implements AiRepository {
  @override
  DateTime? descriptionRetryAt;
  final requests = <({String message, Map<String, dynamic> filters, int revision})>[];
  Future<Map<String, dynamic>> Function(String, Map<String, dynamic>, int)? onRefine;
  Map<String, dynamic> fields = {'bedrooms': 4, 'has_elevator': true};
  @override
  Future<Map<String, dynamic>> refine(String message, Map<String, dynamic> filters, int revision) async {
    requests.add((message: message, filters: Map.of(filters), revision: revision));
    if (onRefine != null) return onRefine!(message, filters, revision);
    final next = <String, dynamic>{...filters};
    if (next.isEmpty) next.addAll({'type': 'apartment', 'purpose': 'rent', 'search': 'صنعاء', 'min_bedrooms': 3});
    if (message.contains('سعر') || message.contains('أقل') || message.contains('خفض')) next['max_price'] = 100000;
    if (message.contains('الغرف')) next.remove('min_bedrooms');
    return {'revision': revision, 'filters': next, 'message': 'حدّثنا شروط بحثك.'};
  }
  @override
  Future<Map<String, dynamic>> listingFields(String message, Map<String, dynamic> facts, {int? propertyId, String? draftKey}) async => {'fields': fields, 'requires_review': true};
  @override
  Future<Map<String, dynamic>> description(Map<String, dynamic> facts, {int? propertyId, String? draftKey, String sourceDescription = ''}) async => {'description': 'شقة للإيجار في صنعاء، أربع غرف.', 'requires_review': true};
  @override
  Future<Map<String, dynamic>> question(int id, String question) async => {'answer': 'هذه المعلومة غير مذكورة في الإعلان.'};
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}

class Wave3PropertiesFake implements PropertyRepository {
  final queries = <({Map<String, dynamic> filters, int page})>[];
  Future<(List<PropertySummary>, bool)> Function(Map<String, dynamic>, int)? onSearch;
  @override
  Future<(List<PropertySummary>, bool)> searchListings(Map<String, dynamic> filters, {int page = 1}) async {
    queries.add((filters: Map.of(filters), page: page));
    return onSearch == null ? ([wave3Property(11)], false) : onSearch!(filters, page);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}

class Wave3VoiceFake implements VoiceInput {
  Wave3VoiceFake({this.text = 'خفض السعر إلى مئة ألف', this.autoComplete = true});
  final String? text;
  final bool autoComplete;
  int calls = 0;
  final recordings = <Wave3RecordingFake>[];
  Wave3RecordingFake get latest => recordings.last;
  @override
  VoiceRecording start() {
    calls++;
    final recording = Wave3RecordingFake(text: text, autoComplete: autoComplete); recordings.add(recording);
    if (autoComplete) {
      scheduleMicrotask(() {
        recording.emit(const VoiceEvent('ready'));
      });
    }
    return recording;
  }
  Future<void> dispose() async { for (final recording in recordings) { await recording.close(); } }
}

class Wave3RecordingFake implements VoiceRecording {
  Wave3RecordingFake({this.text, this.autoComplete = false});
  final String? text;
  final bool autoComplete;
  final _events = StreamController<VoiceEvent>();
  int cancellations = 0, stops = 0;
  @override
  Stream<VoiceEvent> get events => _events.stream;
  void emit(VoiceEvent event) { if (!_events.isClosed) _events.add(event); }
  @override
  Future<void> cancel() async { cancellations++; }
  @override
  Future<void> stop() async {
    stops++; emit(const VoiceEvent('processing'));
    if (autoComplete) scheduleMicrotask(() => emit(text == null ? const VoiceEvent('cancelled') : VoiceEvent('final', text: text!)));
  }
  Future<void> close() => _events.close();
}

class Wave3MarketplaceFake implements MarketplaceRepository {
  Wave3MarketplaceFake({this.onFeed});
  final Future<MarketplaceFeed> Function(HomeFeedQuery)? onFeed;
  final queries = <HomeFeedQuery>[];
  @override
  Future<MarketplaceFeed> feed(HomeFeedQuery query) async {
    queries.add(query);
    return onFeed == null ? MarketplaceFeed(label: 'صنعاء', governorate: 'صنعاء', sections: {'latest': [wave3Property(11)]}) : onFeed!(query);
  }
  @override
  Future<List<HomeLocation>> locations() async => const [HomeLocation(governorate: 'صنعاء', manual: true), HomeLocation(label: 'تعز', governorate: 'تعز', latitude: 13.58, longitude: 44.02, manual: true)];
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}

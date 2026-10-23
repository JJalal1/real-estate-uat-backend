import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_video_section.dart';

void main() {
  test('parses only ready video reference fields and no private object path', () {
    final video = PropertyVideoItem.tryParse({
      'id': 71,
      'poster_url': 'https://example.test/api/property-videos/71/poster',
      'stream_url': 'https://example.test/api/property-videos/71/stream',
      'duration_ms': 45670,
      'original_path': 'private/listing-videos/71/source.mp4',
    });
    expect(video, isNotNull);
    expect(video!.id, 71);
    expect(video.durationMs, 45670);
    expect(video.streamUrl, endsWith('/stream'));
    expect(PropertyVideoItem.tryParse({'id': 2, 'stream_url': ''}), isNull);
  });

  testWidgets('video never starts before explicit interaction', (tester) async {
    const video = PropertyVideoItem(
      id: 71,
      posterUrl: 'https://example.test/api/property-videos/71/poster',
      streamUrl: 'https://example.test/api/property-videos/71/stream',
    );
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: PropertyVideoSection(video: video)),
    ));
    expect(find.text('فيديو العقار'), findsOneWidget);
    expect(find.byType(AndroidView), findsNothing);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('rejects non-HTTPS media links', (tester) async {
    const video = PropertyVideoItem(
      id: 2,
      posterUrl: 'https://example.test/poster.jpg',
      streamUrl: 'http://example.test/video.mp4',
    );
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: PropertyVideoSection(video: video)),
    ));
    expect(find.text('فيديو العقار'), findsNothing);
    expect(find.byType(AndroidView), findsNothing);
  });
}

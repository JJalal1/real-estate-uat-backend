import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/properties/domain/listing_photo_check.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const check = ListingPhotoCheck();
  const channel = MethodChannel('real_estate/media');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('matches the built or open-land category and allows background objects',
      () {
    expect(check.matches({'building': 0.98, 'car': 0.68}, 'house'), isTrue);
    expect(check.matches({'bathroom': 0.94}, 'apartment'), isTrue);
    expect(check.matches({'soil': 0.85, 'building': 0.64}, 'land'), isTrue);
    expect(check.matches({'farm': 0.95, 'building': 0.70}, 'farm'), isTrue);
    expect(check.matches({'soil': 0.90}, 'house'), isFalse);
    expect(check.matches({'building': 0.90}, 'land'), isFalse);
    expect(check.matches({'building': 0.61, 'car': 0.94}, 'house'), isFalse);
    expect(check.matches({'room': 0.51}, 'villa'), isFalse);
    expect(check.matches({}, 'land'), isFalse);
  });

  test('checks content before applying file size and extension rules',
      () async {
    final directory = await Directory.systemTemp.createTemp('listing-photo-');
    addTearDown(() => directory.delete(recursive: true));
    final oversized =
        await File('${directory.path}/large.jpg').open(mode: FileMode.write);
    await oversized.truncate(8 * 1024 * 1024 + 1);
    await oversized.close();
    final large = '${directory.path}/large.jpg';
    final webp = '${directory.path}/house.webp';
    await File(webp).writeAsBytes([1]);

    Map<String, double> labels = {'car': 0.96};
    final paths = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'labelListingPhoto');
      paths.add(call.arguments['path'] as String);
      return labels;
    });
    expect(await check.validate(large, 'house'), ListingPhotoIssue.mismatch);
    labels = {'building': 0.95};
    expect(await check.validate(large, 'house'), ListingPhotoIssue.invalidFile);
    final unsupported = '${directory.path}/house.gif';
    expect(await check.validate(unsupported, 'house'),
        ListingPhotoIssue.invalidFile);
    expect(await check.validate(webp, 'house'), isNull);
    expect(paths, [large, large, unsupported, webp]);
  });

  test('unreadable files and a failed classifier do not enter the upload flow',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'LISTING_PHOTO_UNREADABLE');
    });
    expect(await check.validate('file.jpg', 'house'),
        ListingPhotoIssue.invalidFile);

    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'LISTING_PHOTO_CHECK_UNAVAILABLE');
    });
    expect(await check.validate('file.jpg', 'house'),
        ListingPhotoIssue.unavailable);
  });
}

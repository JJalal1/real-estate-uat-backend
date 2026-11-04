import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/local/listing_viewer_key_store.dart';

void main() {
  test('failed directory lookup can retry and retain existing identifier', () async {
    final dir = await Directory.systemTemp.createTemp('aqer-viewer-io-');
    addTearDown(() => dir.delete(recursive: true));
    var calls = 0;
    final store = ListingViewerKeyStore(supportDirectory: () async {
      calls++;
      if (calls == 1) throw const FileSystemException('synthetic disk error');
      return dir;
    });
    await expectLater(store.load(), throwsA(isA<FileSystemException>()));
    final key = await store.load();
    expect(key.length, greaterThanOrEqualTo(32));
    expect(await store.load(), key);
    expect(calls, 2);
    final reopened = ListingViewerKeyStore(supportDirectory: () async => dir);
    expect(await reopened.load(), key);
  });

  test('simultaneous calls share in-flight load rather than regenerate key', () async {
    final dir = await Directory.systemTemp.createTemp('aqer-viewer-io-');
    addTearDown(() => dir.delete(recursive: true));
    final gate = Completer<void>();
    var calls = 0;
    final store = ListingViewerKeyStore(supportDirectory: () async {
      calls++;
      await gate.future;
      return dir;
    });
    final first = store.load();
    final second = store.load();
    gate.complete();
    expect(await first, await second);
    expect(calls, 1);
  });
}

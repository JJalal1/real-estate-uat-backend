import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/properties/domain/listing_account_draft.dart';
import 'package:real_estate_mobile/features/properties/domain/listing_photo_check.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_editor_screen.dart';

import 'support/wave6_fakes.dart';
import 'wave6_product_ui_test.dart' show editorSnapshot, finishWave6, pumpWave6;

class _DraftUploads extends Wave6Drafts {
  final uploaded = <String>[];

  @override
  Future<ListingAccountDraft> upload(
    String key,
    String imageKey,
    String path,
    int revision, {
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
  }) {
    uploaded.add(path);
    return super.upload(key, imageKey, path, revision,
        cancelToken: cancelToken, onSendProgress: onSendProgress);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('real_estate/media');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets(
      'only accepted files enter the draft and a rejected replacement preserves the photo',
      (tester) async {
    final directory =
        Directory.systemTemp.createTempSync('listing-editor-photos-');
    addTearDown(() => directory.delete(recursive: true));
    final house = File('${directory.path}/house.png');
    house.writeAsBytesSync(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    ));
    final car = '${directory.path}/car.png';
    var selected = [car, house.path];
    var cleanup = Completer<void>();
    final checked = <String>[];
    final discarded = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'pickImages':
          return selected;
        case 'labelListingPhoto':
          final path = call.arguments['path'] as String;
          checked.add(path);
          return path == car ? {'car': 0.98} : {'building': 0.95};
        case 'clearTemporaryFiles':
          discarded.addAll((call.arguments['paths'] as List).cast<String>());
          if (!cleanup.isCompleted) cleanup.complete();
          return null;
        default:
          throw MissingPluginException(call.method);
      }
    });

    final drafts = _DraftUploads();
    await pumpWave6(
      tester,
      ListingEditorScreen(localRecovery: editorSnapshot()),
      drafts: drafts,
    );
    final add = find.text('إضافة صور');
    await tester.ensureVisible(add);
    await tester.runAsync(() async {
      await tester.tap(add);
      await cleanup.future;
    });
    await tester.pumpAndSettle();
    expect(find.text(ListingPhotoIssue.mismatch.message), findsOneWidget);
    expect(find.text('صور الإعلان (1/12)'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(drafts.uploaded, [house.path]);

    selected = [car];
    cleanup = Completer<void>();
    final menu = find.byTooltip('خيارات الصورة');
    await tester.ensureVisible(menu);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('استبدال الصورة'));
      await cleanup.future;
    });
    await tester.pumpAndSettle();
    expect(find.text('صور الإعلان (1/12)'), findsOneWidget);
    expect(drafts.uploaded, [house.path]);
    expect(checked, [car, house.path, car]);
    expect(discarded, [car, car]);
    expect(tester.takeException(), isNull);
    await finishWave6(tester);
  });
}

import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/local/listing_recovery_store.dart';
import 'package:real_estate_mobile/core/offline/offline_connection.dart';
import 'package:real_estate_mobile/features/properties/data/public_photo_disk_cache.dart';
import 'package:real_estate_mobile/features/properties/data/public_photo_loader.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_editor_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_fullscreen_gallery.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'support/owner_ux_fixtures.dart' show loadUxFixtures;
import 'support/wave6_fakes.dart';
import 'wave6_product_ui_test.dart'
    show pumpWave6, finishWave6, editorSnapshot, textField;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadUxFixtures);
  test(
      'restart offline reuses a cached small variant, never downloads or opens a large one',
      () async {
    final root = await Directory.systemTemp.createTemp('aqer-small-photo-');
    final connection = OfflineConnectionController()..offline();
    final dio = Dio();
    var calls = 0;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      calls++;
      h.reject(DioException(
          requestOptions: r, type: DioExceptionType.connectionError));
    }));
    PublicPhotoDiskCache disk() => PublicPhotoDiskCache(
        origin: Uri.parse('https://fixture.invalid'),
        directory: () async => root);
    const card =
        'https://fixture.invalid/api/property-media/1?variant=card&v=one';
    final first = disk();
    await first.put(
        card,
        Uint8List.fromList([1, 2, 3]),
        Headers.fromMap({
          'cache-control': ['public, max-age=1'],
          'content-type': ['image/jpeg'],
          'etag': ['"one"']
        }),
        expectedEpoch: first.epoch);
    final loader = PublicPhotoLoader(dio, disk(), connection: connection);
    expect(
        (await loader.load(card.replaceAll('variant=card', 'variant=thumb'),
                cancelToken: CancelToken()))
            .bytes,
        [1, 2, 3]);
    await expectLater(
        loader.load(card.replaceAll('variant=card', 'variant=gallery'),
            cancelToken: CancelToken()),
        throwsStateError);
    await expectLater(
        loader.load(card.replaceAll('/1?', '/2?'), cancelToken: CancelToken()),
        throwsStateError);
    expect(calls, 0);
    dio.close();
    connection.dispose();
    await root.delete(recursive: true);
  });
  test(
      'device draft fields and copied photos survive a new store and remain actor scoped',
      () async {
    final root = await Directory.systemTemp.createTemp('aqer-device-draft-');
    final photo = File('${root.path}/input.jpg');
    await photo.writeAsBytes([1, 2, 3, 4]);
    ListingRecoveryStore storage() =>
        ListingRecoveryStore(directory: () async => root);
    final first = storage(), key = 'fc0d4f08-f575-4ed5-aa57-75184a8ef648';
    await first.write(7, null, {
      'draft_key': key,
      'draft_kind': 'saved',
      'offline_prepared': true,
      'fields': {'title': 'مسودة بلا اتصال'}
    }, [
      photo.path
    ]);
    await first.pinExplicitSave(7);
    await photo.delete();
    final restored = (await storage().read(7, null))!;
    expect((restored['fields'] as Map)['title'], 'مسودة بلا اتصال');
    expect(restored['offline_prepared'], true);
    final copied = File((restored['image_paths'] as List).single as String);
    expect(await copied.readAsBytes(), [1, 2, 3, 4]);
    expect(await storage().read(8, null), isNull);
    expect(await storage().saved(7), hasLength(1));
    await root.delete(recursive: true);
  });
  testWidgets(
      'fullscreen offline explains connectivity and creates no zoom pager',
      (tester) async {
    final connection = OfflineConnectionController()..offline();
    await tester.pumpWidget(ProviderScope(
        overrides: [
          offlineConnectionProvider.overrideWith((ref) => connection)
        ],
        child: MaterialApp(
            home: PropertyFullscreenGallery(images: [
          PropertyImageItem.fromJson(
              {'id': 1, 'url': 'https://fixture.invalid/api/property-media/1'})
        ], initialIndex: 0))));
    await tester.pumpAndSettle();
    expect(find.textContaining('فتح الصور الكبيرة'), findsOneWidget);
    expect(find.byType(PageView), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'manual edits save locally offline, survive reopening and never auto-upload on reconnect',
      (tester) async {
    final drafts = Wave6Drafts(),
        recovery = Wave6Recovery({
          ...editorSnapshot(),
          'draft_key': 'fc0d4f08-f575-4ed5-aa57-75184a8ef648',
          'entry_method': 'manual',
          'offline_prepared': true
        });
    final connection = OfflineConnectionController()..offline();
    Widget editor() => ProviderScope(overrides: [
          offlineConnectionProvider.overrideWith((ref) => connection)
        ], child: const ListingEditorScreen());
    await pumpWave6(tester, editor(), drafts: drafts, recovery: recovery);
    await tester.ensureVisible(textField('وصف العقار'));
    await tester.enterText(textField('وصف العقار'), 'تفاصيل كتبت دون إنترنت');
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect((recovery.snapshot!['fields'] as Map)['description'],
        'تفاصيل كتبت دون إنترنت');
    expect(recovery.snapshot!['offline_prepared'], true);
    expect(drafts.saves, isEmpty);
    connection.online();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(drafts.saves, isEmpty);
    expect(find.textContaining('محفوظة على الجهاز'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finishWave6(tester);
  });
}

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/properties/data/public_photo_disk_cache.dart';
import 'package:real_estate_mobile/features/properties/data/public_photo_loader.dart';

const _origin = 'https://fixture.example';
const _url = '$_origin/api/property-media/1?variant=thumb';
Headers _headers({String control = 'public, max-age=86400', String etag = '"revision-one"'}) => Headers.fromMap({
  'cache-control': [control], 'content-type': ['image/jpeg'], 'etag': [etag],
});

void main() {
  late Directory root;
  late DateTime now;
  PublicPhotoDiskCache cache({int entries = 160, int bytes = 48 * 1024 * 1024}) => PublicPhotoDiskCache(
    origin: Uri.parse(_origin), directory: () async => root, clock: () => now, maxEntries: entries, maxBytes: bytes);
  final bytes = Uint8List.fromList([1,2,3,4]);
  setUp(() async { root = await Directory.systemTemp.createTemp('aqer-wave1-public-'); now = DateTime.utc(2026,10,28); });
  tearDown(() async { if (await root.exists()) await root.delete(recursive: true); });

  test('public bytes survive a new cache instance; variant and version identity remain exact', () async {
    final first = cache(); await first.put(_url, bytes, _headers(), expectedEpoch: first.epoch);
    final restarted = cache();
    expect((await restarted.read(_url))!.bytes, bytes);
    expect(await restarted.read('$_origin/api/property-media/1?variant=card'), isNull);
    expect(await restarted.read('$_url&v=updated'), isNull);
    expect(restarted.hits, 1);
  });

  test('private, signed, foreign, unversioned unsafe and no-store responses never persist', () async {
    final store = cache();
    for (final url in ['$_origin/api/listing-editor-drafts/secret/images/secret', '$_url&token=private',
      'https://other.example/api/property-media/1', 'http://fixture.example/api/property-media/1',
      'https://user:password@fixture.example/api/property-media/1', '$_url&variant=detail', '$_url#fragment']) {
      expect(store.eligible(url), isFalse);
      await store.put(url, bytes, _headers(), expectedEpoch: store.epoch);
      expect(await store.read(url), isNull);
    }
    for (final control in ['private, no-store', 'public, no-store', 'public, no-cache', 'max-age=86400', 'public, max-age=0']) {
      await store.put(_url, bytes, _headers(control: control), expectedEpoch: store.epoch);
      expect(await store.read(_url), isNull);
    }
    expect(store.writes, 0);
  });

  test('expiry and size/count limits remove bytes instead of growing without bound', () async {
    final store = cache(entries: 2, bytes: 8);
    for (var id = 1; id <= 3; id++) {
      await store.put('$_origin/api/property-media/$id?variant=thumb', bytes, _headers(), expectedEpoch: store.epoch);
      now = now.add(const Duration(seconds: 1));
    }
    expect(await store.read(_url), isNull);
    expect(await store.read('$_origin/api/property-media/3?variant=thumb'), isNotNull);
    now = now.add(const Duration(days: 2));
    expect(await store.read('$_origin/api/property-media/3?variant=thumb'), isNull);
  });

  test('invalidation rejects a late pre-mutation write', () async {
    final store = cache(), before = cache().epoch;
    await store.clear();
    await store.put(_url, bytes, _headers(), expectedEpoch: before);
    expect(await store.read(_url), isNull);
  });

  test('cold restart validates ETag and ten returns transfer zero identical image bytes', () async {
    final first = cache(); await first.put(_url, bytes, _headers(), expectedEpoch: first.epoch);
    final requests = <RequestOptions>[];
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      requests.add(request);
      handler.resolve(Response<List<int>>(requestOptions: request, statusCode: 304, data: const [], headers: _headers()));
    }));
    var transferred = 0;
    for (var count = 0; count < 10; count++) {
      final result = await PublicPhotoLoader(dio, cache()).load(_url, cancelToken: CancelToken());
      expect(result.bytes, bytes); expect(result.notModified, isTrue); transferred += result.downloadedBytes;
    }
    expect(requests, hasLength(10));
    expect(requests.every((request) => request.headers['If-None-Match'] == '"revision-one"'), isTrue);
    expect(transferred, 0);
    dio.close();
  });

  test('a revoked/deleted public image wins over disk; no stale bytes are returned', () async {
    final store = cache(); await store.put(_url, bytes, _headers(), expectedEpoch: store.epoch);
    final dio = Dio()..interceptors.add(InterceptorsWrapper(onRequest: (request, handler) =>
      handler.resolve(Response<List<int>>(requestOptions: request, statusCode: 404, data: const []))));
    await expectLater(PublicPhotoLoader(dio, store).load(_url, cancelToken: CancelToken()), throwsA(isA<DioException>()));
    expect(await store.read(_url), isNull); dio.close();
  });

  test('superseded image response cannot persist or return a successful transfer', () async {
    final store = cache(), pending = Completer<Response<List<int>>>(), started = Completer<void>();
    final dio = Dio()..interceptors.add(InterceptorsWrapper(onRequest: (request, handler) async {
      started.complete(); handler.resolve(await pending.future);
    }));
    final token = CancelToken();
    final result = PublicPhotoLoader(dio, store).load(_url, cancelToken: token);
    final assertion = expectLater(result, throwsA(isA<DioException>()));
    await started.future; token.cancel('fixture superseded');
    pending.complete(Response<List<int>>(requestOptions: RequestOptions(path: _url), statusCode: 200, data: bytes, headers: _headers()));
    await assertion; expect(await store.read(_url), isNull); dio.close();
  });
}

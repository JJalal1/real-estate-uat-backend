import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/network/api_client.dart';
import 'package:real_estate_mobile/core/network/adaptive_image_policy.dart';
import 'package:real_estate_mobile/core/network/conditional_image_prefetch.dart';
import 'package:real_estate_mobile/core/platform/media_network_monitor.dart';
import 'package:real_estate_mobile/core/widgets/viewport_media.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/properties/presentation/adaptive_property_photo.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_draft_photo.dart';
import 'package:real_estate_mobile/features/properties/data/public_photo_loader.dart';
import 'package:real_estate_mobile/features/properties/data/public_photo_disk_cache.dart';

const _probe = bool.fromEnvironment('AQER_PREFETCH_HTTP_PROBE');
const _expectedEnabled = bool.fromEnvironment('AQER_PREFETCH_EXPECT_ENABLED');
const _wifi = ImageNetworkConditions(metered: false, networkKey: 'synthetic-wifi', transport: 'wifi');
const _png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
class _Guest extends AuthController {
  @override
  Future<AuthUser?> build() async => null;
}
class _Network extends MediaNetworkMonitor {
  _Network(this.current) { policy.recordTransfer(_wifi, 65536, const Duration(milliseconds: 100)); }
  ImageNetworkConditions current;
  @override
  Future<ImageNetworkConditions> snapshot({bool refresh = false}) async => current;
}
Future<void> _frames(WidgetTester tester, [int count = 24]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 35)));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('compiled prefetch experiment stays within the selected UAT configuration', () {
    expect(ConditionalImagePrefetch.enabled, _expectedEnabled);
  });
  test('only same-origin public card derivatives may be speculated', () {
    final origin = Uri.parse('https://fixture.example/api');
    expect(ConditionalImagePrefetch.eligibleUrl('https://fixture.example/api/property-media/3?variant=card&v=approved', origin), isTrue);
    for (final url in ['https://other.example/api/property-media/3?variant=card',
      'https://fixture.example/api/property-media/3?variant=zoom',
      'https://fixture.example/api/property-media/3?variant=card&token=private',
      'https://fixture.example/api/property-media/3?variant=card&variant=thumb',
      'https://fixture.example/api/listing-editor-drafts/private/images/3?variant=card',
      'https://user:password@fixture.example/api/property-media/3?variant=card']) {
      expect(ConditionalImagePrefetch.eligibleUrl(url, origin), isFalse, reason: url);
    }
  });
  test('unmetered alone is insufficient and old or foreign speed samples are refused', () {
    var now = DateTime.utc(2026, 11, 11);
    final policy = AdaptiveImagePolicy(clock: () => now);
    expect(policy.canPrefetch(_wifi), isFalse);
    policy.recordTransfer(_wifi, 65536, const Duration(milliseconds: 100));
    expect(policy.canPrefetch(_wifi), isTrue);
    for (final network in [const ImageNetworkConditions(),
      const ImageNetworkConditions(metered: true, networkKey: 'synthetic-wifi'),
      const ImageNetworkConditions(metered: false, dataSaver: true, networkKey: 'synthetic-wifi'),
      const ImageNetworkConditions(metered: false, networkKey: 'another-network')]) {
      expect(policy.canPrefetch(network), isFalse);
    }
    now = now.add(const Duration(seconds: 61));expect(policy.canPrefetch(_wifi), isFalse);
    policy.recordTransfer(_wifi, 65536, const Duration(seconds: 2));
    expect(policy.canPrefetch(_wifi), isFalse);
  });
  test('a foreground lease promotes pending bytes without another request or cancellation', () async {
    final cache = ListingPhotoCache(), pending = Completer<Uint8List>();
    CancelToken? token;var starts = 0;
    final prefetch = cache.acquire('public:fixture', (cancel) { starts++;token = cancel;return pending.future; }, prefetch: true);
    final visible = cache.acquire('public:fixture', (_) { starts++;return pending.future; });
    expect(cache.hasForegroundLease('public:fixture'), isTrue);
    prefetch.close();expect(token!.isCancelled, isFalse);expect(starts, 1);
    pending.complete(Uint8List.fromList([1, 2, 3]));await visible.future;visible.close();
    final returned = cache.acquire('public:fixture', (_) async => Uint8List.fromList([9]));
    expect(await returned.future, [1, 2, 3]);expect(cache.prefetchReadyHits, 1);
    returned.close();cache.clear();
  });
  test('only two speculative owners can retain bytes in one account scope', () {
    final budget = PhotoPrefetchBudget(), one = Object(), two = Object(), three = Object();
    expect(budget.reserve(one), isTrue);expect(budget.reserve(two), isTrue);
    expect(budget.reserve(three), isFalse);budget.release(one);expect(budget.reserve(three), isTrue);
    budget.dispose();expect(budget.reserve(Object()), isFalse);
  });

  testWidgets('covering a route removes nearby prefetch eligibility', (tester) async {
    final navigator = GlobalKey<NavigatorState>(), nearby = <int, bool>{};
    await tester.pumpWidget(MaterialApp(navigatorKey: navigator, home: Scaffold(body: SizedBox(height: 320,
      child: ListView.builder(itemExtent: 160, cacheExtent: 480, itemCount: 20,
        itemBuilder: (_, i) => ViewportMedia(onPrefetchChanged: (near, _, __) => nearby[i] = near,
          builder: (_) => Text('visible-$i')))))));
    await tester.pump();await tester.pump();await tester.pump();
    expect(nearby.values.any((value) => value), isTrue);
    unawaited(navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('covered')))));
    await tester.pumpAndSettle();
    expect(nearby.values.every((value) => !value), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  test('real HTTP background byte limit cancels speculation and allows a foreground promotion', () async {
    HttpOverrides.global = null;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final origin = 'http://127.0.0.1:${server.port}', bytes = List<int>.filled(1024, 1);
    server.listen((r) async {
      r.response.headers.contentType = ContentType('image', 'png');
      r.response.headers.set('cache-control', 'public, max-age=60');r.response.headers.set('etag', '"fixture"');
      r.response.contentLength = bytes.length;
      try { r.response.add(bytes);await r.response.close(); } catch (_) { /* Expected cancellation. */ }
    });
    final dio = Dio(BaseOptions(baseUrl: '$origin/api'));
    addTearDown(() async {dio.close(force: true);await server.close(force: true);});
    final loader = PublicPhotoLoader(dio, PublicPhotoDiskCache(origin: Uri.parse(origin)));
    final background = CancelToken();
    await expectLater(loader.load('$origin/api/property-media/1?variant=card', cancelToken: background,
      backgroundByteLimit: 128, requirePublicResponse: true), throwsA(isA<DioException>()));
    expect(background.isCancelled, isTrue);
    final foreground = CancelToken();
    final transferred = await loader.load('$origin/api/property-media/1?variant=card', cancelToken: foreground,
      backgroundByteLimit: 128, foregroundAttached: () => true, requirePublicResponse: true);
    expect(foreground.isCancelled, isFalse);expect(transferred.bytes.length, 1024);
  }, skip: !_probe, timeout: const Timeout(Duration(minutes: 1)));

  for (final enabled in [false, true]) {
    testWidgets('real HTTP ${enabled ? 'ON' : 'OFF'} compares ahead bytes and ready images on arrival', (tester) async {
      HttpOverrides.global = null;
      tester.view.physicalSize = const Size(390, 320);tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
      final server = await tester.runAsync(() => HttpServer.bind(InternetAddress.loopbackIPv4, 0));
      final origin = 'http://127.0.0.1:${server!.port}', png = base64Decode(_png);
      final requested = <int>[];var bytes = 0;
      server.listen((request) async {
        requested.add(int.parse(request.uri.pathSegments.last));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.headers.set('cache-control', 'public, max-age=60');
        request.response.headers.set('etag', '"synthetic"');
        bytes += png.length;request.response.add(png);
        try { await request.response.close(); } catch (_) { /* A departed candidate can cancel. */ }
      });
      final dio = Dio(BaseOptions(baseUrl: '$origin/api')), scroll = ScrollController();
      final container = ProviderContainer(overrides: [
        dioProvider.overrideWithValue(dio), authControllerProvider.overrideWith(_Guest.new),
        conditionalPrefetchEnabledProvider.overrideWithValue(enabled),
        mediaNetworkMonitorProvider.overrideWithValue(_Network(_wifi)),
      ]);
      var fixtureClosed = false;
      Future<void> closeFixture() async {
        if (fixtureClosed) return;
        fixtureClosed = true;
        container.dispose();scroll.dispose();dio.close(force: true);
        await server.close(force: true);
      }
      addTearDown(closeFixture);
      try {
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp(home: Scaffold(
        body: ListView.builder(controller: scroll, padding: EdgeInsets.zero, cacheExtent: 480,
          itemExtent: 160, itemCount: 20, itemBuilder: (_, i) => SizedBox(key: ValueKey('card-${i+1}'),
            child: AdaptivePropertyPhoto(url: '$origin/api/property-media/${i+1}?variant=card')))))));
      await _frames(tester);
      final initial = requested.length, initialBytes = bytes;
      expect(initial, enabled ? 4 : 2);expect(requested.where((id) => id > 4), isEmpty);
      final beforeArrival = requested.where((id) => id == 3 || id == 4).length;
      scroll.jumpTo(320);await tester.pump();await tester.pump();
      final readyOnArrival = find.descendant(of: find.byKey(const ValueKey('card-3')), matching: find.byType(Image)).evaluate().length;
      expect(readyOnArrival, enabled ? 1 : 0);
      await _frames(tester, 12);
      final afterArrival = requested.where((id) => id == 3 || id == 4).length;
      expect(afterArrival - beforeArrival, enabled ? 0 : 2);
      expect(requested.where((id) => id == 3).length, 1);
      final cache = container.read(listingPhotoCacheProvider);
      if (enabled) expect(cache.prefetchReadyHits, greaterThanOrEqualTo(2));
      stdout.writeln('AQER_PREFETCH_HTTP ${jsonEncode({'enabled': enabled, 'synthetic_network_condition': 'fresh fast unmetered',
        'initial_requests': initial, 'initial_payload_bytes': initialBytes,
        'extra_visible_requests_on_arrival': afterArrival-beforeArrival, 'ready_image_on_arrival': readyOnArrival,
        'prefetch_requests': cache.prefetchRequests, 'prefetch_payload_bytes': cache.prefetchBytes,
        'prefetch_ready_hits': cache.prefetchReadyHits})}');
      } finally {
        await tester.pumpWidget(const SizedBox());await tester.pump();
        await closeFixture();
      }
    }, skip: !_probe, timeout: const Timeout(Duration(minutes: 2)));
  }
  for (final entry in <String, ImageNetworkConditions>{
    'data_saver': const ImageNetworkConditions(metered: false, dataSaver: true, networkKey: 'synthetic-wifi'),
    'metered': const ImageNetworkConditions(metered: true, networkKey: 'synthetic-wifi'),
    'unknown': const ImageNetworkConditions(),
  }.entries) {
    testWidgets('real HTTP blocks speculative bytes for ${entry.key}', (tester) async {
      HttpOverrides.global = null;
      tester.view.physicalSize = const Size(390, 320);tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
      final server = await tester.runAsync(() => HttpServer.bind(InternetAddress.loopbackIPv4, 0));
      final origin = 'http://127.0.0.1:${server!.port}', png = base64Decode(_png);
      final requested = <int>[];
      server.listen((r) async { requested.add(int.parse(r.uri.pathSegments.last));r.response.headers.contentType=ContentType('image','png');r.response.add(png);await r.response.close(); });
      final dio=Dio(BaseOptions(baseUrl:'$origin/api'));
      final container=ProviderContainer(overrides:[dioProvider.overrideWithValue(dio),
        authControllerProvider.overrideWith(_Guest.new),conditionalPrefetchEnabledProvider.overrideWithValue(true),
        mediaNetworkMonitorProvider.overrideWithValue(_Network(entry.value))]);
      var fixtureClosed = false;
      Future<void> closeFixture() async {
        if (fixtureClosed) return;
        fixtureClosed = true;
        container.dispose();dio.close(force: true);
        await server.close(force: true);
      }
      addTearDown(closeFixture);
      try {
      await tester.pumpWidget(UncontrolledProviderScope(container:container,child:MaterialApp(home:Scaffold(body:ListView.builder(
        padding:EdgeInsets.zero,cacheExtent:480,itemExtent:160,itemCount:20,itemBuilder:(_,i)=>AdaptivePropertyPhoto(url:'$origin/api/property-media/${i+1}?variant=card'))))));
      await _frames(tester);expect(requested.toSet(),{1,2});expect(requested.length,2);
      expect(container.read(listingPhotoCacheProvider).prefetchRequests,0);
      stdout.writeln('AQER_PREFETCH_BLOCKED ${jsonEncode({'condition':entry.key,'image_requests':requested.length,'speculative_requests':0})}');
      } finally {
        await tester.pumpWidget(const SizedBox());await tester.pump();
        await closeFixture();
      }
    },skip:!_probe,timeout:const Timeout(Duration(minutes:2)));
  }
}

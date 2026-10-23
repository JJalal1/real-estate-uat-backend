import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/network/api_client.dart';
import 'package:real_estate_mobile/core/platform/media_network_monitor.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_repository.dart';
import 'package:real_estate_mobile/features/discovery/presentation/marketplace_home_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/adaptive_property_photo.dart';

const _png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
const _enabled = bool.fromEnvironment('AQER_VIEWPORT_HTTP_PROBE');
const _required = bool.fromEnvironment('AQER_EXPECT_VIEWPORT_GATING', defaultValue: true);

class _Guest extends AuthController {
  @override
  Future<AuthUser?> build() async => null;
}

Future<void> _networkFrames(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 70)));
  }
}

Widget _app(Dio dio, Widget child) => ProviderScope(overrides: [
  dioProvider.overrideWithValue(dio),
  authControllerProvider.overrideWith(_Guest.new),
  homeLocationAttemptedProvider.overrideWith((_) => true),
], child: MaterialApp(home: Directionality(textDirection: TextDirection.rtl, child: child)));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    HttpOverrides.global = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      MediaNetworkMonitor.channel, (_) async => {'metered': true, 'networkKey': 'measurement', 'transport': 'cellular'});
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MediaNetworkMonitor.channel, null));

  testWidgets('count actual home HTTP requests before and after viewport loading', (tester) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final server = await tester.runAsync(() => HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    final origin = 'http://127.0.0.1:${server!.port}';
    final requested = <String>[];
    var feedRequests = 0, bytes = 0;
    final png = base64Decode(_png);
    server.listen((request) async {
      if (request.uri.path == '/api/marketplace') {
        feedRequests++;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'data': {
          'context': {'label': 'منطقة اختبار'}, 'section_order': ['spotlight', 'latest', 'sale', 'rent'], 'brokers': [],
          'sections': {for (var s = 0; s < 4; s++) ['spotlight', 'latest', 'sale', 'rent'][s]: [
            for (var i = 0; i < 6; i++) {'id': 100 + s * 10 + i, 'title': 'عقار اصطناعي', 'status': 'published',
              'type': 'apartment', 'purpose': 'sale', 'price': 100, 'currency': 'YER',
              'main_image': '$origin/api/property-media/${100 + s * 10 + i}?variant=card'}
          ]},
        }}));
      } else if (request.uri.path.startsWith('/api/property-media/')) {
        requested.add(request.uri.path);
        bytes += png.length;
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(png);
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
    final dio = Dio(BaseOptions(baseUrl: '$origin/api'));
    addTearDown(() async { dio.close(force: true); await server.close(force: true); });
    await tester.pumpWidget(_app(dio, const MarketplaceHomeScreen()));
    await _networkFrames(tester, frames: 14);
    final initial = requested.length, initialBytes = bytes;
    final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    position.jumpTo(position.maxScrollExtent);
    await _networkFrames(tester);
    final afterFastScroll = requested.length;
    position.jumpTo(0);
    await _networkFrames(tester);
    final returnRequests = requested.length - afterFastScroll;
    final report = {'network': 'real loopback HTTP, synthetic PNG only', 'gating_required': _required,
      'feed_requests': feedRequests, 'initial_image_requests': initial, 'initial_image_bytes': initialBytes,
      'after_fast_scroll_requests': afterFastScroll, 'return_image_requests': returnRequests,
      'unique_image_requests': requested.toSet().length, 'total_image_bytes': bytes};
    if (_required) {
      expect(initial, inInclusiveRange(1, 2));
      expect(requested.where((path) => path.endsWith('/120')), isEmpty, reason: 'fast scrolling skips an unseen middle section');
      expect(returnRequests, 0);
    }
    expect(feedRequests, 1);
    expect(tester.takeException(), isNull);
    stdout.writeln('AQER_VIEWPORT_HTTP ${jsonEncode(report)}');
    await tester.runAsync(() => File('viewport-http-metrics.json').writeAsString(jsonEncode(report)));
    await tester.pumpWidget(const SizedBox());
    dio.close(force: true);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(seconds: 4));
  }, skip: !_enabled, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('count real UAT image HTTP transfers for hidden images and return', (tester) async {
    tester.view.physicalSize = const Size(390, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dio = Dio(BaseOptions(baseUrl: 'https://real-estate-uat-api-frankfurt.onrender.com/api',
      connectTimeout: const Duration(seconds: 80), receiveTimeout: const Duration(seconds: 80)));
    addTearDown(() => dio.close(force: true));
    final urls = <String>[];
    await tester.runAsync(() async {
      for (final id in [60, 61, 62]) {
        final data = (await dio.get<dynamic>('/properties/$id')).data['data'] as Map;
        expect(data['status'], 'published');
        urls.add((data['images'] as List).first['url'] as String);
      }
    });
    var requests = 0, bytes = 0, completed = 0;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      if (o.uri.path.contains('/property-media/')) requests++;
      h.next(o);
    }, onResponse: (r, h) {
      if (r.data is List<int>) { bytes += (r.data as List<int>).length; completed++; }
      h.next(r);
    }));
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(_app(dio, Scaffold(body: SingleChildScrollView(controller: scroll, child: Column(children: [
      for (var i = 0; i < urls.length; i++) ...[
        SizedBox(height: 150, child: AdaptivePropertyPhoto(url: urls[i])),
        const SizedBox(height: 900),
      ],
    ])))));
    await _networkFrames(tester, frames: 45);
    for (var i = 0; i < 900 && completed < (_required ? 1 : 3); i++) {
      await _networkFrames(tester, frames: 1);
    }
    expect(completed, _required ? 1 : 3);
    final initial = requests, initialBytes = bytes;
    scroll.jumpTo(1000);
    await _networkFrames(tester, frames: 30);
    for (var i = 0; i < 900 && completed < (_required ? 2 : 3); i++) {
      await _networkFrames(tester, frames: 1);
    }
    expect(completed, _required ? 2 : 3);
    final afterScroll = requests;
    scroll.jumpTo(0);
    await _networkFrames(tester, frames: 12);
    final report = {'network': 'real UAT Laravel to private Supabase Storage', 'gating_required': _required,
      'initial_image_requests': initial, 'initial_image_bytes': initialBytes,
      'after_scroll_requests': afterScroll, 'return_image_requests': requests - afterScroll, 'total_image_bytes': bytes};
    if (_required) { expect(initial, 1); expect(afterScroll, 2); expect(requests - afterScroll, 0); }
    expect(initialBytes, greaterThan(0));
    expect(tester.takeException(), isNull);
    stdout.writeln('AQER_VIEWPORT_UAT ${jsonEncode(report)}');
    await tester.runAsync(() => File('viewport-uat-metrics.json').writeAsString(jsonEncode(report)));
    await tester.pumpWidget(const SizedBox());
    dio.close(force: true);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(seconds: 4));
  }, skip: !_enabled, timeout: const Timeout(Duration(minutes: 5)));
}

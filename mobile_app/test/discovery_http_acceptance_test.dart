import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/network/api_client.dart';
import 'package:real_estate_mobile/core/widgets/app_components.dart';
import 'package:real_estate_mobile/features/discovery/presentation/marketplace_section_screen.dart';
import 'package:real_estate_mobile/features/discovery/presentation/smart_search_assistant.dart';

const _enabled = bool.fromEnvironment('AQER_DISCOVERY_HTTP_PROBE');
class _NoHint extends AssistantHintStore {
  @override
  Future<bool> take() async => false;
}
Future<void> _frames(WidgetTester tester, {int count = 8}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
  }
}
Map<String, dynamic> _row(int id) => {'id': id, 'title': 'عقار HTTP اصطناعي $id', 'type': 'house',
  'purpose': 'sale', 'price': 100, 'currency': 'YER', 'status': 'published', 'images': []};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => HttpOverrides.global = null);

  testWidgets('actual HTTP delayed load, 503 refresh, exact retry, pagination and zero results', (tester) async {
    tester.view.physicalSize = const Size(390, 900); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final server = await tester.runAsync(() => HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    final initial = Completer<void>();
    final pages = <int>[]; var fail = false;
    server!.listen((request) async {
      final page = int.tryParse(request.uri.queryParameters['page'] ?? '') ?? 1;
      pages.add(page);
      if (pages.length == 1) await initial.future;
      request.response.headers.contentType = ContentType.json;
      if (fail) { request.response.statusCode = 503; request.response.write(jsonEncode({'message': 'Synthetic outage'})); }
      else {
        final empty = request.uri.queryParameters['type'] == 'land';
        request.response.write(jsonEncode({'data': empty ? [] : [_row(7001), if (page == 2) _row(7002)],
          'meta': {'current_page': page, 'last_page': empty ? 1 : 2}}));
      }
      await request.response.close();
    });
    final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${server.port}/api'));
    addTearDown(() async { dio.close(force: true); await server.close(force: true); });
    Widget app({String? type}) => ProviderScope(overrides: [dioProvider.overrideWithValue(dio),
      assistantHintStoreProvider.overrideWithValue(_NoHint())], child: MaterialApp(home: MarketplaceSectionScreen(type: type)));
    await tester.pumpWidget(app()); await _frames(tester, count: 4);
    expect(find.byType(AppSkeleton), findsOneWidget);
    expect(find.byType(AppEmptyState), findsNothing);
    initial.complete(); await _frames(tester);
    expect(find.text('عقار HTTP اصطناعي 7001'), findsOneWidget);
    fail = true;
    final refresh = tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh();
    await tester.pump();
    expect(find.text('عقار HTTP اصطناعي 7001'), findsOneWidget);
    await _frames(tester); await refresh;
    expect(find.text('عقار HTTP اصطناعي 7001'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('إعادة المحاولة')); await _frames(tester);
    expect(pages, [1, 1, 1]);
    await tester.ensureVisible(find.text('المزيد من العقارات'));
    await tester.tap(find.text('المزيد من العقارات')); await _frames(tester);
    expect(pages, [1, 1, 1, 2]);
    expect(find.text('عقار HTTP اصطناعي 7001'), findsOneWidget);
    expect(find.text('عقار HTTP اصطناعي 7002'), findsOneWidget);
    expect(find.text('المزيد من العقارات'), findsNothing);
    await tester.pumpWidget(app(type: 'land')); await _frames(tester);
    expect(find.byType(AppEmptyState), findsOneWidget);
    expect(find.text('عقار HTTP اصطناعي 7001'), findsNothing);
    expect(pages, [1, 1, 1, 2, 1]);
    final report = {'network': 'actual loopback HTTP with deliberate delayed response and HTTP 503',
      'http_requests': pages.length, 'pages': pages, 'retained_during_refresh': true,
      'retry_failed_page': 1, 'unique_paginated_rows': 2, 'extra_requests_after_end': 0, 'empty_result_state': true};
    stdout.writeln('AQER_LOADING_HTTP ${jsonEncode(report)}');
    await tester.runAsync(() => File('viewport-loading-http-metrics.json').writeAsString(jsonEncode(report)));
    await tester.pumpWidget(const SizedBox()); dio.close(force: true);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
  }, skip: !_enabled, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('live UAT Arabic search, disjoint pages, empty results and access/error contracts', (tester) async {
    final dio = Dio(BaseOptions(baseUrl: 'https://real-estate-uat-api-frankfurt.onrender.com/api',
      connectTimeout: const Duration(seconds: 80), receiveTimeout: const Duration(seconds: 80)));
    addTearDown(() => dio.close(force: true));
    final times = <int>[]; var calls = 0;
    Future<Response<dynamic>> get(String path, {Map<String, dynamic>? query}) async {
      final watch = Stopwatch()..start();
      final response = await dio.get<dynamic>(path, queryParameters: query, options: Options(validateStatus: (_) => true));
      times.add(watch.elapsedMilliseconds); calls++; return response;
    }
    late Map<String, dynamic> report;
    await tester.runAsync(() async {
      final health = await get('/health'); expect(health.statusCode, 200);
      final pages = <Set<int>>[];
      for (var page = 1; page <= 2; page++) {
        final response = await get('/properties', query: {'page': page, 'per_page': 5, 'sort': 'latest'});
        expect(response.statusCode, 200);
        final data = response.data['data'] as List;
        expect(data, hasLength(5));
        expect(data.every((row) => row['status'] == 'published'), isTrue);
        pages.add(data.map((r) => (r['id'] as num).toInt()).toSet());
      }
      expect(pages[0].intersection(pages[1]), isEmpty);
      Future<Set<int>> arabic(String search) async {
        final response = await get('/properties', query: {'search': search, 'per_page': 50});
        expect(response.statusCode, 200);
        return (response.data['data'] as List).map((r) => (r['id'] as num).toInt()).toSet();
      }
      final canonical = await arabic('إب'), normalized = await arabic('اب');
      expect(canonical, isNotEmpty); expect(normalized, canonical);
      final empty = await arabic('aqer_synthetic_no_results_1024'); expect(empty, isEmpty);
      final denied = <int>[];
      for (final path in ['/messages/threads', '/listing-editor-drafts', '/notifications', '/admin/support/summary']) {
        final response = await get(path); denied.add(response.statusCode!); expect(response.statusCode, 401);
      }
      final unavailable = await get('/properties/2147483647'); expect(unavailable.statusCode, 404);
      final invalid = await get('/properties/nearby', query: {'latitude': 999, 'longitude': 44}); expect(invalid.statusCode, 422);
      report = {'network': 'real Render UAT Laravel API, read only; no account token', 'http_requests': calls,
        'pagination_rows': pages.map((p) => p.length).toList(), 'pagination_overlap': 0,
        'arabic_normalization_same_ids': true, 'arabic_result_count': canonical.length, 'empty_count': empty.length,
        'protected_get_statuses': denied, 'unavailable_status': unavailable.statusCode, 'invalid_coordinates_status': invalid.statusCode,
        'latency_ms': times};
    });
    stdout.writeln('AQER_DISCOVERY_UAT ${jsonEncode(report)}');
    await tester.runAsync(() => File('viewport-discovery-uat-metrics.json').writeAsString(jsonEncode(report)));
    dio.close(force: true);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(seconds: 4));
  }, skip: !_enabled, timeout: const Timeout(Duration(minutes: 8)));
}

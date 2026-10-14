import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/network/public_startup_read.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_repository.dart';
import 'package:real_estate_mobile/features/discovery/presentation/marketplace_home_screen.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';

import 'support/wave3_fakes.dart';

const query = (latitude: 15.3694, longitude: 44.1910,
  governorate: 'صنعاء', type: null, device: false);

Dio mockDio(void Function(RequestOptions, RequestInterceptorHandler) respond) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid/api'));
  dio.interceptors.add(InterceptorsWrapper(onRequest: respond));
  return dio;
}

void reject(RequestOptions options, RequestInterceptorHandler handler, int code) {
  handler.reject(DioException(requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response<Map<String, dynamic>>(requestOptions: options,
      statusCode: code, data: const {'message': 'Service Unavailable'})));
}

void main() {
  test('temporary gateway failure recovers the exact anonymous query', () async {
    final calls = <RequestOptions>[];
    final dio = mockDio((o, h) {
      calls.add(o);
      if (calls.length == 1) { reject(o, h, 503); return; }
      h.resolve(Response<Map<String, dynamic>>(requestOptions: o, statusCode: 200,
        data: const {'data': {'context': {'label': 'تعز'}, 'sections': {}}}));
    });
    addTearDown(dio.close);
    final reader = PublicStartupRead(dio, enabled: true, retryDelays: const [Duration.zero]);
    final result = await reader.get('/marketplace', queryParameters: {'governorate': 'تعز', 'type': 'apartment'});
    expect(result.statusCode, 200); expect(calls, hasLength(2));
    expect(calls.every((o) => o.method == 'GET' && !o.headers.containsKey('Authorization')), isTrue);
    expect(calls.last.queryParameters, {'governorate': 'تعز', 'type': 'apartment'});
  });

  for (final code in [401, 403, 422, 500]) {
    test('HTTP $code is returned without automatic repetition', () async {
      var calls = 0;
      final dio = mockDio((o, h) { calls++; reject(o, h, code); });
      addTearDown(dio.close);
      final reader = PublicStartupRead(dio, enabled: true, retryDelays: const [Duration.zero]);
      await expectLater(reader.get('/marketplace'), throwsA(isA<DioException>()));
      expect(calls, 1);
    });
  }

  test('gateway retries have a finite attempt count and never apply to writes', () async {
    final methods = <String>[];
    final dio = mockDio((o, h) { methods.add(o.method); reject(o, h, 503); });
    addTearDown(dio.close);
    final reader = PublicStartupRead(dio, enabled: true,
      retryDelays: const [Duration.zero, Duration.zero]);
    await expectLater(reader.get('/marketplace'), throwsA(isA<DioException>()));
    expect(methods, ['GET', 'GET', 'GET']);
    await expectLater(dio.post('/ai/search'), throwsA(isA<DioException>()));
    expect(methods, ['GET', 'GET', 'GET', 'POST']);
  });

  test('normal environment retains the original single request behavior', () async {
    var calls = 0;
    final dio = mockDio((o, h) { calls++; reject(o, h, 503); });
    addTearDown(dio.close);
    await expectLater(PublicStartupRead(dio, enabled: false).get('/marketplace'),
      throwsA(isA<DioException>()));
    expect(calls, 1);
  });

  testWidgets('cancelling a retry wait stops new requests and releases its timer', (tester) async {
    final reached = Completer<void>(); var calls = 0;
    final dio = mockDio((o, h) { calls++; reject(o, h, 503); reached.complete(); });
    addTearDown(dio.close);
    final token = CancelToken();
    final pending = PublicStartupRead(dio, enabled: true,
      retryDelays: const [Duration(seconds: 20)]).get('/marketplace', cancelToken: token);
    final checked = expectLater(pending, throwsA(isA<DioException>()
      .having((e) => e.type, 'type', DioExceptionType.cancel)));
    await tester.pump(); await reached.future; await tester.pump();
    token.cancel('Left home'); await tester.pump(); await checked;
    await tester.pump(const Duration(seconds: 30)); expect(calls, 1);
  });

  testWidgets('one overall startup deadline cancels a stalled request', (tester) async {
    var calls = 0;
    final dio = mockDio((o, h) { calls++; });
    addTearDown(dio.close);
    final token = CancelToken();
    final pending = PublicStartupRead(dio, enabled: true,
      budget: const Duration(seconds: 10)).get('/marketplace', cancelToken: token);
    final checked = expectLater(pending, throwsA(isA<DioException>()
      .having((e) => e.type, 'type', DioExceptionType.receiveTimeout)));
    await tester.pump(); await tester.pump(const Duration(seconds: 10));
    await tester.pump(); await checked;
    expect(token.isCancelled, isTrue); expect(calls, 1);
  });

  testWidgets('successful feed survives short tab trips and expires', (tester) async {
    final fake = Wave3MarketplaceFake();
    final container = ProviderContainer(overrides: [marketplaceRepositoryProvider.overrideWithValue(fake)]);
    addTearDown(container.dispose);
    final provider = marketplaceFeedProvider(query);
    final first = container.listen(provider, (_, __) {});
    await container.read(provider.future); first.close(); await tester.pump();
    final second = container.listen(provider, (_, __) {});
    await container.read(provider.future); expect(fake.queries, hasLength(1));
    second.close(); await tester.pump();
    await tester.pump(const Duration(seconds: 46)); await tester.pump();
    final third = container.listen(provider, (_, __) {});
    await container.read(provider.future); expect(fake.queries, hasLength(2));
    third.close();
  });

  testWidgets('manual refresh, property revisions and different regions invalidate reuse', (tester) async {
    final fake = Wave3MarketplaceFake();
    final container = ProviderContainer(overrides: [marketplaceRepositoryProvider.overrideWithValue(fake)]);
    addTearDown(container.dispose);
    final provider = marketplaceFeedProvider(query);
    final sub = container.listen(provider, (_, __) {});
    await container.read(provider.future);
    container.invalidate(provider); await tester.pump(); await container.read(provider.future);
    container.read(propertyDataRevisionProvider.notifier).state++;
    await tester.pump(); await container.read(provider.future);
    final elsewhere = marketplaceFeedProvider((latitude: 13.58, longitude: 44.02,
      governorate: 'تعز', type: 'house', device: false));
    final other = container.listen(elsewhere, (_, __) {});
    await container.read(elsewhere.future);
    expect(fake.queries, hasLength(4)); expect(fake.queries.last.governorate, 'تعز');
    expect(fake.queries.last.type, 'house');
    other.close(); sub.close();
  });

  testWidgets('leaving an unfinished feed cancels and ignores a late response', (tester) async {
    final answer = Completer<MarketplaceFeed>();
    final fake = Wave3MarketplaceFake(onFeed: (_) => answer.future);
    final container = ProviderContainer(overrides: [marketplaceRepositoryProvider.overrideWithValue(fake)]);
    addTearDown(container.dispose);
    final provider = marketplaceFeedProvider(query);
    final sub = container.listen(provider, (_, __) {});
    final pending = container.read(provider.future);
    final checked = expectLater(pending, throwsA(isA<DioException>()));
    sub.close(); await tester.pump(); await tester.pump();
    expect(fake.cancelTokens.single!.isCancelled, isTrue);
    answer.complete(const MarketplaceFeed(label: 'صنعاء'));
    await tester.pump(); await checked;
  });

  testWidgets('failed reads are not retained when leaving and returning', (tester) async {
    final fake = Wave3MarketplaceFake(onFeed: (_) async => throw DioException(
      requestOptions: RequestOptions(path: '/marketplace'), type: DioExceptionType.connectionError));
    final container = ProviderContainer(overrides: [marketplaceRepositoryProvider.overrideWithValue(fake)]);
    addTearDown(container.dispose);
    final provider = marketplaceFeedProvider(query);
    final first = container.listen(provider, (_, __) {});
    await expectLater(container.read(provider.future), throwsA(isA<DioException>()));
    first.close(); await tester.pump(); await tester.pump();
    final second = container.listen(provider, (_, __) {});
    await expectLater(container.read(provider.future), throwsA(isA<DioException>()));
    expect(fake.queries, hasLength(2)); second.close();
  });

  testWidgets('failed refresh keeps the last successful cards with a clear warning', (tester) async {
    var calls = 0;
    final fake = Wave3MarketplaceFake(onFeed: (_) async {
      calls++;
      if (calls > 1) throw DioException(requestOptions: RequestOptions(path: '/marketplace'),
        type: DioExceptionType.connectionError);
      return MarketplaceFeed(label: 'صنعاء', sections: {'latest': [wave3Property(11)]});
    });
    await tester.pumpWidget(ProviderScope(overrides: [
      marketplaceRepositoryProvider.overrideWithValue(fake),
      homeLocationAttemptedProvider.overrideWith((_) => true),
    ], child: MaterialApp(theme: AppTheme.light, home: const MarketplaceHomeScreen())));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(MarketplaceHomeScreen)));
    container.invalidate(marketplaceFeedProvider((latitude: 15.3694, longitude: 44.1910,
      governorate: null, type: null, device: false)));
    await tester.pumpAndSettle();
    expect(calls, 2); expect(find.byKey(const ValueKey('home-property-11')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-refresh-error')), findsOneWidget);
    expect(find.text('تعذّر تحديث العقارات الآن. نعرض آخر تحميل ناجح.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home explains a slow request while search remains usable', (tester) async {
    final answer = Completer<MarketplaceFeed>();
    final fake = Wave3MarketplaceFake(onFeed: (_) => answer.future);
    await tester.pumpWidget(ProviderScope(overrides: [
      marketplaceRepositoryProvider.overrideWithValue(fake),
      homeLocationAttemptedProvider.overrideWith((_) => true),
    ], child: MaterialApp(theme: AppTheme.light, home: const MarketplaceHomeScreen())));
    await tester.pump(); await tester.pump(const Duration(seconds: 7));
    expect(find.text('الاتصال يستغرق وقتًا أطول. نحاول تحميل العقارات تلقائيًا…'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-ai-send')), findsOneWidget);
    expect(find.text('تعذر تحميل المحتوى'), findsNothing);
    answer.complete(MarketplaceFeed(label: 'صنعاء', sections: {'latest': [wave3Property(11)]}));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-property-11')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-loading-message')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

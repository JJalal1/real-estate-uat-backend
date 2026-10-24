import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';

void main() {
  test('cancelled nearby request never returns cached results', () async {
    var hits = 0;
    final dio = Dio()..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      hits++;
      handler.resolve(Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: <String, dynamic>{'data': <Map<String, dynamic>>[
          {'id': 7, 'title': 'عقار اختباري', 'price': 1500, 'currency': 'YER',
            'latitude': 15.36, 'longitude': 44.19, 'distance_km': 1},
        ]},
      ));
    }));
    addTearDown(() => dio.close(force: true));
    final repo = PropertyRepository(dio, AuthRepository(dio));
    final first = await repo.nearby(latitude: 15.36, longitude: 44.19);
    expect(first.single.id, 7);
    expect(hits, 1);

    final cancelled = CancelToken()..cancel('Viewport replaced');
    await expectLater(
      repo.nearby(latitude: 15.36, longitude: 44.19, cancelToken: cancelled),
      throwsA(isA<DioException>()),
    );
    expect(hits, 1);
    final reuse = await repo.nearby(latitude: 15.36, longitude: 44.19);
    expect(reuse.single.id, 7);
    expect(hits, 1);
  });

  test('cancelled search page cannot use cached page while a new page succeeds', () async {
    var hits = 0;
    final dio = Dio()..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      hits++;
      final page = int.tryParse(options.queryParameters['page'].toString()) ?? 1;
      handler.resolve(Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: <String, dynamic>{
          'data': <Map<String, dynamic>>[
            {'id': page, 'title': 'عقار اختباري $page', 'price': 1500,
              'purpose': 'sale', 'type': 'land', 'status': 'published', 'currency': 'YER'},
          ],
          'meta': {'current_page': page, 'last_page': 2},
        },
      ));
    }));
    addTearDown(() => dio.close(force: true));
    final repo = PropertyRepository(dio, AuthRepository(dio));
    final first = await repo.searchListings({'type': 'land'});
    expect(first.$1.single.id, 1);
    final cancelled = CancelToken()..cancel('Search superseded');
    await expectLater(repo.searchListings({'type': 'land'}, cancelToken: cancelled),
      throwsA(isA<DioException>()));
    final second = await repo.searchListings({'type': 'land'}, page: 2);
    expect(second.$1.single.id, 2);
    expect(hits, 2);
  });

  test('late cancelled response cannot populate cache', () async {
    final pending = Completer<void>();
    final enteredInterceptor = Completer<void>();
    var hits = 0;
    final dio = Dio()..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) async {
      hits++;
      if (hits == 1) {
        // This must be an in-flight cancellation, not a request rejected
        // before Dio's interceptor ever starts.
        enteredInterceptor.complete();
        await pending.future;
      }
      handler.resolve(Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: <String, dynamic>{'data': <Map<String, dynamic>>[]},
      ));
    }));
    addTearDown(() => dio.close(force: true));
    final repo = PropertyRepository(dio, AuthRepository(dio));
    final cancel = CancelToken();
    final old = repo.nearbyFiltered({'latitude': 15.36, 'longitude': 44.19}, cancelToken: cancel);
    await enteredInterceptor.future.timeout(const Duration(seconds: 5));
    expect(hits, 1);
    cancel.cancel('Map changed');
    pending.complete();
    await expectLater(old, throwsA(isA<DioException>()));
    await repo.nearbyFiltered({'latitude': 15.36, 'longitude': 44.19});
    expect(hits, 2);
  });
}

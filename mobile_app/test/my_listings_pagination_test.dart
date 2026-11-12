import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/local/stage6_secure_session_store.dart';
import 'package:real_estate_mobile/core/network/api_client.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/core/widgets/app_components.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/data/account_request_scope.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/my_listings_page.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/properties/presentation/my_listings_screen.dart';

AuthUser _user(int id) => AuthUser.fromJson({
  'id': id, 'name': 'Synthetic broker $id', 'account_type': 'broker',
  'account_status': 'active',
});

class _Auth extends AuthController {
  @override
  Future<AuthUser?> build() async => _user(6);
  void change(int? id) => state = AsyncData(id == null ? null : _user(id));
}

class _Credentials implements AuthRepository {
  Completer<void>? pending;
  @override
  Future<Options> requiredAuthOptions() async {
    if (pending != null) await pending!.future;
    return Options(headers: {'Authorization': 'Bearer synthetic-only'});
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}

Map<String, dynamic> _listing(int id, {String? title, String review = 'draft'}) => {
  'id': id, 'title': title ?? 'Synthetic listing $id', 'type': 'house',
  'purpose': 'sale', 'status': review == 'approved' ? 'published' : 'draft',
  'review_status': review, 'is_owner': true, 'images': <Object>[],
};

Map<String, dynamic> _page(int page, List<Map<String, dynamic>> rows,
    {int last = 1, int? total}) => {
  'data': rows,
  'meta': {'current_page': page, 'last_page': last, 'per_page': 50,
    'total': total ?? rows.length},
};

MyListingsPage _model(int page, List<int> ids, {int last = 2}) => MyListingsPage(
  items: ids.map((id) => PropertyDetails.fromJson(_listing(id))).toList(),
  currentPage: page, lastPage: last, total: 51,
);

DioException _failure([int status = 503, RequestOptions? request]) => DioException(
  requestOptions: request ?? RequestOptions(), type: DioExceptionType.badResponse,
  response: Response(requestOptions: request ?? RequestOptions(), statusCode: status),
);

class _Wire {
  _Wire(this.respond) {
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) async {
      requests.add(request);
      try {
        handler.resolve(Response<Map<String, dynamic>>(
          requestOptions: request, statusCode: 200, data: await respond(request)));
      } on DioException catch (error) {
        handler.reject(error);
      }
    }));
  }
  final Future<Map<String, dynamic>> Function(RequestOptions) respond;
  final dio = Dio(BaseOptions(baseUrl: 'https://synthetic.invalid/api'));
  final requests = <RequestOptions>[];
  List<int> get pages => requests.map((r) => r.queryParameters['page'] as int).toList();
}

Future<ProviderContainer> _container(_Wire wire, {_Credentials? credentials}) async {
  final container = ProviderContainer(overrides: [
    authControllerProvider.overrideWith(_Auth.new),
    authRepositoryProvider.overrideWithValue(credentials ?? _Credentials()),
    dioProvider.overrideWithValue(wire.dio),
  ]);
  await container.read(authControllerProvider.future);
  addTearDown(() { container.dispose(); wire.dio.close(force: true); });
  return container;
}

Future<void> _flush() async {
  for (var index = 0; index < 8; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

MyListingsPagesController _controller(Future<MyListingsPage> Function(int) load) {
  final controller = MyListingsPagesController(load: load, signedIn: true,
    isCurrent: () => true, onSessionChange: () {});
  addTearDown(controller.dispose);
  return controller;
}

Future<ProviderContainer> _open(WidgetTester tester, _Wire wire) async {
  tester.view.physicalSize = const Size(390, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = await _container(wire);
  await tester.pumpWidget(UncontrolledProviderScope(container: container,
    child: MaterialApp(theme: AppTheme.light, home: const MyListingsScreen())));
  await tester.pumpAndSettle();
  return container;
}

Finder get _verticalList => find.byWidgetPredicate(
  (widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down);

Future<void> _next(WidgetTester tester) async {
  final more = find.byKey(const ValueKey('my-listings-more'));
  await tester.scrollUntilVisible(more, 600, scrollable: _verticalList.first,
    maxScrolls: 100);
  await tester.pumpAndSettle();
  expect(more.hitTestable(), findsOneWidget);
  await tester.tap(more);
  await tester.pumpAndSettle();
}

void main() {
  test('workspace API requests a single bounded page with complete metadata', () async {
    final wire = _Wire((_) async => _page(2, [_listing(51)], last: 3, total: 101));
    final container = await _container(wire);
    final result = await container.read(propertyRepositoryProvider).myListingsPage(page: 2);
    expect(wire.requests.single.path, '/properties/mine/list');
    expect(wire.requests.single.queryParameters, {'page': 2, 'per_page': 50, 'view': 'workspace'});
    expect(result.items.single.id, 51);
    expect(result.currentPage, 2);
    expect(result.lastPage, 3);
    expect(result.total, 101);
    expect(result.hasMore, isTrue);
  });

  test('legacy complete-list API still reads every page for draft recovery', () async {
    final wire = _Wire((r) async {
      final page = r.queryParameters['page'] as int;
      return _page(page, [_listing(page)], last: 2, total: 2);
    });
    final container = await _container(wire);
    final rows = await container.read(propertyRepositoryProvider).myListings();
    expect(wire.pages, [1, 2]);
    expect(rows.map((row) => row.id), [1, 2]);
  });

  test('invalid metadata or page bounds cannot silently truncate the workspace', () async {
    var body = <String, dynamic>{'data': <Object>[]};
    final wire = _Wire((_) async => body);
    final container = await _container(wire);
    final repository = container.read(propertyRepositoryProvider);
    await expectLater(repository.myListingsPage(), throwsStateError);
    body = _page(1, []);
    await expectLater(repository.myListingsPage(page: 2), throwsStateError);
    await expectLater(repository.myListingsPage(page: 0), throwsArgumentError);
    await expectLater(repository.myListingsPage(perPage: 51), throwsArgumentError);
    expect(wire.requests.length, 2);
  });

  for (final boundary in ['account', 'epoch']) {
    test('$boundary boundary while credentials await sends no workspace request', () async {
      final credentials = _Credentials()..pending = Completer<void>();
      final wire = _Wire((_) async => _page(1, [_listing(1)]));
      final container = await _container(wire, credentials: credentials);
      final rejected = expectLater(container.read(propertyRepositoryProvider)
        .myListingsPage(requestScope: container.read(accountRequestScopeProvider)), throwsStateError);
      if (boundary == 'epoch') {
        Stage6SecureSessionStore.instance.beginSessionChange();
      } else {
        (container.read(authControllerProvider.notifier) as _Auth).change(7);
      }
      credentials.pending!.complete();
      await rejected;
      expect(wire.requests, isEmpty);
    });
  }

  test('late workspace receipt cannot cross same-ID session replacement', () async {
    final receipt = Completer<Map<String, dynamic>>();
    final wire = _Wire((_) => receipt.future);
    final container = await _container(wire);
    final rejected = expectLater(container.read(propertyRepositoryProvider)
      .myListingsPage(), throwsStateError);
    await _flush();
    expect(wire.pages, [1]);
    Stage6SecureSessionStore.instance.beginSessionChange();
    receipt.complete(_page(1, [_listing(1)]));
    await rejected;
  });

  test('repeated next-page taps deduplicate IDs and stop at the final page', () async {
    final pending = Completer<MyListingsPage>();
    final calls = <int>[];
    final controller = _controller((page) async {
      calls.add(page);
      return page == 1 ? _model(1, [1, 2]) : pending.future;
    });
    await _flush();
    final next = controller.loadMore();
    await controller.loadMore();
    pending.complete(_model(2, [2, 3]));
    await next;
    expect(calls, [1, 2]);
    expect(controller.state.items.map((item) => item.id), [1, 2, 3]);
    await controller.loadMore();
    expect(calls, [1, 2]);
  });

  test('503 retains earlier pages and retry requests the same next page once', () async {
    final calls = <int>[];
    var fail = true;
    final controller = _controller((page) async {
      calls.add(page);
      if (page == 2 && fail) throw _failure();
      return _model(page, page == 1 ? [1, 2] : [2, 3]);
    });
    await _flush();
    await controller.loadMore();
    expect(controller.state.items.map((item) => item.id), [1, 2]);
    expect(controller.state.page?.currentPage, 1);
    expect(controller.state.pageError, isNotNull);
    fail = false;
    await controller.loadMore();
    expect(calls, [1, 2, 2]);
    expect(controller.state.items.map((item) => item.id), [1, 2, 3]);
  });

  for (final status in [401, 403, 404]) {
    test('$status clears private pages and prevents further appending', () async {
      final calls = <int>[];
      final controller = _controller((page) async {
        calls.add(page);
        if (page == 2) throw _failure(status);
        return _model(1, [1]);
      });
      await _flush();
      await controller.loadMore();
      expect(controller.state.items, isEmpty);
      expect(controller.state.error, isNotNull);
      await controller.loadMore();
      expect(calls, [1, 2]);
    });
  }

  test('refresh supersedes a pending next page and rejects its late error', () async {
    final pending = Completer<MyListingsPage>();
    var fresh = false;
    final controller = _controller((page) async => page == 2
      ? pending.future : _model(1, fresh ? [20] : [1]));
    await _flush();
    final next = controller.loadMore();
    fresh = true;
    await controller.refresh();
    pending.completeError(_failure());
    await next;
    expect(controller.state.items.map((item) => item.id), [20]);
    expect(controller.state.pageError, isNull);
    expect(controller.state.error, isNull);
  });

  test('failed refresh keeps rows but blocks appending until page one succeeds', () async {
    final calls = <int>[];
    var fail = false;
    final controller = _controller((page) async {
      calls.add(page);
      if (fail) throw _failure();
      return _model(page, [page]);
    });
    await _flush();
    fail = true;
    await controller.refresh();
    expect(controller.state.items.single.id, 1);
    await controller.loadMore();
    expect(calls, [1, 1]);
    fail = false;
    await controller.refresh();
    await controller.loadMore();
    expect(calls, [1, 1, 1, 2]);
  });

  for (final boundary in ['account', 'logout', 'same-ID']) {
    test('$boundary discards the old page and starts the replacement at page one', () async {
      final old = Completer<Map<String, dynamic>>();
      var replacement = false;
      final wire = _Wire((r) async {
        final page = r.queryParameters['page'] as int;
        if (page == 2) return old.future;
        return _page(1, [_listing(replacement ? 90 : 1)], last: 2, total: 51);
      });
      final container = await _container(wire);
      final subscription = container.listen(myListingsPagesProvider, (_, __) {});
      addTearDown(subscription.close);
      await _flush();
      final controller = container.read(myListingsPagesProvider.notifier);
      final next = controller.loadMore();
      await _flush();
      replacement = true;
      final auth = container.read(authControllerProvider.notifier) as _Auth;
      if (boundary == 'same-ID') Stage6SecureSessionStore.instance.beginSessionChange();
      auth.change(boundary == 'account' ? 7 : null);
      if (boundary == 'same-ID') auth.change(6);
      await _flush();
      old.complete(_page(2, [_listing(2)], last: 2, total: 51));
      await next;
      await _flush();
      final state = container.read(myListingsPagesProvider);
      expect(state.items.map((item) => item.id), boundary == 'logout' ? <int>[] : [90]);
      expect(state.loadingMore, isFalse);
      expect(wire.pages, boundary == 'logout' ? [1, 2] : [1, 2, 1]);
    });
  }

  testWidgets('long private workspace keeps retry at the footer and preserves scroll', (tester) async {
    var fail = true;
    final wire = _Wire((r) async {
      final page = r.queryParameters['page'] as int;
      if (page == 2 && fail) throw _failure(503, r);
      return _page(page, page == 1 ? List.generate(50, (i) => _listing(i + 1))
        : [_listing(50), _listing(51)], last: 2, total: 51);
    });
    final container = await _open(tester, wire);
    expect(wire.pages, [1]);
    await _next(tester);
    expect(container.read(myListingsPagesProvider).items.length, 50);
    final scroll = tester.state<ScrollableState>(_verticalList.first).position;
    final failedOffset = scroll.pixels;
    expect(failedOffset, greaterThan(1000));
    final footer = find.byKey(const ValueKey('my-listings-page-error'));
    final retry = find.descendant(of: footer, matching: find.text('إعادة المحاولة'));
    await tester.ensureVisible(retry);
    await tester.pumpAndSettle();
    expect(retry.hitTestable(), findsOneWidget);
    fail = false;
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(wire.pages, [1, 2, 2]);
    expect(container.read(myListingsPagesProvider).items.length, 51);
    expect(scroll.pixels, greaterThan(failedOffset - 200));
    expect(find.byKey(const ValueKey('my-listings-more')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty local filter can reach a match on the next page without false totals', (tester) async {
    final wire = _Wire((r) async {
      final page = r.queryParameters['page'] as int;
      return _page(page, [_listing(page, review: page == 1 ? 'draft' : 'approved')],
        last: 2, total: 2);
    });
    await _open(tester, wire);
    expect(find.text('ملخص الإعلانات المحمّلة'), findsOneWidget);
    final filter = find.text('منشورة (0)');
    await tester.ensureVisible(filter);
    await tester.tap(filter);
    await tester.pumpAndSettle();
    expect(find.text('لا توجد إعلانات في هذه الحالة'), findsNothing);
    await _next(tester);
    expect(wire.pages, [1, 2]);
    expect(find.text('Synthetic listing 2'), findsOneWidget);
    expect(find.text('الأعداد تخص الإعلانات المحمّلة حتى اكتمال التحميل'), findsNothing);
    expect(find.byType(AppErrorState), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

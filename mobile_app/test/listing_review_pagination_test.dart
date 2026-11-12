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
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/reviews/data/listing_review_repository.dart';
import 'package:real_estate_mobile/features/reviews/presentation/listing_review_workspace_screen.dart';

AuthUser _user(int id) => AuthUser.fromJson({
  'id': id, 'name': 'Synthetic support $id', 'account_status': 'active',
  'roles': ['support_agent'], 'permissions': ['listings.moderate'],
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

Map<String, dynamic> _listing(int id, {String? title}) => {
  'id': id, 'title': title ?? 'Synthetic listing $id',
  'review_status': 'submitted', 'purpose': 'sale', 'type': 'apartment',
  'owner': {'name': 'Synthetic owner'}, 'proof_documents': <Object>[],
};

Map<String, dynamic> _page(int page, List<Map<String, dynamic>> rows,
    {int last = 1, int? total}) => {
  'data': rows,
  'meta': {'current_page': page, 'last_page': last, 'total': total ?? rows.length},
};

DioException _failure(RequestOptions request, int status) => DioException(
  requestOptions: request, type: DioExceptionType.badResponse,
  response: Response(requestOptions: request, statusCode: status),
);

class _Wire {
  _Wire(this.respond) {
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) async {
      requests.add(request);
      try {
        handler.resolve(Response<Map<String, dynamic>>(
          requestOptions: request, statusCode: 200, data: request.path.endsWith('/blocks') ? _page(1, []) : await respond(request)));
      } on DioException catch (error) {
        handler.reject(error);
      }
    }));
  }
  final Future<Map<String, dynamic>> Function(RequestOptions) respond;
  final dio = Dio(BaseOptions(baseUrl: 'https://synthetic.invalid/api'));
  final requests = <RequestOptions>[];
  Iterable<int> get pages => requests.where((r) => r.path.endsWith('/queue'))
      .map((r) => r.queryParameters['page'] as int);
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

Future<ProviderContainer> _open(WidgetTester tester, _Wire wire) async {
  tester.view.physicalSize = const Size(390, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = await _container(wire);
  await tester.pumpWidget(UncontrolledProviderScope(container: container,
    child: MaterialApp(theme: AppTheme.light, home: const ListingReviewWorkspaceScreen())));
  await tester.pumpAndSettle();
  return container;
}

Finder get _verticalList => find.byWidgetPredicate(
  (widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down);

Future<void> _next(WidgetTester tester) async {
  final more = find.byKey(const ValueKey('review-queue-more'));
  await tester.scrollUntilVisible(more, 600, scrollable: _verticalList.first,
      maxScrolls: 50);
  await tester.tap(more);
  for (var i = 0; i < 8; i++) { await tester.pump(); }
}

void main() {
  test('queue repository uses bounded pages and server end metadata', () async {
    final wire = _Wire((_) async => _page(2, [_listing(26)], last: 3, total: 51));
    final container = await _container(wire);
    final page = await container.read(listingReviewRepositoryProvider).queue(page: 2);
    expect(wire.requests.single.path, '/admin/listing-review/queue');
    expect(wire.requests.single.queryParameters, {'page': 2, 'per_page': 25});
    expect(page.items.single.id, 26);
    expect(page.currentPage, 2);
    expect(page.lastPage, 3);
    expect(page.total, 51);
    expect(page.hasMore, isTrue);
  });

  test('invalid page metadata fails instead of silently ending the queue', () async {
    var result = <String, dynamic>{'data': <Object>[]};
    final wire = _Wire((_) async => result);
    final container = await _container(wire);
    final repository = container.read(listingReviewRepositoryProvider);
    await expectLater(repository.queue(), throwsStateError);
    result = _page(1, []);
    await expectLater(repository.queue(page: 2), throwsStateError);
    await expectLater(repository.queue(page: 0), throwsArgumentError);
    await expectLater(repository.queue(perPage: 51), throwsArgumentError);
    expect(wire.requests.length, 2);
  });

  test('epoch change while credentials wait cannot send an old queue request', () async {
    final credentials = _Credentials()..pending = Completer<void>();
    final wire = _Wire((_) async => _page(1, [_listing(1)]));
    final container = await _container(wire, credentials: credentials);
    final request = container.read(listingReviewRepositoryProvider).queue();
    final rejected = expectLater(request, throwsStateError);
    Stage6SecureSessionStore.instance.beginSessionChange();
    credentials.pending!.complete();
    await rejected;
    expect(wire.requests, isEmpty);
  });

  test('account switch while credentials wait cannot send an old queue request', () async {
    final credentials = _Credentials()..pending = Completer<void>();
    final wire = _Wire((_) async => _page(1, [_listing(1)]));
    final container = await _container(wire, credentials: credentials);
    final request = container.read(listingReviewRepositoryProvider).queue();
    final rejected = expectLater(request, throwsStateError);
    (container.read(authControllerProvider.notifier) as _Auth).change(7);
    credentials.pending!.complete();
    await rejected;
    expect(wire.requests, isEmpty);
  });

  testWidgets('25-row queue retains page one on 503 and retries page two once', (tester) async {
    var fail = true;
    final wire = _Wire((r) async {
      final page = r.queryParameters['page'] as int;
      if (page == 1) return _page(1, List.generate(25, (i) => _listing(i + 1)), last: 2, total: 26);
      if (fail) throw _failure(r, 503);
      return _page(2, [_listing(25, title: 'Updated listing 25'), _listing(26)], last: 2, total: 26);
    });
    final container = await _open(tester, wire);
    expect(find.text('Synthetic listing 1'), findsOneWidget);
    await _next(tester);
    await tester.pumpAndSettle();
    expect(wire.pages, [1, 2]);
    expect(container.read(reviewQueueProvider).items.length, 25);
    final status = find.byKey(const ValueKey('review-queue-page-status'));
    await tester.scrollUntilVisible(status, 600, scrollable: _verticalList.first);
    final retry = find.descendant(of: status, matching: find.text('إعادة المحاولة'));
    await tester.ensureVisible(retry);
    await tester.pumpAndSettle();
    expect(retry.hitTestable(), findsOneWidget);
    fail = false;
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(wire.pages, [1, 2, 2]);
    final state = container.read(reviewQueueProvider);
    expect(state.items.map((e) => e.id), List.generate(26, (i) => i + 1));
    expect(state.items.singleWhere((e) => e.id == 25).title, 'Updated listing 25');
    expect(state.page!.hasMore, isFalse);
    expect(find.byKey(const ValueKey('review-queue-more')), findsNothing);
    await container.read(reviewQueueProvider.notifier).loadMore();
    expect(wire.pages, [1, 2, 2]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('temporary refresh failure preserves rows and retries page one', (tester) async {
    var fail = false;
    final wire = _Wire((r) async {
      if (fail) throw _failure(r, 503);
      return _page(1, [_listing(1)], last: 2, total: 2);
    });
    final container = await _open(tester, wire);
    fail = true;
    final refresh = tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh();
    await tester.pumpAndSettle();
    await refresh;
    expect(find.text('Synthetic listing 1'), findsOneWidget);
    expect(container.read(reviewQueueProvider).items.single.id, 1);
    expect(find.byType(AppErrorState), findsNothing);
    await container.read(reviewQueueProvider.notifier).loadMore();
    expect(wire.pages, [1, 1]);
    expect(tester.widget<TextButton>(find.byKey(const ValueKey('review-queue-more'))).onPressed, isNull);
    fail = false;
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(wire.pages, [1, 1, 1]);
    expect(container.read(reviewQueueProvider).error, isNull);
  });

  testWidgets('page two access denial removes private queue rows', (tester) async {
    final wire = _Wire((r) async {
      if (r.queryParameters['page'] == 1) return _page(1, [_listing(1)], last: 2, total: 2);
      throw _failure(r, 403);
    });
    final container = await _open(tester, wire);
    await _next(tester);
    await tester.pumpAndSettle();
    expect(container.read(reviewQueueProvider).items, isEmpty);
    expect(find.text('Synthetic listing 1'), findsNothing);
    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.text('ليس لديك صلاحية لتنفيذ هذه العملية.'), findsOneWidget);
  });

  testWidgets('claim invalidation replaces pages and ignores the old page two', (tester) async {
    final delayed = Completer<Map<String, dynamic>>();
    var claimed = false;
    final wire = _Wire((r) async {
      if (r.path.endsWith('/start')) {
        claimed = true;
        return {'data': <String, dynamic>{}};
      }
      if (r.queryParameters['page'] == 2) return delayed.future;
      return _page(1, [_listing(claimed ? 7 : 1)], last: claimed ? 1 : 2, total: claimed ? 1 : 2);
    });
    final container = await _open(tester, wire);
    await _next(tester);
    await container.read(reviewQueueProvider.notifier).loadMore();
    expect(wire.pages, [1, 2]);
    await tester.tap(find.text('استلام الطلب'));
    await tester.pumpAndSettle();
    expect(wire.pages, [1, 2, 1]);
    expect(container.read(reviewQueueProvider).items.single.id, 7);
    delayed.complete(_page(2, [_listing(2)], last: 2, total: 2));
    await tester.pumpAndSettle();
    expect(container.read(reviewQueueProvider).items.map((e) => e.id), [7]);
    expect(find.text('Synthetic listing 2'), findsNothing);
  });

  testWidgets('refresh during page two replaces the snapshot and ignores its late rows', (tester) async {
    final delayed = Completer<Map<String, dynamic>>();
    var firstLoads = 0;
    final wire = _Wire((r) async {
      if (r.queryParameters['page'] == 2) return delayed.future;
      firstLoads++;
      return _page(1, [_listing(firstLoads == 1 ? 1 : 8)], last: 2, total: 2);
    });
    final container = await _open(tester, wire);
    await _next(tester);
    final refresh = tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh();
    await tester.pumpAndSettle();
    await refresh;
    delayed.complete(_page(2, [_listing(2)], last: 2, total: 2));
    await tester.pumpAndSettle();
    expect(wire.pages, [1, 2, 1]);
    expect(container.read(reviewQueueProvider).items.map((e) => e.id), [8]);
    expect(find.text('Synthetic listing 1'), findsNothing);
    expect(find.text('Synthetic listing 2'), findsNothing);
  });

  testWidgets('account switch discards a delayed page and starts the next account at one', (tester) async {
    final delayed = Completer<Map<String, dynamic>>();
    var actor = 6;
    final wire = _Wire((r) async {
      if (r.queryParameters['page'] == 2) return delayed.future;
      return _page(1, [_listing(actor)], last: actor == 6 ? 2 : 1, total: actor == 6 ? 2 : 1);
    });
    final container = await _open(tester, wire);
    await _next(tester);
    actor = 7;
    (container.read(authControllerProvider.notifier) as _Auth).change(7);
    await tester.pumpAndSettle();
    delayed.complete(_page(2, [_listing(60)], last: 2, total: 2));
    await tester.pumpAndSettle();
    expect(wire.pages, [1, 2, 1]);
    expect(container.read(reviewQueueProvider).items.map((e) => e.id), [7]);
    expect(find.text('Synthetic listing 6'), findsNothing);
    expect(find.text('Synthetic listing 60'), findsNothing);
  });

  testWidgets('logout removes visible private rows without requesting a guest queue', (tester) async {
    final wire = _Wire((_) async => _page(1, [_listing(1)]));
    final container = await _open(tester, wire);
    (container.read(authControllerProvider.notifier) as _Auth).change(null);
    await tester.pumpAndSettle();
    expect(wire.pages, [1]);
    expect(container.read(reviewQueueProvider).items, isEmpty);
    expect(find.text('Synthetic listing 1'), findsNothing);
    expect(find.text('يجب تسجيل الدخول أولاً.'), findsOneWidget);
  });

  testWidgets('logout then the same ID before a frame still rejects the old page', (tester) async {
    final delayed = Completer<Map<String, dynamic>>();
    var replacement = false;
    final wire = _Wire((r) async {
      if (r.queryParameters['page'] == 2) return delayed.future;
      return _page(1, [_listing(replacement ? 9 : 1)], last: replacement ? 1 : 2, total: replacement ? 1 : 2);
    });
    final container = await _open(tester, wire);
    await _next(tester);
    replacement = true;
    final auth = container.read(authControllerProvider.notifier) as _Auth;
    auth.change(null);
    auth.change(6);
    await tester.pumpAndSettle();
    delayed.complete(_page(2, [_listing(2)], last: 2, total: 2));
    await tester.pumpAndSettle();
    expect(wire.pages, [1, 2, 1]);
    expect(container.read(reviewQueueProvider).items.map((e) => e.id), [9]);
    expect(find.text('Synthetic listing 1'), findsNothing);
    expect(find.text('Synthetic listing 2'), findsNothing);
  });

  testWidgets('same-account session replacement resets loaded pages on auth emission', (tester) async {
    var replacement = false;
    final wire = _Wire((r) async {
      final page = r.queryParameters['page'] as int;
      return _page(page, [_listing(replacement ? 9 : page)], last: replacement ? 1 : 2, total: replacement ? 1 : 2);
    });
    final container = await _open(tester, wire);
    await _next(tester);
    await tester.pumpAndSettle();
    replacement = true;
    Stage6SecureSessionStore.instance.beginSessionChange();
    (container.read(authControllerProvider.notifier) as _Auth).change(6);
    await tester.pumpAndSettle();
    expect(wire.pages, [1, 2, 1]);
    expect(container.read(reviewQueueProvider).items.map((e) => e.id), [9]);
  });

  testWidgets('same-session account metadata emission preserves both loaded pages', (tester) async {
    final wire = _Wire((r) async {
      final page = r.queryParameters['page'] as int;
      return _page(page, [_listing(page)], last: 2, total: 2);
    });
    final container = await _open(tester, wire);
    await _next(tester);
    await tester.pumpAndSettle();
    (container.read(authControllerProvider.notifier) as _Auth).change(6);
    await tester.pumpAndSettle();
    expect(wire.pages, [1, 2]);
    expect(container.read(reviewQueueProvider).items.map((e) => e.id), [1, 2]);
  });

  testWidgets('epoch-only change while loading clears stale rows and recovers at page one', (tester) async {
    final delayed = Completer<Map<String, dynamic>>();
    var replacement = false;
    final wire = _Wire((r) async {
      if (r.queryParameters['page'] == 2) return delayed.future;
      return _page(1, [_listing(replacement ? 9 : 1)], last: replacement ? 1 : 2, total: replacement ? 1 : 2);
    });
    final container = await _open(tester, wire);
    await _next(tester);
    replacement = true;
    Stage6SecureSessionStore.instance.beginSessionChange();
    delayed.complete(_page(2, [_listing(2)], last: 2, total: 2));
    await tester.pumpAndSettle();
    expect(wire.pages, [1, 2, 1]);
    expect(container.read(reviewQueueProvider).items.map((e) => e.id), [9]);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('empty queue supports refresh and keeps the original Arabic/theme surface', (tester) async {
    var empty = true;
    final wire = _Wire((_) async => _page(1, empty ? [] : [_listing(3)]));
    final container = await _open(tester, wire);
    expect(find.byType(AppEmptyState), findsOneWidget);
    expect(find.text('لا توجد طلبات معلقة'), findsOneWidget);
    expect(Directionality.of(tester.element(find.text('لا توجد طلبات معلقة'))), TextDirection.rtl);
    empty = false;
    await tester.tap(find.text('تحديث'));
    await tester.pumpAndSettle();
    expect(container.read(reviewQueueProvider).items.single.id, 3);
    expect(wire.pages, [1, 1]);
    expect(tester.takeException(), isNull);
  });
}

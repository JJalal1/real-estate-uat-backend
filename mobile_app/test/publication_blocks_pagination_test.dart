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

AuthUser _user(int id, {bool canLift = true}) => AuthUser.fromJson({
  'id': id, 'name': 'Synthetic support $id', 'account_status': 'active',
  'roles': ['support_agent'], 'permissions': ['listings.moderate', if (canLift) 'listings.manage_blocks'],
});

class _Auth extends AuthController {
  @override
  Future<AuthUser?> build() async => _user(6);
  void change(int? id, {bool canLift = true}) => state = AsyncData(id == null ? null : _user(id, canLift: canLift));
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

Map<String, dynamic> _block(int id, {String? reason}) => {
  'id': id, 'property_asset_id': id, 'purpose': 'sale', 'is_active': true,
  'reason': reason ?? 'Synthetic block $id',
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
          requestOptions: request, statusCode: 200, data: request.path.endsWith('/queue') ? _page(1, []) : await respond(request)));
      } on DioException catch (error) {
        handler.reject(error);
      }
    }));
  }
  final Future<Map<String, dynamic>> Function(RequestOptions) respond;
  final dio = Dio(BaseOptions(baseUrl: 'https://synthetic.invalid/api'));
  final requests = <RequestOptions>[];
  Iterable<int> get pages => requests.where((r) => r.path.endsWith('/blocks'))
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
  await tester.tap(find.text('حظر النشر'));
  await tester.pumpAndSettle();
  return container;
}

Finder get _verticalList => find.byWidgetPredicate(
  (widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down);

Future<void> _next(WidgetTester tester) async {
  final more = find.byKey(const ValueKey('publication-blocks-more'));
  await tester.scrollUntilVisible(more, 600, scrollable: _verticalList.first,
      maxScrolls: 50);
  await tester.pumpAndSettle();
  expect(more.hitTestable(), findsOneWidget);
  await tester.tap(more);
  await tester.pump();
}

void main() {
  test('blocks repository preserves active filter and reads bounded 50-row pages', () async {
    final wire = _Wire((_) async => _page(2, [_block(51)], last: 3, total: 101));
    final container = await _container(wire);
    final result = await container.read(listingReviewRepositoryProvider).blocks(page: 2);
    expect(wire.requests.single.queryParameters, {'active': 1, 'page': 2, 'per_page': 50});
    expect(result.items.single.id, 51);
    expect(result.currentPage, 2);
    expect(result.lastPage, 3);
    expect(result.total, 101);
    expect(result.hasMore, isTrue);
  });

  test('lift cannot obtain a replacement-session token while credentials are pending', () async {
    final credentials = _Credentials()..pending = Completer<void>();
    final wire = _Wire((_) async => {'data': <String, dynamic>{}});
    final container = await _container(wire, credentials: credentials);
    final rejected = expectLater(container.read(listingReviewRepositoryProvider)
        .liftBlock(1, 'Synthetic sufficient reason'), throwsStateError);
    Stage6SecureSessionStore.instance.beginSessionChange();
    credentials.pending!.complete();
    await rejected;
    expect(wire.requests, isEmpty);
  });

  test('blocks reject invalid paging metadata and out-of-contract sizes', () async {
    var result = <String, dynamic>{'data': <Object>[]};
    final wire = _Wire((_) async => result);
    final container = await _container(wire);
    final repository = container.read(listingReviewRepositoryProvider);
    await expectLater(repository.blocks(), throwsStateError);
    result = _page(1, []);
    await expectLater(repository.blocks(page: 2), throwsStateError);
    await expectLater(repository.blocks(page: 0), throwsArgumentError);
    await expectLater(repository.blocks(perPage: 101), throwsArgumentError);
    expect(wire.requests.length, 2);
  });

  test('blocks cannot cross a session boundary while credentials are pending', () async {
    final credentials = _Credentials()..pending = Completer<void>();
    final wire = _Wire((_) async => _page(1, [_block(1)]));
    final container = await _container(wire, credentials: credentials);
    final pending = container.read(listingReviewRepositoryProvider).blocks();
    final rejected = expectLater(pending, throwsStateError);
    Stage6SecureSessionStore.instance.beginSessionChange();
    credentials.pending!.complete();
    await rejected;
    expect(wire.requests, isEmpty);
  });

  testWidgets('50 blocks retain rows on 503, retry page two, deduplicate and stop', (tester) async {
    var fail = true;
    final wire = _Wire((r) async {
      if (r.queryParameters['page'] == 1) return _page(1, List.generate(50, (i) => _block(i + 1)), last: 2, total: 51);
      if (fail) throw _failure(r, 503);
      return _page(2, [_block(50, reason: 'Updated block 50'), _block(51)], last: 2, total: 51);
    });
    final container = await _open(tester, wire);
    await _next(tester);
    await tester.pumpAndSettle();
    expect(wire.pages, [1, 2]);
    expect(container.read(publicationBlocksProvider).items.length, 50);
    final retry = find.descendant(
      of: find.byKey(const ValueKey('publication-blocks-page-status')),
      matching: find.byType(TextButton));
    await tester.ensureVisible(retry);
    await tester.pumpAndSettle();
    expect(retry.hitTestable(), findsOneWidget);
    fail = false;
    await tester.tap(retry);
    await tester.pumpAndSettle();
    final state = container.read(publicationBlocksProvider);
    expect(wire.pages, [1, 2, 2]);
    expect(state.items.map((e) => e.id), List.generate(51, (i) => i + 1));
    expect(state.items.singleWhere((e) => e.id == 50).reason, 'Updated block 50');
    expect(state.page!.hasMore, isFalse);
    expect(find.byKey(const ValueKey('publication-blocks-more')), findsNothing);
    await container.read(publicationBlocksProvider.notifier).loadMore();
    expect(wire.pages, [1, 2, 2]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('block page-two denial clears private rows and offers first-page retry', (tester) async {
    final wire = _Wire((r) async {
      if (r.queryParameters['page'] == 1) return _page(1, [_block(1)], last: 2, total: 2);
      throw _failure(r, 403);
    });
    final container = await _open(tester, wire);
    await _next(tester);
    await tester.pumpAndSettle();
    expect(container.read(publicationBlocksProvider).items, isEmpty);
    expect(find.text('Synthetic block 1'), findsNothing);
    expect(find.byType(AppErrorState), findsOneWidget);
  });

  testWidgets('block visibility keeps lift permission and same-session metadata boundaries', (tester) async {
    final wire = _Wire((_) async => _page(1, [_block(1)]));
    final container = await _open(tester, wire);
    expect(find.text('رفع الحظر'), findsOneWidget);
    (container.read(authControllerProvider.notifier) as _Auth).change(6, canLift: false);
    await tester.pumpAndSettle();
    expect(find.text('رفع الحظر'), findsNothing);
    expect(find.text('Synthetic block 1'), findsOneWidget);
    expect(wire.pages, [1]);
    expect(Directionality.of(tester.element(find.text('Synthetic block 1'))), TextDirection.rtl);
  });

  testWidgets('lift invalidation rejects a pending old page and reloads active blocks', (tester) async {
    final delayed = Completer<Map<String, dynamic>>();
    var lifted = false;
    final wire = _Wire((r) async {
      if (r.path.endsWith('/lift')) {
        expect(r.data, {'reason': 'سبب اصطناعي كاف لرفع الحظر'});
        lifted = true;
        return {'data': <String, dynamic>{}};
      }
      if (r.queryParameters['page'] == 2) return delayed.future;
      return _page(1, [_block(lifted ? 7 : 1)], last: lifted ? 1 : 2, total: lifted ? 1 : 2);
    });
    final container = await _open(tester, wire);
    await _next(tester);
    await tester.tap(find.text('رفع الحظر'));
    // Page two remains pending behind the dialog; don't settle its spinner.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), 'سبب اصطناعي كاف لرفع الحظر');
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('رفع الحظر')));
    await tester.pumpAndSettle();
    expect(wire.pages, [1, 2, 1]);
    expect(container.read(publicationBlocksProvider).items.single.id, 7);
    delayed.complete(_page(2, [_block(2)], last: 2, total: 2));
    await tester.pumpAndSettle();
    expect(container.read(publicationBlocksProvider).items.map((e) => e.id), [7]);
    expect(find.text('Synthetic block 2'), findsNothing);
  });

  testWidgets('block refresh replaces a pending page and rejects its late result', (tester) async {
    final delayed = Completer<Map<String, dynamic>>();
    var firstLoads = 0;
    final wire = _Wire((r) async {
      if (r.queryParameters['page'] == 2) return delayed.future;
      firstLoads++;
      return _page(1, [_block(firstLoads == 1 ? 1 : 8)], last: 2, total: 2);
    });
    final container = await _open(tester, wire);
    await _next(tester);
    await tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh();
    await tester.pump();
    delayed.complete(_page(2, [_block(2)], last: 2, total: 2));
    await tester.pumpAndSettle();
    expect(wire.pages, [1, 2, 1]);
    expect(container.read(publicationBlocksProvider).items.map((e) => e.id), [8]);
  });

  testWidgets('temporary block refresh failure preserves rows and blocks page-two continuation', (tester) async {
    var fail = false;
    final wire = _Wire((r) async {
      if (fail) throw _failure(r, 503);
      return _page(1, [_block(1)], last: 2, total: 2);
    });
    final container = await _open(tester, wire);
    fail = true;
    await tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh();
    await tester.pumpAndSettle();
    await container.read(publicationBlocksProvider.notifier).loadMore();
    expect(wire.pages, [1, 1]);
    expect(container.read(publicationBlocksProvider).items.single.id, 1);
    expect(tester.widget<TextButton>(find.byKey(const ValueKey('publication-blocks-more'))).onPressed, isNull);
    fail = false;
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(wire.pages, [1, 1, 1]);
  });

  testWidgets('account change drops late blocks and restarts at page one', (tester) async {
    final delayed = Completer<Map<String, dynamic>>();
    var actor = 6;
    final wire = _Wire((r) async {
      if (r.queryParameters['page'] == 2) return delayed.future;
      return _page(1, [_block(actor)], last: actor == 6 ? 2 : 1, total: actor == 6 ? 2 : 1);
    });
    final container = await _open(tester, wire);
    await _next(tester);
    actor = 7;
    (container.read(authControllerProvider.notifier) as _Auth).change(7);
    await tester.pumpAndSettle();
    delayed.complete(_page(2, [_block(60)], last: 2, total: 2));
    await tester.pumpAndSettle();
    expect(wire.pages, [1, 2, 1]);
    expect(container.read(publicationBlocksProvider).items.map((e) => e.id), [7]);
    expect(find.text('Synthetic block 6'), findsNothing);
  });

  testWidgets('same-ID replacement session discards accumulated blocks', (tester) async {
    var replacement = false;
    final wire = _Wire((r) async {
      final page = r.queryParameters['page'] as int;
      return _page(page, [_block(replacement ? 9 : page)], last: replacement ? 1 : 2, total: replacement ? 1 : 2);
    });
    final container = await _open(tester, wire);
    await _next(tester);
    await tester.pumpAndSettle();
    replacement = true;
    Stage6SecureSessionStore.instance.beginSessionChange();
    (container.read(authControllerProvider.notifier) as _Auth).change(6);
    await tester.pumpAndSettle();
    expect(wire.pages, [1, 2, 1]);
    expect(container.read(publicationBlocksProvider).items.map((e) => e.id), [9]);
  });

  testWidgets('changing account during a lift dialog cannot send the old block action', (tester) async {
    final wire = _Wire((_) async => _page(1, [_block(1)]));
    final container = await _open(tester, wire);
    await tester.tap(find.text('رفع الحظر'));
    await tester.pumpAndSettle();
    (container.read(authControllerProvider.notifier) as _Auth).change(7);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(wire.requests.where((r) => r.path.endsWith('/lift')), isEmpty);
  });

  testWidgets('late lift receipt cannot invalidate the replacement account block list', (tester) async {
    final delayed = Completer<Map<String, dynamic>>();
    var actor = 6;
    final wire = _Wire((r) async {
      if (r.path.endsWith('/lift')) return delayed.future;
      return _page(1, [_block(actor)]);
    });
    final container = await _open(tester, wire);
    await tester.tap(find.text('رفع الحظر'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'سبب اصطناعي كاف لرفع الحظر');
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('رفع الحظر')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(wire.requests.where((r) => r.path.endsWith('/lift')).length, 1);
    actor = 7;
    (container.read(authControllerProvider.notifier) as _Auth).change(7);
    await tester.pumpAndSettle();
    delayed.complete({'data': <String, dynamic>{}});
    await tester.pumpAndSettle();
    expect(wire.pages, [1, 1]);
    expect(container.read(publicationBlocksProvider).items.map((e) => e.id), [7]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty active blocks can refresh without changing permissions or theme', (tester) async {
    var empty = true;
    final wire = _Wire((_) async => _page(1, empty ? [] : [_block(3)]));
    final container = await _open(tester, wire);
    expect(find.text('لا توجد عمليات حظر نشطة'), findsOneWidget);
    empty = false;
    await tester.tap(find.text('تحديث'));
    await tester.pumpAndSettle();
    expect(container.read(publicationBlocksProvider).items.single.id, 3);
    expect(wire.pages, [1, 1]);
    expect(tester.takeException(), isNull);
  });
}

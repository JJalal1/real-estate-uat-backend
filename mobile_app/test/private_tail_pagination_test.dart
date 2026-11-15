import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/local/stage6_secure_session_store.dart';
import 'package:real_estate_mobile/core/network/api_client.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/account/data/private_collection.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/broker/data/broker_repository.dart';
import 'package:real_estate_mobile/features/broker/data/customer_help_store.dart';
import 'package:real_estate_mobile/features/broker/presentation/broker_workspaces.dart';
import 'package:real_estate_mobile/features/properties/data/favorites_repository.dart';
import 'package:real_estate_mobile/features/properties/presentation/favorites_screen.dart';

import 'support/phase23_widget_tools.dart';

AuthUser _user(int id) => AuthUser.fromJson({'id': id, 'name': 'Synthetic broker $id',
  'account_type': 'broker', 'account_status': 'active'});
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
class _Help implements CustomerHelpStore {
  @override
  Future<bool> seen(int accountId) async => true;
  @override
  Future<void> markSeen(int accountId) async {}
}
class _Wire {
  _Wire(this.respond) {
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) async {
      requests.add(request);
      try {
        handler.resolve(Response<Map<String, dynamic>>(requestOptions: request,
          statusCode: 200, data: await respond(request)));
      } on DioException catch (error) { handler.reject(error); }
    }));
  }
  final Future<Map<String, dynamic>> Function(RequestOptions) respond;
  final dio = Dio(BaseOptions(baseUrl: 'https://synthetic.invalid/api'));
  final requests = <RequestOptions>[];
  List<int> get pages => requests.where((r) => r.method == 'GET')
    .map((r) => r.queryParameters['page'] as int).toList();
}
DioException _failure(RequestOptions r, [int status = 503]) => DioException(
  requestOptions: r, type: DioExceptionType.badResponse,
  response: Response(requestOptions: r, statusCode: status));
Map<String, dynamic> _page(int page, List<Map<String, dynamic>> rows, {int last = 1}) => {
  'data': rows, 'meta': {'current_page': page, 'last_page': last, 'total': rows.length},
};
Map<String, dynamic> _row(String surface, int id, {String? title, bool due = false}) => switch (surface) {
  'favorites' => {'property': {'id': id, 'title': title ?? 'Synthetic favorite $id',
    'price': 100000, 'currency': 'YER', 'purpose': 'sale', 'type': 'house', 'latitude': 15.3, 'longitude': 44.2}},
  'availability' => {'id': id, 'title': title ?? 'Synthetic availability $id',
    'purpose': 'sale', 'availability_status': 'available', 'needs_confirmation': due},
  _ => {'thread_id': id, 'customer_name': title ?? 'Synthetic customer $id',
    'property_id': id, 'property_title': 'Synthetic listing $id', 'stage': 'new'},
};
Future<ProviderContainer> _container(_Wire wire, {_Credentials? credentials}) async {
  final c = ProviderContainer(overrides: [
    authControllerProvider.overrideWith(_Auth.new),
    authRepositoryProvider.overrideWithValue(credentials ?? _Credentials()),
    dioProvider.overrideWithValue(wire.dio), customerHelpStoreProvider.overrideWithValue(_Help()),
  ]);
  await c.read(authControllerProvider.future);
  addTearDown(() { c.dispose(); wire.dio.close(force: true); });
  return c;
}
Future<ProviderContainer> _open(WidgetTester tester, _Wire wire, Widget screen,
    {double scale = 1}) async {
  tester.view.physicalSize = const Size(390, 800); tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
  final c = await _container(wire);
  await tester.pumpWidget(UncontrolledProviderScope(container: c, child: MaterialApp(
    theme: AppTheme.light, builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!), home: screen)));
  await tester.pumpAndSettle(); return c;
}
Finder get _vertical => find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;
Future<void> _more(WidgetTester tester, String key) async {
  final more = find.byKey(ValueKey(key));
  await tester.scrollUntilVisible(more, 500, scrollable: _vertical, maxScrolls: 100);
  await tester.pumpAndSettle(); await tester.tap(more); await pumpPhase23Request(tester);
}
Future<void> _flush() async {
  for (var i = 0; i < 8; i++) { await Future<void>.delayed(Duration.zero); }
}

void main() {
  test('private pages reject absent and mismatched server metadata', () {
    for (final body in [<String, dynamic>{'data': []}, _page(2, []), _page(1, [], last: 0)]) {
      expect(() => PrivateCollectionPage<int>.parse(body, requestedPage: 1,
        parse: (row) => row['id'] as int), throwsStateError);
    }
  });

  for (final status in [401, 403, 404]) {
    test('private page-two $status clears retained rows and retries page one', () async {
      var deny = false;
      final pages = <int>[];
      final controller = PrivateCollectionController<int>(load: (page) async {
        pages.add(page);
        if (deny) throw _failure(RequestOptions(), status);
        return PrivateCollectionPage(items: [page], currentPage: page, lastPage: 2);
      }, idOf: (id) => id);
      addTearDown(controller.dispose); await _flush();
      deny = true; await controller.loadMore();
      expect(controller.state.items, isEmpty); expect(controller.state.error, isNotNull);
      deny = false; await controller.refresh(); expect(pages, [1, 2, 1]);
    });
  }

  test('refresh wins over a pending second page and deduplication updates IDs', () async {
    final pending = Completer<PrivateCollectionPage<int>>(); var refreshed = false;
    final controller = PrivateCollectionController<int>(load: (page) async {
      if (page == 2) return pending.future;
      return PrivateCollectionPage(items: [refreshed ? 7 : 1], currentPage: 1, lastPage: 2);
    }, idOf: (id) => id);
    addTearDown(controller.dispose); await _flush();
    final more = controller.loadMore(); refreshed = true; await controller.refresh();
    pending.complete(const PrivateCollectionPage(items: [99], currentPage: 2, lastPage: 2));
    await more; expect(controller.state.items, [7]);
  });

  for (final surface in ['favorites', 'availability', 'customers']) {
    final size = surface == 'customers' ? 30 : 50;
    final prefix = switch (surface) {'favorites' => 'favorites', 'availability' => 'broker-availability', _ => 'broker-customers'};
    final screen = switch (surface) {'favorites' => const FavoritesScreen(),
      'availability' => const BrokerAvailabilityScreen(), _ => const BrokerCustomersScreen()};
    phase23WidgetTest('$surface requests one page then retries the footer without dropping rows', (tester) async {
      var fail = true;
      final wire = _Wire((r) async {
        final page = r.queryParameters['page'] as int;
        if (page == 1) return _page(1, List.generate(size, (i) => _row(surface, i + 1)), last: 2);
        if (fail) throw _failure(r);
        return _page(2, [_row(surface, size, title: 'Updated repeated row'), _row(surface, size + 1)], last: 2);
      });
      final c = await _open(tester, wire, screen);
      expect(wire.pages, [1]);
      if (surface != 'customers') expect(wire.requests.first.queryParameters['per_page'], 50);
      if (surface == 'availability') expect(find.text('اختيار الإعلانات المحمّلة'), findsOneWidget);
      await _more(tester, '$prefix-more'); await tester.pumpAndSettle();
      final footer = find.byKey(ValueKey('$prefix-page-status'));
      final retry = find.descendant(of: footer, matching: find.text('إعادة المحاولة'));
      await tester.ensureVisible(retry); await tester.pumpAndSettle();
      final before = tester.state<ScrollableState>(_vertical).position.pixels;
      expect(retry.hitTestable(), findsOneWidget);
      if (surface == 'favorites') expect(c.read(favoritePagesProvider).items.length, size);
      if (surface == 'availability') expect(c.read(brokerAvailabilityPagesProvider(false)).items.length, size);
      fail = false; await tester.tap(retry); await tester.pumpAndSettle();
      expect(wire.pages, [1, 2, 2]);
      expect(tester.state<ScrollableState>(_vertical).position.pixels, greaterThan(before - 200));
      expect(find.text('Updated repeated row'), findsOneWidget);
      expect(find.byKey(ValueKey('$prefix-more')), findsNothing);
      expect(find.byKey(ValueKey('$prefix-page-status')), findsNothing);
      if (surface == 'favorites') expect(c.read(favoritePagesProvider).items.length, size + 1);
      if (surface == 'availability') expect(c.read(brokerAvailabilityPagesProvider(false)).items.length, size + 1);
      expect(tester.takeException(), isNull);
    });

    for (final sameId in [false, true]) {
      phase23WidgetTest('$surface discards a late page across ${sameId ? 'same-ID renewal' : 'account replacement'}', (tester) async {
        final pending = Completer<Map<String, dynamic>>(); var actor = 1;
        final wire = _Wire((r) async {
          if (r.queryParameters['page'] == 2) return pending.future;
          return _page(1, [_row(surface, actor)], last: actor == 1 ? 2 : 1);
        });
        final c = await _open(tester, wire, screen);
        await _more(tester, '$prefix-more'); expect(wire.pages, [1, 2]);
        actor = 700;
        if (sameId) Stage6SecureSessionStore.instance.beginSessionChange();
        (c.read(authControllerProvider.notifier) as _Auth).change(sameId ? 6 : 7);
        await tester.pumpAndSettle();
        pending.complete(_page(2, [_row(surface, 999)], last: 2)); await tester.pumpAndSettle();
        expect(find.textContaining('999'), findsNothing);
        expect(find.text('Synthetic ${surface == 'favorites' ? 'favorite' : surface == 'availability' ? 'availability' : 'customer'} 700'), findsOneWidget);
        expect(wire.pages, [1, 2, 1]); expect(tester.takeException(), isNull);
      });
    }
  }

  phase23WidgetTest('availability server filter replaces pending pages and resets selected IDs', (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    final wire = _Wire((r) async {
      if (r.queryParameters['only_due'] == 1) return _page(1, [_row('availability', 101, due: true)]);
      if (r.queryParameters['page'] == 2) return pending.future;
      return _page(1, [_row('availability', 1)], last: 2);
    });
    final c = await _open(tester, wire, const BrokerAvailabilityScreen(), scale: 2.4);
    await _more(tester, 'broker-availability-more');
    final chip = find.text('تحتاج تأكيد التوفر');
    await tester.scrollUntilVisible(chip, -400, scrollable: _vertical, maxScrolls: 30);
    await tester.pump(const Duration(milliseconds: 300));
    expect(chip.hitTestable(), findsOneWidget);
    await tester.tap(chip); await tester.pumpAndSettle();
    expect(wire.requests.last.queryParameters, {'page': 1, 'per_page': 50, 'only_due': 1});
    pending.complete(_page(2, [_row('availability', 999)], last: 2)); await tester.pumpAndSettle();
    expect(c.read(brokerAvailabilityPagesProvider(true)).items.map((item) => item.id), [101]);
    final row = find.byKey(const ValueKey('broker-availability-101'));
    await tester.scrollUntilVisible(row, 300, scrollable: _vertical, maxScrolls: 20);
    await tester.pumpAndSettle();
    expect(find.text('Synthetic availability 101'), findsOneWidget);
    expect(find.text('Synthetic availability 999'), findsNothing);
    final confirm = find.text('ما زالت متوفرة (1)');
    await tester.scrollUntilVisible(confirm, 300, scrollable: _vertical, maxScrolls: 20);
    expect(confirm.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final surface in ['favorites', 'availability']) {
    test('$surface cannot send after credentials cross a session boundary', () async {
      final credentials = _Credentials()..pending = Completer<void>();
      final wire = _Wire((_) async => _page(1, []));
      final c = await _container(wire, credentials: credentials);
      final request = surface == 'favorites' ? c.read(favoritesRepositoryProvider).favoritesPage()
        : c.read(brokerRepositoryProvider).availabilityPage();
      final rejected = expectLater(request, throwsStateError);
      Stage6SecureSessionStore.instance.beginSessionChange(); credentials.pending!.complete();
      await rejected; expect(wire.requests, isEmpty);
    });
  }
}

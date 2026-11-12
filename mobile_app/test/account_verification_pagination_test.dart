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
import 'package:real_estate_mobile/features/account/data/account_verification_repository.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/account/presentation/account_verification_admin_screen.dart';
import 'package:real_estate_mobile/features/support/data/account_verification_support_repository.dart';
import 'package:real_estate_mobile/features/support/presentation/account_verification_support_screen.dart';
import 'package:real_estate_mobile/features/support/presentation/support_tasks_screen.dart';

AuthUser _user(int id) => AuthUser.fromJson({'id': id, 'name': 'Synthetic staff $id',
  'account_status': 'active', 'roles': ['support_agent'], 'permissions': ['accounts.verify_profiles']});
class _Auth extends AuthController {
  @override
  Future<AuthUser?> build() async => _user(6);
  void change(int? id) => state = AsyncData(id == null ? null : _user(id));
}
class _Credentials implements AuthRepository {
  Completer<void>? pending;
  @override
  Future<Options> requiredAuthOptions() async {
    await pending?.future;
    return Options(headers: {'Authorization': 'Bearer synthetic-only'});
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}
Map<String, dynamic> _application(int id, {String? name}) => {
  'user_id': id, 'name': name ?? 'Synthetic applicant $id', 'phone': '+967000000000',
  'type': 'owner', 'status': 'pending', 'details': {'governorate': 'Synthetic region'},
  'documents': [{'kind': 'identity_document', 'original_name': 'private-identity-$id.jpg',
    'url': '/api/account-verification/users/$id/documents/identity_document'}],
};
Map<String, dynamic> _page(int page, List<Map<String, dynamic>> rows,
    {int last = 1, int? total}) => {'data': rows,
  'meta': {'current_page': page, 'last_page': last, 'total': total ?? rows.length}};
DioException _failure(RequestOptions r, int status) => DioException(requestOptions: r,
  type: DioExceptionType.badResponse, response: Response(requestOptions: r, statusCode: status));
class _Wire {
  _Wire(this.respond) {
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) async {
      requests.add(request);
      try {
        handler.resolve(Response<dynamic>(requestOptions: request, statusCode: 200,
          data: await respond(request)));
      } on DioException catch (error) { handler.reject(error); }
    }));
  }
  final Future<Object> Function(RequestOptions) respond;
  final dio = Dio(BaseOptions(baseUrl: 'https://synthetic.invalid/api'));
  final requests = <RequestOptions>[];
  Iterable<int> get pages => requests.where((r) => r.path == '/admin/account-verifications')
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
Future<ProviderContainer> _open(WidgetTester tester, _Wire wire,
    {required bool admin, int? focus, bool tasks = false}) async {
  tester.view.physicalSize = const Size(390, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
  final container = await _container(wire);
  await tester.pumpWidget(UncontrolledProviderScope(container: container,
    child: MaterialApp(theme: AppTheme.light, home: tasks ? const SupportTasksScreen() : admin
      ? const AccountVerificationAdminScreen() : AccountVerificationSupportScreen(focusUserId: focus))));
  await tester.pumpAndSettle();
  return container;
}
Finder get _verticalList => find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
Future<void> _next(WidgetTester tester) async {
  final more = find.byKey(const ValueKey('verification-more'));
  await tester.scrollUntilVisible(more, 600, scrollable: _verticalList.first, maxScrolls: 40);
  await tester.pumpAndSettle();
  expect(more.hitTestable(), findsOneWidget);
  await tester.tap(more); await tester.pump();
}
Future<void> _review(WidgetTester tester, int id) async {
  final row = find.byKey(ValueKey('verification-$id'));
  await tester.ensureVisible(row); await tester.pumpAndSettle();
  await tester.tap(row); await tester.pumpAndSettle();
}

void main() {
  test('repositories preserve filters and expose validated page metadata', () async {
    final wire = _Wire((_) async => _page(2, [_application(101)], last: 3, total: 101));
    final container = await _container(wire);
    final admin = container.read(accountVerificationRepositoryProvider);
    final support = container.read(accountVerificationSupportRepositoryProvider);
    final first = await admin.adminQueue(status: 'approved', type: 'office', page: 2, userId: 101);
    expect(wire.requests.last.queryParameters, {'status': 'approved', 'type': 'office',
      'user_id': 101, 'page': 2, 'per_page': 40});
    expect(first.total, 101); expect(first.hasMore, isTrue);
    await support.pending(page: 2, userId: 101, perPage: 1);
    expect(wire.requests.last.queryParameters, {'status': 'pending', 'user_id': 101, 'page': 2, 'per_page': 1});
    await expectLater(admin.adminQueue(page: 0), throwsArgumentError);
    await expectLater(admin.adminQueue(userId: 0), throwsArgumentError);
    await expectLater(support.pending(perPage: 101), throwsArgumentError);
    expect(wire.pages, [2, 2]);
  });

  testWidgets('focused support task reaches applicant101 with one exact lookup and no unrelated profiles', (tester) async {
    final wire = _Wire((r) async => r.queryParameters['user_id'] == 101
      ? _page(1, [_application(101)])
      : _page(1, [for (var id = 201; id >= 102; id--) _application(id)], last: 2, total: 101));
    await _open(tester, wire, admin: false, focus: 101);
    expect(wire.requests.single.queryParameters, {'status': 'pending', 'user_id': 101, 'page': 1, 'per_page': 1});
    expect(find.text('Synthetic applicant 101'), findsOneWidget);
    expect(find.text('Synthetic applicant 201'), findsNothing);
    expect(find.text('طلب التحقق غير موجود في قائمة المراجعة الحالية.'), findsNothing);
    await _review(tester, 101);
    expect(find.text('Synthetic region'), findsOneWidget);
    expect(wire.requests.length, 1);
    expect(find.byKey(const ValueKey('verification-more')), findsNothing);
  });

  for (final boundary in ['account switch', 'same-ID replacement', 'same-account relogin']) {
    testWidgets('task navigation binds focus101 before the first frame across $boundary', (tester) async {
      final wire = _Wire((r) async => r.path == '/admin/workspace/tasks'
        ? _page(1, [{'id': 7, 'source_type': 'account_verification', 'source_id': 101,
            'subject': 'Synthetic verification task', 'status': 'in_progress',
            'priority': 'normal', 'is_mine': true, 'can_claim': false}])
        : _page(1, [_application(101)]));
      final container = await _open(tester, wire, admin: false, tasks: true);
      await tester.tap(find.text('فتح'));
      final auth = container.read(authControllerProvider.notifier) as _Auth;
      if (boundary == 'same-ID replacement') {
        Stage6SecureSessionStore.instance.beginSessionChange(); auth.change(6);
      } else { auth.change(null); auth.change(boundary == 'account switch' ? 7 : 6); }
      await tester.pumpAndSettle();
      expect(wire.requests.where((r) => r.path == '/admin/account-verifications'), isEmpty);
      expect(find.text('Synthetic applicant 101'), findsNothing);
      expect(find.text('تغيّر الحساب'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('an unavailable focused applicant uses exact empty result without falling back to bulk data', (tester) async {
    final wire = _Wire((_) async => _page(1, []));
    await _open(tester, wire, admin: false, focus: 101);
    expect(wire.requests.single.queryParameters['user_id'], 101);
    expect(find.text('طلب التحقق غير موجود في قائمة المراجعة الحالية.'), findsOneWidget);
  });

  for (final admin in [false, true]) {
    final surface = admin ? 'admin queue' : 'support queue';
    test('$surface rejects invalid metadata and credentials from a replacement session', () async {
      final credentials = _Credentials();
      final wire = _Wire((_) async => {'data': <Object>[]});
      final container = await _container(wire, credentials: credentials);
      Future<Object> read() => admin
        ? container.read(accountVerificationRepositoryProvider).adminQueue()
        : container.read(accountVerificationSupportRepositoryProvider).pending();
      await expectLater(read(), throwsStateError);
      credentials.pending = Completer<void>();
      final rejected = expectLater(read(), throwsStateError);
      Stage6SecureSessionStore.instance.beginSessionChange();
      credentials.pending!.complete();
      await rejected;
      expect(wire.requests.length, 1);
    });

    testWidgets('$surface retains40 rows on page2 failure and retries, deduplicates and ends', (tester) async {
      var fail = true;
      final wire = _Wire((r) async {
        if (r.queryParameters['page'] == 1) {
          return _page(1, [for (var id = 1; id <= 40; id++) _application(id)], last: 2, total: 41);
        }
        if (fail) throw _failure(r, 503);
        return _page(2, [_application(40, name: 'Updated applicant40'), _application(41)], last: 2, total: 41);
      });
      await _open(tester, wire, admin: admin);
      await _next(tester); await tester.pumpAndSettle();
      final retry = find.text('إعادة المحاولة');
      await tester.scrollUntilVisible(retry, 200, scrollable: _verticalList.first);
      await tester.pumpAndSettle(); await tester.ensureVisible(retry); await tester.pumpAndSettle();
      expect(retry.hitTestable(), findsOneWidget);
      expect(find.byType(AppErrorState), findsNothing);
      expect(wire.pages, [1, 2]);
      fail = false; await tester.tap(retry.hitTestable()); await tester.pumpAndSettle();
      expect(wire.pages, [1, 2, 2]);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('verification-41')), 200, scrollable: _verticalList.first);
      await tester.pumpAndSettle();
      expect(find.text('Updated applicant40'), findsOneWidget);
      expect(find.byKey(const ValueKey('verification-40')), findsOneWidget);
      expect(find.byKey(const ValueKey('verification-more')), findsNothing);
      await tester.drag(_verticalList.first, const Offset(0, -600)); await tester.pumpAndSettle();
      expect(wire.pages, [1, 2, 2]);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('verification-1')), -600,
        scrollable: _verticalList.first, maxScrolls: 40);
      expect(find.byKey(const ValueKey('verification-1')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$surface removes all retained private rows on page2 access denial', (tester) async {
      final wire = _Wire((r) async {
        if (r.queryParameters['page'] == 2) throw _failure(r, 403);
        return _page(1, [_application(1)], last: 2, total: 2);
      });
      await _open(tester, wire, admin: admin); await _next(tester); await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('verification-1')), findsNothing);
      expect(find.byType(AppErrorState), findsOneWidget);
    });

    testWidgets('$surface ignores page2 after a successful refresh', (tester) async {
      final pending = Completer<Object>(); var firstLoads = 0;
      final wire = _Wire((r) async {
        if (r.queryParameters['page'] == 2) return pending.future;
        return ++firstLoads == 1 ? _page(1, [_application(1)], last: 2, total: 2)
          : _page(1, [_application(10)]);
      });
      await _open(tester, wire, admin: admin); await _next(tester);
      await tester.tap(find.byTooltip('تحديث')); await tester.pump();
      pending.complete(_page(2, [_application(99)], last: 2)); await tester.pumpAndSettle();
      expect(wire.pages, [1, 2, 1]);
      expect(find.byKey(const ValueKey('verification-10')), findsOneWidget);
      expect(find.byKey(const ValueKey('verification-99')), findsNothing);
    });

    testWidgets('$surface keeps pages during same-session account metadata refresh', (tester) async {
      final wire = _Wire((_) async => _page(1, [_application(1)], last: 2, total: 2));
      final container = await _open(tester, wire, admin: admin);
      (container.read(authControllerProvider.notifier) as _Auth).change(6); await tester.pumpAndSettle();
      expect(wire.pages, [1]); expect(find.byKey(const ValueKey('verification-1')), findsOneWidget);
    });

    for (final boundary in ['account switch', 'same-ID replacement', 'same-account relogin']) {
      testWidgets('$surface discards late pages across $boundary', (tester) async {
        final pending = Completer<Object>(); var firstLoads = 0;
        final wire = _Wire((r) async {
          if (r.queryParameters['page'] == 2) return pending.future;
          return ++firstLoads == 1 ? _page(1, [_application(1)], last: 2, total: 2)
            : _page(1, [_application(10)]);
        });
        final container = await _open(tester, wire, admin: admin); await _next(tester);
        final auth = container.read(authControllerProvider.notifier) as _Auth;
        if (boundary == 'same-ID replacement') {
          Stage6SecureSessionStore.instance.beginSessionChange(); auth.change(6);
        } else { auth.change(null); auth.change(boundary == 'account switch' ? 7 : 6); }
        pending.complete(_page(2, [_application(99)], last: 2)); await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('verification-1')), findsNothing);
        expect(find.byKey(const ValueKey('verification-99')), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('$surface refuses document actions after an epoch change before auth emits', (tester) async {
      final wire = _Wire((_) async => _page(1, [_application(101)]));
      await _open(tester, wire, admin: admin); await _review(tester, 101);
      final document = find.text(admin ? 'البطاقة الشخصية أو جواز السفر' : 'صورة الهوية / الجواز');
      await tester.ensureVisible(document); await tester.pumpAndSettle();
      Stage6SecureSessionStore.instance.beginSessionChange();
      await tester.tap(document); await tester.pumpAndSettle();
      expect(wire.requests.where((r) => r.path.contains('/documents/')), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$surface never displays document bytes from the preceding session', (tester) async {
      final pending = Completer<Object>();
      final wire = _Wire((r) async => r.path.contains('/documents/')
        ? pending.future : _page(1, [_application(101)]));
      final container = await _open(tester, wire, admin: admin);
      await _review(tester, 101);
      final document = find.text(admin ? 'البطاقة الشخصية أو جواز السفر' : 'صورة الهوية / الجواز');
      await tester.ensureVisible(document); await tester.pumpAndSettle();
      await tester.tap(document);
      for (var i = 0; i < 8; i++) { await tester.pump(); }
      expect(wire.requests.where((r) => r.path.endsWith('/101/documents/identity_document')).length, 1);
      Stage6SecureSessionStore.instance.beginSessionChange();
      (container.read(authControllerProvider.notifier) as _Auth).change(6);
      pending.complete(<int>[1, 2, 3]); await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(find.text('تعذر عرض هذا الملف كصورة.'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('admin type-filter change discards a pending earlier page', (tester) async {
    final pending = Completer<Object>();
    final wire = _Wire((r) async {
      if (r.queryParameters['page'] == 2) return pending.future;
      return r.queryParameters['type'] == 'office' ? _page(1, [_application(10)])
        : _page(1, [_application(1)], last: 2, total: 2);
    });
    await _open(tester, wire, admin: true); await _next(tester);
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('مكتب عقارات').last); await tester.pump();
    pending.complete(_page(2, [_application(99)], last: 2)); await tester.pumpAndSettle();
    expect(wire.pages, [1, 2, 1]); expect(wire.requests.last.queryParameters['type'], 'office');
    expect(find.byKey(const ValueKey('verification-10')), findsOneWidget);
    expect(find.byKey(const ValueKey('verification-99')), findsNothing);
  });

  testWidgets('late admin approval cannot close the replacement session page', (tester) async {
    final pending = Completer<Object>();
    final wire = _Wire((r) async => r.path.endsWith('/approve') ? pending.future
      : _page(1, [_application(101)]));
    final container = await _open(tester, wire, admin: true); await _review(tester, 101);
    final approve = find.text('اعتماد التحقق');
    await tester.scrollUntilVisible(approve, 250, scrollable: _verticalList.first);
    await tester.pumpAndSettle(); await tester.tap(approve); await tester.pumpAndSettle();
    await tester.tap(find.text('تأكيد')); await tester.pump(const Duration(milliseconds: 400));
    expect(wire.requests.where((r) => r.path.endsWith('/approve')).length, 1);
    Stage6SecureSessionStore.instance.beginSessionChange();
    (container.read(authControllerProvider.notifier) as _Auth).change(6);
    pending.complete({'data': <String, dynamic>{}});
    // Deliver the response before pumping away the prior detail subtree.
    await tester.pumpAndSettle();
    expect(find.text('تغيّر الحساب'), findsOneWidget);
    expect(find.text('Synthetic applicant 101'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

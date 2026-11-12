import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:real_estate_mobile/core/local/stage6_secure_session_store.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/features/account/data/account_safety_repository.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/account/presentation/account_safety_screen.dart';

import 'support/phase23_widget_tools.dart';

AuthUser _user(int id) => AuthUser.fromJson({'id': id, 'name': 'Synthetic erasure test', 'account_status': 'active'});
class _Auth extends AuthController {
  int logouts = 0;
  @override
  Future<AuthUser?> build() async => _user(66);
  void change(int id) => state = AsyncData(_user(id));
  @override
  Future<void> logout() async { logouts++; state = const AsyncData(null); }
}
class _Safety implements AccountSafetyRepository {
  final pending = Completer<void>();
  int erasures = 0;
  @override
  Future<BlockedAccountPage> blocked({int page = 1}) async => const BlockedAccountPage([], false);
  @override
  Future<DeletionRequestStatus> deletionStatus() async => const DeletionRequestStatus(status: 'not_requested');
  @override
  Future<void> eraseAccount() async { erasures++; await pending.future; }
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}
class _Credentials implements AuthRepository {
  final pending = Completer<Options>();
  @override
  Future<Options> requiredAuthOptions() => pending.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}
Future<(_Auth, ProviderContainer)> _open(WidgetTester tester, _Safety repository, {double scale = 1}) async {
  tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
  final auth = _Auth();
  final c = ProviderContainer(overrides: [authControllerProvider.overrideWith(() => auth),
    accountSafetyRepositoryProvider.overrideWithValue(repository)]);
  await c.read(authControllerProvider.future);
  final router = GoRouter(initialLocation: '/safety', routes: [
    GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('Synthetic guest home'))),
    GoRoute(path: '/safety', builder: (_, __) => const AccountSafetyScreen()),
  ]);
  addTearDown(() { router.dispose(); c.dispose(); });
  await tester.pumpWidget(UncontrolledProviderScope(container: c, child: MaterialApp.router(
    theme: AppTheme.light, routerConfig: router, builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!))));
  await tester.pumpAndSettle();
  final button = find.byKey(const ValueKey('delete-account-forever'));
  await tester.scrollUntilVisible(button, 300, scrollable: find.byType(Scrollable).first, maxScrolls: 20);
  await tester.tap(button); await tester.pumpAndSettle();
  return (auth, c);
}
Future<void> _confirm(WidgetTester tester, [String phrase = 'حذف حسابي نهائيًا']) async {
  final field = find.byKey(const ValueKey('account-erasure-confirmation'));
  await tester.ensureVisible(field); await tester.enterText(field, phrase);
  final button = find.byKey(const ValueKey('erase-account-forever'));
  await tester.ensureVisible(button); await tester.tap(button);
  await pumpPhase23Request(tester);
}

void main() {
  phase23WidgetTest('confirmed erasure keeps the controller alive through dismissal and logs out once', (tester) async {
    final repository = _Safety(); final (auth, _) = await _open(tester, repository);
    await _confirm(tester);
    expect(repository.erasures, 1); expect(auth.logouts, 0);
    expect(find.byKey(const ValueKey('account-erasure-confirmation')), findsNothing);
    expect(tester.takeException(), isNull);
    repository.pending.complete(); await tester.pumpAndSettle();
    expect(auth.logouts, 1); expect(tester.takeException(), isNull);
  });

  phase23WidgetTest('incorrect phrase and cancellation never erase an account', (tester) async {
    final repository = _Safety(); final (auth, _) = await _open(tester, repository);
    await _confirm(tester, 'wrong phrase'); await tester.pumpAndSettle();
    expect(repository.erasures, 0); expect(auth.logouts, 0);
    final open = find.byKey(const ValueKey('delete-account-forever'));
    await tester.ensureVisible(open); await tester.tap(open); await tester.pumpAndSettle();
    await tester.tap(find.text('إلغاء')); await tester.pumpAndSettle();
    expect(repository.erasures, 0); expect(tester.takeException(), isNull);
  });

  for (final sameId in [false, true]) {
    phase23WidgetTest('old confirmation cannot erase after ${sameId ? 'same-ID renewal' : 'account switch'} before a frame', (tester) async {
      final repository = _Safety(); final (auth, _) = await _open(tester, repository);
      await tester.enterText(find.byKey(const ValueKey('account-erasure-confirmation')), 'حذف حسابي نهائيًا');
      Stage6SecureSessionStore.instance.beginSessionChange(); auth.change(sameId ? 66 : 7);
      await tester.tap(find.byKey(const ValueKey('erase-account-forever')));
      await tester.pumpAndSettle();
      expect(repository.erasures, 0); expect(auth.logouts, 0);
      expect(find.byKey(const ValueKey('account-erasure-confirmation')), findsNothing);
      expect(tester.takeException(), isNull);
    });
    for (final fail in [false, true]) {
      phase23WidgetTest('late erasure ${fail ? 'failure' : 'receipt'} cannot affect ${sameId ? 'renewed' : 'other'} session', (tester) async {
        final repository = _Safety(); final (auth, c) = await _open(tester, repository);
        await _confirm(tester); expect(repository.erasures, 1);
        Stage6SecureSessionStore.instance.beginSessionChange(); auth.change(sameId ? 66 : 7);
        await tester.pumpAndSettle();
        if (fail) { repository.pending.completeError(StateError('Synthetic old failure')); }
        else { repository.pending.complete(); }
        await tester.pumpAndSettle();
        expect(auth.logouts, 0);
        expect(c.read(authControllerProvider).asData!.value!.id, sameId ? 66 : 7);
        expect(find.textContaining('Synthetic old failure'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  phase23WidgetTest('erasure confirmation stays reachable at320 and2.4 text scale', (tester) async {
    final repository = _Safety(); await _open(tester, repository, scale: 2.4);
    final field = find.byKey(const ValueKey('account-erasure-confirmation'));
    await tester.ensureVisible(field); await tester.pumpAndSettle();
    expect(field.hitTestable(), findsOneWidget);
    final cancel = find.text('إلغاء'); await tester.ensureVisible(cancel);
    expect(cancel.hitTestable(), findsOneWidget);
    await tester.tap(cancel); await tester.pumpAndSettle();
    expect(repository.erasures, 0); expect(tester.takeException(), isNull);
  });

  test('erasure cannot acquire a replacement-session credential after storage waits', () async {
    final credentials = _Credentials(); final dio = Dio(); var sent = false;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (_, __) { sent = true; }));
    addTearDown(() => dio.close(force: true));
    final repository = AccountSafetyRepository(dio, credentials, actorId: 66, currentActor: () => 66);
    final rejected = expectLater(repository.eraseAccount(), throwsStateError);
    Stage6SecureSessionStore.instance.beginSessionChange();
    credentials.pending.complete(Options(headers: {'Authorization': 'Bearer synthetic-only'}));
    await rejected; expect(sent, isFalse);
  });
}

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/local/stage6_secure_session_store.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/messages/data/push_registration_repository.dart';

AuthUser _user(int id) => AuthUser.fromJson({'id': id, 'name': 'Synthetic $id',
  'account_status': 'active', 'phone_verified_at': '2026-10-25T00:00:00Z'});
const _emailA = WhatsAppAuthPending(phone: '', email: 'a@example.invalid', isNewAccount: false);
const _emailB = WhatsAppAuthPending(phone: '', email: 'b@example.invalid', isNewAccount: false);

Response<Map<String, dynamic>> _accepted(RequestOptions request, int id) =>
  Response(requestOptions: request, statusCode: 200,
    data: {'data': {'token': 'synthetic-$id', 'user': {'id': id, 'name': 'Synthetic $id'}}});

class _NoPush implements PushRegistrationRepository {
  @override
  Future<bool> syncIfGranted() async => false;
  @override
  Future<void> unregister() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}

class _DeferredAuth implements AuthRepository {
  Completer<AuthUser?>? restore;
  Completer<AuthUser>? profile;
  @override
  Future<AuthUser?> restoreSession() async => restore == null ? _user(1) : restore!.future;
  @override
  Future<void> logout() async {}
  @override
  Future<AuthResult> login({required String login, required String password}) async =>
    AuthResult(user: _user(2), legacyListingsClaimed: 0);
  @override
  Future<AuthUser> completeProfile(String name) => profile!.future;
  @override
  Future<AuthUser> updateProfile({required String name, required String phone, String? email}) => profile!.future;
  @override
  Future<AuthUser> verifyPhone(String code) => profile!.future;
  @override
  Future<AuthUser> verifyEmail(String code) => profile!.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}

ProviderContainer _container(_DeferredAuth repository) {
  final container = ProviderContainer(overrides: [
    authRepositoryProvider.overrideWithValue(repository),
    pushRegistrationRepositoryProvider.overrideWithValue(_NoPush()),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('real_estate/secure_store');
  String? stored;

  setUp(() {
    stored = 'synthetic-1';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'readToken') return stored;
      if (call.method == 'writeToken') {
        stored = (call.arguments as Map)['token'] as String;
        return null;
      }
      if (call.method == 'deleteToken') { stored = null; return null; }
      throw StateError('Unexpected native method ${call.method}');
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

  test('late unauthorized restoration cannot erase a replacement token', () async {
    final entered = Completer<void>(), release = Completer<void>();
    final dio = Dio()..interceptors.add(InterceptorsWrapper(onRequest: (request, handler) async {
      entered.complete();
      await release.future;
      handler.reject(DioException(requestOptions: request, type: DioExceptionType.badResponse,
        response: Response<void>(requestOptions: request, statusCode: 401)));
    }));
    addTearDown(() => dio.close(force: true));
    final restoring = AuthRepository(dio).restoreSession();
    final rejected = expectLater(restoring, throwsStateError);
    await entered.future;
    await Stage6SecureSessionStore.instance.writeToken('synthetic-2');
    release.complete();
    await rejected;
    expect(stored, 'synthetic-2');
  });

  test('older email login cannot overwrite a newer accepted login', () async {
    final entered = Completer<void>(), release = Completer<void>();
    final dio = Dio()..interceptors.add(InterceptorsWrapper(onRequest: (request, handler) async {
      final first = (request.data as Map)['email'] == _emailA.email;
      if (first) { entered.complete(); await release.future; }
      handler.resolve(_accepted(request, first ? 1 : 2));
    }));
    addTearDown(() => dio.close(force: true));
    final repository = AuthRepository(dio);
    final rejected = expectLater(repository.verifyWhatsApp(_emailA, 'synthetic-code'), throwsStateError);
    await entered.future;
    expect((await repository.verifyWhatsApp(_emailB, 'synthetic-code')).user.id, 2);
    release.complete();
    await rejected;
    expect(stored, 'synthetic-2');
  });

  test('finishing an old logout cannot erase a newer accepted login', () async {
    final entered = Completer<void>(), release = Completer<void>();
    final dio = Dio()..interceptors.add(InterceptorsWrapper(onRequest: (request, handler) async {
      if (request.path == '/auth/logout') {
        entered.complete(); await release.future;
        handler.resolve(Response<void>(requestOptions: request, statusCode: 200));
      } else { handler.resolve(_accepted(request, 2)); }
    }));
    addTearDown(() => dio.close(force: true));
    final repository = AuthRepository(dio);
    final logout = repository.logout();
    await entered.future;
    await repository.verifyWhatsApp(_emailB, 'synthetic-code');
    release.complete();
    await logout;
    expect(stored, 'synthetic-2');
  });

  test('an in-flight login cannot restore credentials after logout', () async {
    final entered = Completer<void>(), release = Completer<void>();
    final dio = Dio()..interceptors.add(InterceptorsWrapper(onRequest: (request, handler) async {
      if (request.path == '/auth/email/login') {
        entered.complete(); await release.future;
        handler.resolve(_accepted(request, 1));
      } else { handler.resolve(Response<void>(requestOptions: request, statusCode: 200)); }
    }));
    addTearDown(() => dio.close(force: true));
    final repository = AuthRepository(dio);
    final rejected = expectLater(repository.verifyWhatsApp(_emailA, 'synthetic-code'), throwsStateError);
    await entered.future;
    await repository.logout();
    release.complete();
    await rejected;
    expect(stored, isNull);
  });

  test('late password reset cannot clear a subsequent login', () async {
    final entered = Completer<void>(), release = Completer<void>();
    final dio = Dio()..interceptors.add(InterceptorsWrapper(onRequest: (request, handler) async {
      if (request.path == '/auth/password/reset') {
        entered.complete(); await release.future;
        handler.resolve(Response<void>(requestOptions: request, statusCode: 200));
      } else { handler.resolve(_accepted(request, 2)); }
    }));
    addTearDown(() => dio.close(force: true));
    final repository = AuthRepository(dio);
    final rejected = expectLater(repository.resetPassword(login: 'a@example.invalid',
      code: 'synthetic-code', password: 'synthetic-password'), throwsStateError);
    await entered.future;
    await repository.verifyWhatsApp(_emailB, 'synthetic-code');
    release.complete();
    await rejected;
    expect(stored, 'synthetic-2');
  });

  test('refresh cannot resurrect the visible account after logout', () async {
    final repository = _DeferredAuth();
    final container = _container(repository);
    await container.read(authControllerProvider.future);
    repository.restore = Completer<AuthUser?>();
    final controller = container.read(authControllerProvider.notifier);
    final refreshing = controller.refresh();
    await controller.logout();
    repository.restore!.complete(_user(1));
    await refreshing;
    expect(container.read(authControllerProvider).requireValue, isNull);
  });

  test('initial restoration cannot resurrect an account after explicit logout', () async {
    final repository = _DeferredAuth()..restore = Completer<AuthUser?>();
    final container = _container(repository);
    final restoring = container.read(authControllerProvider.future);
    await container.read(authControllerProvider.notifier).logout();
    repository.restore!.complete(_user(1));
    await restoring;
    await container.pump();
    expect(container.read(authControllerProvider).requireValue, isNull);
  });

  for (final action in ['complete', 'update', 'phone', 'email']) {
    test('late $action receipt cannot replace the next visible account', () async {
      final repository = _DeferredAuth();
      final container = _container(repository);
      await container.read(authControllerProvider.future);
      repository.profile = Completer<AuthUser>();
      final controller = container.read(authControllerProvider.notifier);
      final Future<void> operation = switch (action) {
        'complete' => controller.completeProfile('Old synthetic name'),
        'update' => controller.updateProfile(name: 'Old synthetic name', phone: '+12025550101'),
        'phone' => controller.verifyPhone('synthetic-code'),
        _ => controller.verifyEmail('synthetic-code'),
      };
      final rejected = expectLater(operation, throwsStateError);
      await controller.logout();
      await controller.login(login: 'b@example.invalid', password: 'synthetic-password');
      repository.profile!.complete(_user(1));
      await rejected;
      expect(container.read(authControllerProvider).requireValue?.id, 2);
    });
  }
}

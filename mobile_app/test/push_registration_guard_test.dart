import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/messages/data/push_registration_repository.dart';
import 'package:real_estate_mobile/core/local/stage6_secure_session_store.dart';

void main() {
  test('only valid opted-in Android registration can be sent to Laravel', () {
    final valid = PushNativeRegistration.fromMap({
      'configured': true, 'granted': true,
      'generation': 'synthetic-generation',
      'installation_id': '11111111-2222-3333-4444-555555555555',
      'token': '  ${List.filled(32, 'f').join()}  ',
    });
    expect(valid.hasUsableInstallationId, isTrue);
    expect(valid.hasUsableToken, isTrue);
    expect(valid.canRegister, isTrue);
    expect(valid.token, List.filled(32, 'f').join());
  });

  test('missing or malformed bridge data never permits registration', () {
    for (final payload in <Map<String, dynamic>>[
      {},
      {'configured': true, 'granted': false,
       'installation_id': '11111111-2222-3333-4444-555555555555',
       'token': List.filled(32, 'f').join()},
      {'configured': true, 'granted': true, 'installation_id': '', 'token': List.filled(32, 'f').join()},
      {'configured': true, 'granted': true, 'installation_id': 'abc', 'token': List.filled(32, 'f').join()},
      {'configured': true, 'granted': true, 'installation_id': List.filled(201, 'x').join(), 'token': List.filled(32, 'f').join()},
      {'configured': true, 'granted': true,
       'installation_id': '11111111-2222-3333-4444-555555555555',
       'token': 'short'},
      {'configured': true, 'granted': true,
       'installation_id': '11111111-2222-3333-4444-555555555555',
       'token': List.filled(4097, 'f').join()},
      {'configured': true, 'granted': true,
       'installation_id': 1234567890123456789, 'token': List.filled(32, 'f').join()},
      {'configured': true, 'granted': true,
       'installation_id': '11111111-2222-3333-4444-555555555555', 'token': 1234567890123456789},
    ]) {
      expect(PushNativeRegistration.fromMap({'generation': 'synthetic-generation', ...payload}).canRegister, isFalse, reason: '$payload');
    }
  });
  test('invalid native registration performs no backend request', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('real_estate/push');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => {
      'configured': true,
      'granted': true,
      'installation_id': '',
      'token': List.filled(32, 't').join(),
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    var requests = 0;
    final dio = Dio()..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests++;
      handler.reject(DioException(requestOptions: options));
    }));
    addTearDown(() => dio.close(force: true));
    final repo = PushRegistrationRepository(dio, _BuildTestAuth(dio));
    expect(await repo.syncIfGranted(), isFalse);
    expect(await repo.requestAndRegister(), isFalse);
    expect(requests, 0);
  });

  test('valid registration reports the compiled Android build to Laravel', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('real_estate/push');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => call.method == 'confirmRegistration' ? true : {
      'configured': true, 'granted': true,
      'generation': 'synthetic-generation',
      'installation_id': '11111111-2222-3333-4444-555555555555',
      'token': List.filled(32, 't').join(),
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    RequestOptions? sent;
    final dio = Dio()..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      sent = options;
      handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200,
        data: {'data': {'registered': true, 'user_id': 101}}));
    }));
    addTearDown(() => dio.close(force: true));
    final repo = PushRegistrationRepository(dio, _BuildTestAuth(dio));
    expect(await repo.syncIfGranted(), isTrue);
    expect(sent?.path, '/push/devices');
    expect((sent?.data as Map)['app_build'],
      const int.fromEnvironment('APP_BUILD_NUMBER', defaultValue: 1));
  });

  test('session changed while native token resolves never reaches backend', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('real_estate/push');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final native = Completer<Map<String, dynamic>>();
    final entered = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (_) { entered.complete(); return native.future; });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    var requests = 0;
    final dio = Dio()..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests++; handler.reject(DioException(requestOptions: options));
    }));
    addTearDown(() => dio.close(force: true));
    final pending = PushRegistrationRepository(dio, _BuildTestAuth(dio)).requestAndRegister();
    final rejected = expectLater(pending, throwsStateError);
    await entered.future;
    Stage6SecureSessionStore.instance.beginSessionChange();
    native.complete({'configured': true, 'granted': true, 'generation': 'old',
      'installation_id': '11111111-2222-3333-4444-555555555555', 'token': List.filled(32, 't').join()});
    await rejected;
    expect(requests, 0);
  });

  test('logout revokes locally before the network and rejects late registration receipts', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('real_estate/push');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final events = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      events.add(call.method);
      if (call.method == 'confirmRegistration') return true;
      return {'configured': true, 'granted': call.method != 'deleteToken', 'generation': 'synthetic-generation',
        'installation_id': '11111111-2222-3333-4444-555555555555', 'token': List.filled(32, 't').join()};
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final entered = Completer<void>();
    final response = Completer<void>();
    final dio = Dio()..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) async {
      events.add(options.method);
      if (options.method == 'POST') { entered.complete(); await response.future; }
      handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200,
        data: {'data': {'registered': true, 'user_id': 101}}));
    }));
    addTearDown(() => dio.close(force: true));
    final repo = PushRegistrationRepository(dio, _BuildTestAuth(dio));
    final pending = repo.requestAndRegister();
    final rejected = expectLater(pending, throwsStateError);
    await entered.future;
    await repo.unregister();
    expect(events.indexOf('deleteToken'), lessThan(events.indexOf('DELETE')));
    response.complete();
    await rejected;
    expect(events, isNot(contains('confirmRegistration')));
  });

  test('a server receipt alone does not claim enrollment if native fence rejects it', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('real_estate/push');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => call.method == 'confirmRegistration' ? false : {
      'configured': true, 'granted': true, 'generation': 'synthetic-old-generation',
      'installation_id': '11111111-2222-3333-4444-555555555555', 'token': List.filled(32, 't').join(),
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final dio = Dio()..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200,
        data: {'data': {'registered': true, 'user_id': 101}}));
    }));
    addTearDown(() => dio.close(force: true));
    expect(await PushRegistrationRepository(dio, _BuildTestAuth(dio)).syncIfGranted(), isFalse);
  });

}

class _BuildTestAuth extends AuthRepository {
  _BuildTestAuth(super.dio);

  @override
  Future<Options> requiredAuthOptions() async => Options(
    headers: {'Authorization': 'Bearer synthetic-build-contract'},
  );
}

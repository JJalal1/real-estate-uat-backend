import 'package:flutter/services.dart';

class Stage6SecureSessionStore {
  Stage6SecureSessionStore._();
  static final Stage6SecureSessionStore instance = Stage6SecureSessionStore._();
  static const _channel = MethodChannel('real_estate/secure_store');
  Future<void> _operations = Future<void>.value();
  int _sessionEpoch = 0;

  int get sessionEpoch => _sessionEpoch;
  int beginSessionChange() => ++_sessionEpoch;

  // A conditional delete and a subsequent login write must not interleave.
  // Failed native operations must also leave the queue usable for retry.
  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _operations.then((_) => operation());
    _operations = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<String?> _readNativeToken() async {
    final token = await _channel.invokeMethod<String>('readToken');
    final value = token?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<String?> readToken() => _serialize(_readNativeToken);

  Future<void> writeToken(String token) {
    beginSessionChange();
    return _serialize(() => _channel.invokeMethod<void>('writeToken', {'token': token}));
  }

  Future<bool> writeTokenIfCurrent(String token, int epoch) => _serialize(() async {
    if (_sessionEpoch != epoch) return false;
    await _channel.invokeMethod<void>('writeToken', {'token': token});
    return _sessionEpoch == epoch;
  });

  Future<void> deleteTokenIfMatches(String expected) => _serialize(() async {
    if (await _readNativeToken() == expected) {
      await _channel.invokeMethod<void>('deleteToken');
    }
  });

  Future<void> deleteToken() {
    beginSessionChange();
    return _serialize(() => _channel.invokeMethod<void>('deleteToken'));
  }
}

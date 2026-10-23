import 'package:flutter/services.dart';

class Stage6SecureSessionStore {
  Stage6SecureSessionStore._();
  static final Stage6SecureSessionStore instance = Stage6SecureSessionStore._();
  static const _channel = MethodChannel('real_estate/secure_store');

  Future<String?> readToken() async {
    final token = await _channel.invokeMethod<String>('readToken');
    final value = token?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> writeToken(String token) =>
      _channel.invokeMethod<void>('writeToken', {'token': token});

  Future<void> deleteToken() => _channel.invokeMethod<void>('deleteToken');
}

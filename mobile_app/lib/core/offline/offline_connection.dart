import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum OfflineConnection { unknown, online, offline }

final offlineConnectionProvider =
    StateNotifierProvider<OfflineConnectionController, OfflineConnection>(
        (ref) => OfflineConnectionController());
final offlineResumeRevisionProvider = StateProvider<int>((ref) => 0);

class OfflineConnectionController extends StateNotifier<OfflineConnection> {
  OfflineConnectionController() : super(OfflineConnection.unknown);
  static const _channel = MethodChannel('real_estate/network');
  Dio? _probe;
  Future<void>? _checking;
  bool _disposed = false;
  bool usedSnapshot = false;
  OfflineConnection get current => state;
  void configure(String baseUrl) {
    _probe ??= Dio(BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 3),
        receiveTimeout: const Duration(seconds: 3)));
  }

  void offline() {
    if (!_disposed && state != OfflineConnection.offline)
      state = OfflineConnection.offline;
  }

  void online() {
    if (!_disposed && state != OfflineConnection.online)
      state = OfflineConnection.online;
  }

  Future<void> check({bool force = false}) =>
      _checking ??= _check(force).whenComplete(() => _checking = null);
  Future<void> _check(bool force) async {
    try {
      final snapshot = await _channel
          .invokeMapMethod<String, dynamic>('imageNetworkState')
          .timeout(const Duration(seconds: 1));
      if (snapshot?['connected'] == false) {
        offline();
        return;
      }
    } catch (_) {/* Other platforms use the API probe. */}
    if (!force && state == OfflineConnection.online) return;
    final probe = _probe;
    if (probe == null) return;
    try {
      final r = await probe
          .get<dynamic>('/health')
          .timeout(const Duration(seconds: 4));
      if (r.statusCode == 200 && r.data is Map)
        online();
      else
        offline();
    } catch (_) {
      offline();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _probe?.close(force: true);
    super.dispose();
  }
}

bool offlineTransportFailure(Object error) =>
    error is DioException &&
    error.response == null &&
    const [
      DioExceptionType.connectionError,
      DioExceptionType.connectionTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.sendTimeout
    ].contains(error.type);

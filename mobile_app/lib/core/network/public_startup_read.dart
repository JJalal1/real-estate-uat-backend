import 'dart:async';

import 'package:dio/dio.dart';

/// Bounded recovery for the two anonymous home reads on the sleeping UAT host.
/// It is not installed on the shared Dio client or on writes.
class PublicStartupRead {
  PublicStartupRead(this._dio, {
    required this.enabled,
    this.budget = const Duration(seconds: 75),
    this.retryDelays = const [
      Duration(seconds: 1), Duration(seconds: 2), Duration(seconds: 4),
      Duration(seconds: 8), Duration(seconds: 12), Duration(seconds: 16),
    ],
  });

  final Dio _dio;
  final bool enabled;
  final Duration budget;
  final List<Duration> retryDelays;

  Future<Response<Map<String, dynamic>>> get(String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async {
    final token = cancelToken ?? CancelToken();
    if (!enabled) {
      return _dio.get<Map<String, dynamic>>(path,
        queryParameters: queryParameters, cancelToken: token);
    }
    var expired = false;
    final deadline = Timer(budget, () {
      expired = true;
      token.cancel('Public home startup deadline');
    });
    try {
      for (var attempt = 0; ; attempt++) {
        if (token.isCancelled) throw token.cancelError!;
        try {
          return await _dio.get<Map<String, dynamic>>(path,
            queryParameters: queryParameters, cancelToken: token);
        } on DioException catch (error) {
          if (token.isCancelled || !_transient(error) || attempt >= retryDelays.length) {
            rethrow;
          }
          await _wait(retryDelays[attempt], token);
        }
      }
    } on DioException catch (error) {
      if (expired) {
        throw DioException(requestOptions: error.requestOptions,
          type: DioExceptionType.receiveTimeout,
          message: 'Public home startup deadline exceeded.');
      }
      rethrow;
    } finally {
      deadline.cancel();
    }
  }

  Future<void> _wait(Duration delay, CancelToken token) async {
    final done = Completer<void>();
    final timer = Timer(delay, done.complete);
    token.whenCancel.then((error) {
      if (!done.isCompleted) done.completeError(error);
    });
    try { await done.future; } finally { timer.cancel(); }
  }

  bool _transient(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError) return true;
    return error.type == DioExceptionType.badResponse &&
        const [502, 503, 504].contains(error.response?.statusCode);
  }
}

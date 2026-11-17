import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum OfflineConnection { unknown, online, offline, unavailable }

final offlineConnectionProvider =
    StateNotifierProvider<OfflineConnectionController, OfflineConnection>(
        (ref) => OfflineConnectionController());
final offlineResumeRevisionProvider = StateProvider<int>((ref) => 0);

class OfflineConnectionController extends StateNotifier<OfflineConnection> {
  OfflineConnectionController({
    Dio? probe,
    Future<Map<String, dynamic>?> Function()? networkSnapshot,
  })  : _probe = probe,
        _networkSnapshot = networkSnapshot ?? _nativeSnapshot,
        super(OfflineConnection.unknown);
  static const _channel = MethodChannel('real_estate/network');
  static Future<Map<String, dynamic>?> _nativeSnapshot() =>
      _channel.invokeMapMethod<String, dynamic>('imageNetworkState');
  final Future<Map<String, dynamic>?> Function() _networkSnapshot;
  Dio? _probe;
  Duration _probeDeadline = const Duration(seconds: 30);
  CancelToken? _activeProbe;
  Future<void>? _checking;
  bool _disposed = false;
  int _revision = 0;
  int _lastHardOfflineRevision = -1;
  bool usedSnapshot = false;
  OfflineConnection get current => state;
  int get revision => _revision;

  void configure(String baseUrl,
      {Duration connectTimeout = const Duration(seconds: 15),
      Duration receiveTimeout = const Duration(seconds: 15)}) {
    if (connectTimeout <= Duration.zero || receiveTimeout <= Duration.zero) {
      throw ArgumentError('Reachability timeouts must be positive');
    }
    _probe ??= Dio();
    _probe!.options
      ..baseUrl = baseUrl
      ..connectTimeout = connectTimeout
      ..receiveTimeout = receiveTimeout;
    _probeDeadline = connectTimeout + receiveTimeout;
  }

  void _cancelProbe() {
    _activeProbe?.cancel('Newer connection evidence');
    _activeProbe = null;
  }

  /// Only a confirmed loss of the device route enters hard offline mode.
  void offline() {
    if (_disposed) return;
    _lastHardOfflineRevision = ++_revision;
    _cancelProbe();
    if (state != OfflineConnection.offline) state = OfflineConnection.offline;
  }

  /// A fresh real API receipt is stronger evidence than platform validation.
  /// Advance even when already online so an older failing probe cannot win.
  void online() {
    if (_disposed) return;
    _revision++;
    _cancelProbe();
    if (state != OfflineConnection.online) state = OfflineConnection.online;
  }

  void reachable(int startedRevision) {
    if (_disposed || startedRevision < _lastHardOfflineRevision) return;
    online();
  }

  void _unavailableIfCurrent(int startedRevision) {
    if (_disposed || startedRevision != _revision) return;
    _revision++;
    _cancelProbe();
    if (state != OfflineConnection.unavailable) {
      state = OfflineConnection.unavailable;
    }
  }

  /// A timeout says this service could not be reached, not that Wi-Fi is off.
  /// Recheck the actual route without delaying the request's cache/error path.
  void transportFailure(int startedRevision) {
    if (_disposed ||
        startedRevision != _revision ||
        state == OfflineConnection.offline) return;
    _unavailableIfCurrent(startedRevision);
    final failureRevision = _revision;
    final pending = _checking;
    unawaited(() async {
      if (pending != null) await pending;
      if (!_disposed && _revision == failureRevision) {
        await check(force: true);
      }
    }()
        .catchError((Object _) {}));
  }

  Future<void> check({bool force = false}) {
    if (_disposed) return Future.value();
    // Both manual and periodic checks may recover an unvalidated but usable
    // network. Coalesce them, never skip probing because Android did not validate.
    return _checking ??= _check().whenComplete(() => _checking = null);
  }

  Future<void> _check() async {
    final startedRevision = _revision;
    try {
      final snapshot =
          await _networkSnapshot().timeout(const Duration(seconds: 1));
      if (_disposed || startedRevision != _revision) return;
      // connected/validated describe Android's external validation. They are
      // advisory: DNS filtering or local network policy may block that probe
      // while the application's own API remains reachable.
      if (snapshot?['networkAvailable'] == false) {
        offline();
        return;
      }
    } catch (_) {/* Other platforms use the API probe. */}
    if (_disposed || startedRevision != _revision) return;
    final probe = _probe;
    if (probe == null) return;
    final cancelToken = CancelToken();
    _activeProbe = cancelToken;
    try {
      final r = await probe
          .get<dynamic>('/health',
              cancelToken: cancelToken,
              options: Options(followRedirects: false))
          .timeout(_probeDeadline, onTimeout: () {
        cancelToken.cancel('Reachability deadline');
        throw TimeoutException('API reachability deadline');
      });
      if (r.statusCode == 200 && r.data is Map && r.data['status'] == 'ok') {
        reachable(startedRevision);
      } else {
        _unavailableIfCurrent(startedRevision);
      }
    } catch (_) {
      _unavailableIfCurrent(startedRevision);
    } finally {
      if (identical(_activeProbe, cancelToken)) _activeProbe = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelProbe();
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

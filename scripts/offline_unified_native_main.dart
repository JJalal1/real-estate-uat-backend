import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
// Isolated native acceptance entry. Never shipped in the ordinary APK.
// No real account, credentials, auth/AI/business API, external HTTP or upload.
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maps;
import 'package:path_provider/path_provider.dart';
import 'package:real_estate_mobile/core/local/listing_recovery_store.dart';
import 'package:real_estate_mobile/core/offline/offline_connection.dart';
import 'package:real_estate_mobile/core/offline/offline_http.dart';
import 'package:real_estate_mobile/core/offline/offline_store.dart';
import 'package:real_estate_mobile/features/messages/data/message_outbox.dart';
import 'package:real_estate_mobile/features/properties/data/public_photo_disk_cache.dart';
import 'package:real_estate_mobile/features/properties/data/public_photo_loader.dart';

const _package = String.fromEnvironment('APP_PACKAGE_ID');
const _enabled = bool.fromEnvironment('AQER_OFFLINE_NATIVE_PROBE');
const _origin = 'https://synthetic.invalid';
const _actor = 999910;
const _network = MethodChannel('real_estate/network');
const _secure = MethodChannel('real_estate/secure_store');
final _bytes = Uint8List.fromList(base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='));
final _store = OfflineStore();

class _NoHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw const SocketException('Native probe HTTP denied');
}

class _ProbeOutbox extends MessageOutbox {
  _ProbeOutbox(
      {required super.actor,
      required super.store,
      required super.current,
      required super.connected,
      required super.resolveThread,
      required super.sendMessage});
  List<PendingMessage> get rows => state;
}

class _SyntheticWire implements HttpClientAdapter {
  _SyntheticWire(this.online);
  final bool online;
  int calls = 0;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls++;
    if (!online) {
      throw DioException(
          requestOptions: options, type: DioExceptionType.connectionError);
    }
    if (options.uri.path.endsWith('/auth/email/login')) {
      return ResponseBody.fromString(
          jsonEncode({
            'data': {
              'token': 'synthetic-native-only',
              'user': {
                'id': _actor,
                'name': 'synthetic native actor',
                'account_status': 'active',
                'phone_verified_at': '2026-11-17T00:00:00Z',
                'profile_completed_at': '2026-11-17T00:00:00Z',
                'roles': <String>[],
                'permissions': <String>[]
              }
            }
          }),
          200,
          headers: {
            'content-type': ['application/json']
          });
    }
    if (options.uri.path.contains('property-media')) {
      return ResponseBody.fromBytes(_bytes, 200, headers: {
        'content-type': ['image/png'],
        'cache-control': ['public, max-age=86400'],
        'etag': ['"synthetic-one"']
      });
    }
    return ResponseBody.fromString(
        jsonEncode({
          'data': {'id': 7, 'title': 'native-cache-synthetic'}
        }),
        200,
        headers: {
          'content-type': ['application/json'],
          'x-aqer-filter-contract': ['2']
        });
  }

  @override
  void close({bool force = false}) {}
}

void _require(bool value, String name) {
  if (!value) {
    throw StateError(name);
  }
}

Future<void> _networkIs(bool connected) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    final state =
        await _network.invokeMapMethod<String, dynamic>('imageNetworkState');
    if (state?['networkAvailable'] == connected) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw StateError('native_connectivity_transition');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!_enabled ||
      _package != 'com.aqer.yemen.uat.offlineprobe' ||
      const String.fromEnvironment('APP_ENVIRONMENT') != 'uat') {
    throw StateError('isolated_native_context_required');
  }
  HttpOverrides.global = _NoHttp();
  runApp(const MaterialApp(
      home: Scaffold(
          body: Center(child: Text('SYNTHETIC OFFLINE NATIVE PROBE')))));
  try {
    await _run();
  } catch (error) {
    debugPrint('AQER_OFFLINE_NATIVE ${jsonEncode({
          'failed': true,
          'error_type': error.runtimeType.toString(),
          'code': error is StateError ? error.message.toString() : ''
        })}');
  }
}

Future<void> _run() async {
  final saved = await _store.read('smoke', 'checkpoint', private: true);
  final phase = ((saved?['phase'] as num?)?.toInt() ?? 0) + 1;
  _require(phase >= 1 && phase <= 3, 'phase_bounds');
  await _networkIs(phase != 2);
  final connection = OfflineConnectionController();
  if (phase == 2) {
    connection.offline();
  } else {
    connection.online();
  }
  final wire = _SyntheticWire(phase == 1);
  final dio = Dio(BaseOptions(baseUrl: '$_origin/api'))
    ..httpClientAdapter = wire;
  dio.interceptors.add(OfflineHttpInterceptor(_store, connection));
  const photo = '$_origin/api/property-media/1?variant=thumb&v=one';
  final disk = PublicPhotoDiskCache(origin: Uri.parse(_origin));
  final loader = PublicPhotoLoader(dio, disk, connection: connection);
  final recovery = ListingRecoveryStore();
  const paths = ['/properties/7', '/messages/threads', '/messages/threads/9'];
  final auth =
      Options(headers: {'Authorization': 'Bearer synthetic-native-only'});
  var actualSends = 0;
  final box = _ProbeOutbox(
      actor: _actor,
      store: _store,
      current: () => true,
      connected: () => phase == 3,
      resolveThread: (_, id) async => 777,
      sendMessage: (thread, body, id) async {
        actualSends++;
        final server =
            await _store.read('smoke', 'synthetic_server', private: true) ??
                {'acks': <String, dynamic>{}, 'attempts': 0};
        final acks = Map<String, dynamic>.from(server['acks'] as Map);
        final previous = acks[id];
        if (previous != null) {
          _require(previous == body, 'stable_client_id_body');
        }
        acks[id] = body;
        final attempts = (server['attempts'] as num).toInt() + 1;
        await _store.write(
            'smoke', 'synthetic_server', {'acks': acks, 'attempts': attempts},
            private: true);
        if (attempts == 1) {
          throw DioException(
              requestOptions: RequestOptions(path: '/messages'),
              type: DioExceptionType.connectionError);
        }
      });
  await box.initialize();
  final authRepository = AuthRepository(dio, offlineStore: _store);
  if (phase == 1) {
    await authRepository.verifyWhatsApp(
        const WhatsAppAuthPending(
            phone: '',
            email: 'synthetic@synthetic.invalid',
            isNewAccount: false),
        '000000');
    for (final path in paths) {
      await dio.get<dynamic>(path, options: auth);
    }
    await loader.load(photo, cancelToken: CancelToken());
    await disk.idle;
    final input = File(
        '${(await getApplicationSupportDirectory()).path}/synthetic-input.png');
    await input.writeAsBytes(_bytes, flush: true);
    await recovery.write(_actor, null, {
      'draft_key': 'fc0d4f08-f575-4ed5-aa57-75184a8ef648',
      'draft_kind': 'saved',
      'offline_prepared': true,
      'fields': {'title': 'native-draft-synthetic'}
    }, [
      input.path
    ]);
    await recovery.pinExplicitSave(_actor);
    await input.delete();
    await box.enqueue('property', 7, 'synthetic first');
    await box.enqueue('property', 7, 'synthetic second');
    _require(actualSends == 0 && box.rows.length == 2, 'durable_queue_no_send');
  } else if (phase == 2) {
    _require((await authRepository.restoreSession())?.id == _actor,
        'offline_session_after_first_login');
    for (final path in paths) {
      final response = await dio.get<dynamic>(path, options: auth);
      _require(
          response.extra['offline_snapshot'] == true &&
              response.data['data']['title'] == 'native-cache-synthetic',
          'offline_http_restart');
    }
    _require(
        (await loader.load(photo, cancelToken: CancelToken())).bytes.length ==
            _bytes.length,
        'offline_small_image_restart');
    var blocked = false;
    try {
      await loader.load(photo.replaceAll('variant=thumb', 'variant=gallery'),
          cancelToken: CancelToken());
    } on StateError {
      blocked = true;
    }
    _require(blocked, 'offline_large_image_blocked');
    final draft = await recovery.read(_actor, null);
    _require(
        (draft?['fields'] as Map?)?['title'] == 'native-draft-synthetic' &&
            draft?['offline_prepared'] == true,
        'manual_draft_restart');
    final copy = File((draft!['image_paths'] as List).single as String);
    _require(await copy.length() == _bytes.length, 'manual_photo_copy_restart');
    await box.flush();
    _require(box.rows.length == 2 && actualSends == 0,
        'offline_queue_no_send_restart');
    final other = _ProbeOutbox(
        actor: _actor + 1,
        store: _store,
        current: () => true,
        connected: () => false,
        resolveThread: (_, id) async => 888,
        sendMessage: (_, body, id) async {
          throw StateError('other_actor_send');
        });
    await other.initialize();
    _require(other.rows.isEmpty, 'actor_isolation');
    other.dispose();
    await maps.setOffline(true);
    final root = await getApplicationSupportDirectory();
    final httpDirectory =
        Directory('${root.parent.path}/no_backup/offline_v1/http_snapshots');
    await for (final entry in httpDirectory.list()) {
      if (entry is File && entry.path.endsWith('.json')) {
        final bytes = await entry.readAsString();
        _require(
            !bytes.contains('native-cache-synthetic') &&
                !bytes.contains('synthetic-native-only'),
            'native_encrypted_at_rest');
      }
    }
    _require(wire.calls == 0, 'zero_http_offline');
  } else {
    await maps.setOffline(false);
    _require(box.rows.length == 2, 'queued_messages_retained_until_reconnect');
    await box.flush();
    await box.flush();
    final server =
        await _store.read('smoke', 'synthetic_server', private: true);
    _require(
        (server?['acks'] as Map?)?.length == 2 &&
            server?['attempts'] == 3 &&
            actualSends == 3,
        'lost_ack_same_id_once');
    _require(box.rows.every((message) => message.status == 'sent'),
        'sent_only_after_ack');
    final encoded = await _secure.invokeMethod<String>(
        'sealOfflineState', {'value': 'synthetic-cipher-probe'});
    _require(
        await _secure
                .invokeMethod<String>('openOfflineState', {'value': encoded}) ==
            'synthetic-cipher-probe',
        'native_cipher_roundtrip');
    final changed = base64Decode(encoded!);
    changed[changed.length - 1] ^= 1;
    var rejected = false;
    try {
      await _secure.invokeMethod<String>(
          'openOfflineState', {'value': base64Encode(changed)});
    } on PlatformException {
      rejected = true;
    }
    _require(rejected, 'native_cipher_authentication');
  }
  await _store.write('smoke', 'checkpoint', {'phase': phase}, private: true);
  box.dispose();
  dio.close(force: true);
  connection.dispose();
  debugPrint('AQER_OFFLINE_NATIVE ${jsonEncode({
        'phase': phase,
        'passed': true,
        'http_calls': wire.calls,
        'synthetic_sends': actualSends
      })}');
}

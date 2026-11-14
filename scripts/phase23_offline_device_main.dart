// Copied into mobile_app/lib ONLY for isolated device acceptance.
// Product widgets and Android voice/location/media channels remain unchanged.
// Auth/status are local fixtures. All business/AI/auth API and Dart HTTP fail closed.
// Native public MapLibre style/device-provider connectivity is permitted.
// Emulator coordinates, virtual-camera frames and picker files are synthetic inputs.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:real_estate_mobile/core/network/api_client.dart';
import 'package:real_estate_mobile/core/platform/voice_capture_controller.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/core/widgets/inline_voice_capture.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/account/presentation/account_verification_screen.dart';
import 'package:real_estate_mobile/features/discovery/data/smart_search_session.dart';
import 'package:real_estate_mobile/features/discovery/presentation/assisted_search_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_location_picker_screen.dart';

const targetMarker = 'AQER_OFFLINE_DEVICE_TARGET_V1';
const _enabled = bool.fromEnvironment('AQER_OFFLINE_DEVICE_QA');
const typedBase = 'DEVICE_TYPED_BASE';
final _meta = <String, int>{
  'v': 1, 'case': 0, 'failures': 0, 'dioBlocked': 0, 'authBlocked': 0,
  'socketBlocked': 0, 'fixtureReads': 0, 'snapshotSeq': 0,
  'voicePhase': 0, 'voiceReadyCount': 0, 'voiceDictation': 0,
  'voicePermissionDenied': 0, 'voiceTranscriptChars': 0, 'voicePreviewChars': 0,
  'typedBaseKept': 0, 'searchStarted': 0,
  'mapReady': 0, 'gpsConfirmations': 0, 'gpsPhase': 0, 'gpsError': 0,
  'gpsMethod': 0, 'latE6': 0, 'lonE6': 0, 'accuracyCm': 0,
  'mediaSelected': 0, 'cameraFiles': 0, 'pickerFiles': 0,
  'mediaBytes': 0, 'mediaDecodable': 0,
};
final _revision = ValueNotifier<int>(0);
String _lastPublished = '';

void _publish({bool force = false}) {
  final payload = jsonEncode(_meta);
  if (!force && payload == _lastPublished) return;
  _lastPublished = payload;
  debugPrint('AQER_DEVICE $payload');
  scheduleMicrotask(() => _revision.value++);
}

void _failure() { _meta['failures'] = _meta['failures']! + 1; _publish(); }

class _NoDartNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    _meta['socketBlocked'] = _meta['socketBlocked']! + 1;
    _failure();
    throw const SocketException('DEVICE_TARGET_DART_NETWORK_FORBIDDEN');
  }
}

class _SyntheticAuth extends AuthController {
  _SyntheticAuth(this.media);
  final bool media;
  @override
  Future<AuthUser?> build() async => !media ? null : AuthUser.fromJson({
    'id': 90001, 'name': 'حساب اصطناعي لفحص الجهاز',
    'account_type': 'regular', 'account_status': 'active',
    'phone_verified_at': '2026-01-01T00:00:00Z',
    'profile_completed_at': '2026-01-01T00:00:00Z',
    'roles': <String>[], 'permissions': <String>[],
  });
}

class _NoCredentials implements AuthRepository {
  _NoCredentials(this.media);
  final bool media;
  @override
  Future<Options> requiredAuthOptions() async {
    if (!media) { _meta['authBlocked'] = _meta['authBlocked']! + 1; _failure(); throw StateError('NO_DEVICE_CREDENTIALS'); }
    return Options();
  }
  @override
  Future<Options?> optionalAuthOptions() async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    _meta['authBlocked'] = _meta['authBlocked']! + 1;
    _failure();
    throw StateError('DEVICE_TARGET_AUTH_FORBIDDEN');
  }
}

class _StatusOnlyAdapter implements HttpClientAdapter {
  _StatusOnlyAdapter(this.media);
  final bool media;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final allowed = media && options.uri.scheme == 'https' &&
      options.uri.host == 'synthetic.invalid' && !options.uri.hasPort &&
      options.method == 'GET' && options.path == '/account-verification' &&
      options.data == null && options.queryParameters.isEmpty &&
      !options.headers.keys.any((key) => key.toLowerCase() == 'authorization');
    if (!allowed) {
      _meta['dioBlocked'] = _meta['dioBlocked']! + 1;
      _publish();
      throw DioException(requestOptions: options, error: 'DEVICE_TARGET_API_FORBIDDEN');
    }
    _meta['fixtureReads'] = _meta['fixtureReads']! + 1;
    _publish();
    return ResponseBody.fromString(jsonEncode({'data': {
      'user_id': 90001, 'name': 'حساب اصطناعي لفحص الجهاز',
      'type': null, 'status': 'not_submitted', 'details': <String, Object>{},
      'documents': <Object>[], 'verification_flags': <String, bool>{},
    }}), 200, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }
  @override
  void close({bool force = false}) {}
}

class _DeviceScene {
  _DeviceScene(this.kind) {
    final media = kind == 3;
    dio = Dio(BaseOptions(baseUrl: 'https://synthetic.invalid'));
    dio.httpClientAdapter = _StatusOnlyAdapter(media);
    container = ProviderContainer(overrides: [
      authControllerProvider.overrideWith(() => _SyntheticAuth(media)),
      authRepositoryProvider.overrideWithValue(_NoCredentials(media)),
      dioProvider.overrideWithValue(dio),
    ]);
  }
  final int kind;
  final bodyKey = GlobalKey();
  late final Dio dio;
  late final ProviderContainer container;
  Future<void> prepare() async { await container.read(authControllerProvider.future); }
  Widget get screen => switch (kind) {
    1 => const AssistedSearchScreen(),
    2 => const PropertyLocationPickerScreen(reverseLookup: null),
    3 => const AccountVerificationScreen(initialType: 'owner'),
    _ => throw StateError('UNDECLARED_DEVICE_CASE'),
  };
  void dispose() { container.dispose(); dio.close(force: true); }
}

Future<void> main() async {
  if (!_enabled) throw StateError('EXPLICIT_DEVICE_TARGET_FLAG_REQUIRED');
  HttpOverrides.global = _NoDartNetwork();
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (_) => _failure();
  ui.PlatformDispatcher.instance.onError = (_, __) { _failure(); return true; };
  runApp(const _DeviceApp());
}

class _DeviceApp extends StatefulWidget {
  const _DeviceApp();
  @override
  State<_DeviceApp> createState() => _DeviceAppState();
}

class _DeviceAppState extends State<_DeviceApp> {
  final _navigator = GlobalKey<NavigatorState>();
  _DeviceScene? _scene;
  VoiceCaptureController? _observedCapture;
  Timer? _poll;
  bool _opening = false, _scanning = false;
  int _previousVoicePhase = 0;
  final _decodedFiles = <String, bool>{};

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(milliseconds: 250), (_) => _observeWidgets());
    WidgetsBinding.instance.addPostFrameCallback((_) => _publish(force: true));
  }

  Future<void> _open(int kind) async {
    if (_opening || _scene != null || !const [1, 2, 3].contains(kind)) return;
    _opening = true;
    final scene = _DeviceScene(kind);
    try {
      await scene.prepare();
      if (!mounted) return;
      _scene = scene;
      _meta['case'] = kind;
      _observedCapture = null;
      _previousVoicePhase = 0;
      _publish(force: true);
      final result = await _navigator.currentState!.push<Object?>(MaterialPageRoute<Object?>(
        builder: (_) => UncontrolledProviderScope(container: scene.container,
          child: KeyedSubtree(key: scene.bodyKey, child: scene.screen)),
      ));
      // Only the actual product picker can produce this returned result.
      if (kind == 2 && result is PropertyLocationSelection) {
        _meta['gpsConfirmations'] = _meta['gpsConfirmations']! + 1;
        _meta['gpsPhase'] = 2;
        _meta['gpsError'] = 0;
        _meta['gpsMethod'] = result.method == 'gps' ? 1 : 0;
        _meta['latE6'] = (result.latitude * 1000000).round();
        _meta['lonE6'] = (result.longitude * 1000000).round();
        final accuracy = result.accuracyMetres;
        _meta['accuracyCm'] = accuracy != null && accuracy.isFinite && accuracy > 0
          ? (accuracy * 100).round().clamp(0, 100000000).toInt() : 0;
      }
    } catch (_) { _failure(); }
    finally {
      _observedCapture = null;
      _scene = null;
      _opening = false;
      _meta['case'] = 0;
      _meta['mapReady'] = 0;
      _meta['voicePhase'] = 0;
      // Let the popped product route finish disposal before closing its scope.
      await Future<void>.delayed(const Duration(milliseconds: 450));
      scene.dispose();
      if (mounted) { setState(() {}); await _snapshot(); }
    }
  }

  void _home() {
    if (_scene == null) return;
    _navigator.currentState?.popUntil((route) => route.isFirst);
  }

  void _observeWidgets() {
    final scene = _scene;
    if (scene == null) return;
    var selected = 0, mapReady = 0, locationError = 0;
    void visit(Element element) {
      final widget = element.widget;
      if (widget is InlineVoiceCapture) _observedCapture = widget.capture;
      if (scene.kind == 1 && widget is TextField &&
          widget.key == const ValueKey('smart-search-description')) {
        _meta['typedBaseKept'] = widget.controller?.text == typedBase ? 1 : 0;
      }
      if (widget is FloatingActionButton && widget.tooltip == 'موقعي الحالي') {
        mapReady = widget.onPressed != null ? 1 : 0;
      }
      if (widget is Text) {
        final text = widget.data ?? '';
        if (text == 'تم اختيار ملف جديد') selected++;
        if (text.contains('لم يُمنح إذن الموقع.')) locationError = 1;
        if (text.contains('إذن الموقع مرفوض نهائيًا.')) locationError = 2;
        if (text.contains('فعّل خدمة الموقع أو حدد النقطة')) locationError = 3;
        if (text == 'تعذر الحصول على موقع الهاتف الآن.') locationError = 4;
      }
      element.visitChildElements(visit);
    }
    scene.bodyKey.currentContext?.visitChildElements(visit);
    if (scene.kind == 1) {
      final capture = _observedCapture;
      if (capture != null) {
        final phase = capture.phase.index;
        if (phase == VoicePhase.listening.index && _previousVoicePhase != phase) {
          _meta['voiceReadyCount'] = _meta['voiceReadyCount']! + 1;
        }
        _previousVoicePhase = phase;
        _meta['voicePhase'] = phase;
        _meta['voiceDictation'] = capture.liveDictation ? 1 : 0;
        _meta['voicePermissionDenied'] = capture.permissionDenied ? 1 : 0;
        _meta['voiceTranscriptChars'] = capture.transcript.length;
        _meta['voicePreviewChars'] = capture.preview.length;
      }
      _meta['searchStarted'] = scene.container.read(smartSearchSessionProvider).started ? 1 : 0;
    }
    if (scene.kind == 2) {
      _meta['mapReady'] = mapReady;
      _meta['gpsError'] = locationError;
      _meta['gpsPhase'] = locationError == 0 ? 0 : 3;
    }
    if (scene.kind == 3) _meta['mediaSelected'] = selected;
    _publish();
  }

  Future<void> _snapshot() async {
    _observeWidgets();
    if (_scanning) return;
    _scanning = true;
    try {
      // Read only the product's temporary media folder, never arbitrary files.
      final temporary = await getTemporaryDirectory();
      final media = Directory('${temporary.path}/stage5_uploads');
      var cameras = 0, picks = 0, bytes = 0, decoded = 0;
      if (await media.exists()) {
        var count = 0;
        await for (final entry in media.list(followLinks: false)) {
          if (entry is! File) continue;
          final name = entry.uri.pathSegments.last;
          if (!RegExp(r'^(selfie_[0-9]+\.jpg|stage5_[0-9]+_[0-9]+\.(png|jpg|webp|heic|heif|avif|gif|bin))$').hasMatch(name)) continue;
          if (++count > 4) { _failure(); break; }
          final size = await entry.length();
          if (size <= 0) continue;
          if (size > 8 * 1024 * 1024) { _failure(); continue; }
          if (name.startsWith('selfie_')) { cameras++; } else { picks++; }
          bytes += size;
          final identity = '$name:$size';
          if (!_decodedFiles.containsKey(identity)) {
            try {
              final codec = await ui.instantiateImageCodec(await entry.readAsBytes(), targetWidth: 64);
              final frame = await codec.getNextFrame();
              _decodedFiles[identity] = frame.image.width > 0 && frame.image.height > 0;
              frame.image.dispose(); codec.dispose();
            } catch (_) { _decodedFiles[identity] = false; }
          }
          if (_decodedFiles[identity] == true) decoded++;
        }
      }
      _meta['cameraFiles'] = cameras; _meta['pickerFiles'] = picks;
      _meta['mediaBytes'] = bytes; _meta['mediaDecodable'] = decoded;
    } catch (_) { _failure(); }
    finally {
      _scanning = false;
      _meta['snapshotSeq'] = _meta['snapshotSeq']! + 1;
      _publish(force: true);
    }
  }

  Widget _control(String label, VoidCallback action) => Semantics(
    label: label, button: true, excludeSemantics: true, onTap: action,
    child: TextButton(onPressed: action, style: TextButton.styleFrom(
      minimumSize: const Size(40, 30), padding: const EdgeInsets.symmetric(horizontal: 6),
      foregroundColor: Colors.white), child: Text(label.replaceFirst('DEVICE_', ''),
        style: const TextStyle(fontSize: 10))),
  );

  @override
  void dispose() { _poll?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: _navigator, debugShowCheckedModeBanner: false,
    theme: AppTheme.light, locale: const Locale('ar'),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: const [GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
    builder: (context, child) => Directionality(textDirection: TextDirection.rtl,
      child: Column(children: [
        SafeArea(bottom: false, child: Material(color: const Color(0xff112233),
          child: MediaQuery.withNoTextScaling(child: Directionality(textDirection: TextDirection.ltr,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text(targetMarker, style: TextStyle(fontSize: 9, color: Colors.white)),
                const Text('SYNTHETIC DEVICE SESSION · Native map/device network · API denied',
                  style: TextStyle(fontSize: 9, color: Colors.white)),
                Row(children: [
                  _control('DEVICE_VOICE', () => unawaited(_open(1))),
                  _control('DEVICE_LOCATION', () => unawaited(_open(2))),
                  _control('DEVICE_MEDIA', () => unawaited(_open(3))),
                  _control('DEVICE_HOME', _home),
                  _control('DEVICE_SNAPSHOT', () => unawaited(_snapshot())),
                ]),
                ValueListenableBuilder<int>(valueListenable: _revision, builder: (_, __, ___) =>
                  Semantics(label: 'DEVICE_META ${jsonEncode(_meta)}', excludeSemantics: true,
                    child: Text('Case ${_meta['case']} · failures ${_meta['failures']} · synthetic sensor input',
                      style: const TextStyle(fontSize: 9, color: Colors.white)))),
              ])))))),
        // Route modal barriers block preceding nodes within their semantic
        // container. Keep their scope below the persistent synthetic controls.
        Expanded(child: Semantics(container: true, explicitChildNodes: true, child: child!)),
      ])),
    home: const Scaffold(body: Center(child: Padding(padding: EdgeInsets.all(24), child: Text(
      'هدف منفصل لفحص أذونات Android ومسارات الجهاز الأصلية.\n'
      'لا حساب حي ولا إرسال بيانات. الموقع والصور مدخلات محاكي اصطناعية.\n'
      'لا تُستبدل نتيجة الصوت أو الموقع أو الكاميرا. اختر الفحص من الشريط.',
      textAlign: TextAlign.center)))),
  );
}

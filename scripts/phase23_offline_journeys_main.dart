// Isolated native QA entry point. Copy to lib/ only in the marked CI job.
// Real router, widgets, account scope and history file; synthetic GET/auth only.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show PlatformDispatcher;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:real_estate_mobile/core/network/api_client.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_repository.dart';
import 'package:real_estate_mobile/features/properties/data/recent_properties_store.dart';
import 'package:real_estate_mobile/router/app_router.dart';

const targetMarker = 'AQER_OFFLINE_JOURNEYS_TARGET_V1';
const _enabled = bool.fromEnvironment('AQER_OFFLINE_JOURNEYS_QA');
final _failures = ValueNotifier<int>(0);
int _failureCount = 0;
void _event(Map<String, Object?> value) => debugPrint('AQER_JOURNEY ${jsonEncode(value)}');
void _failure(String code) {
  _failureCount++;
  _event({'event': 'failure', 'code': code, 'failures': _failureCount});
  scheduleMicrotask(() => _failures.value = _failureCount);
}

class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    _failure('socket_forbidden');
    throw const SocketException('OFFLINE_JOURNEY_NETWORK_FORBIDDEN');
  }
}

const _scopes = <String>['A', 'A', 'A', 'A', 'A', 'A', 'B', 'guest', 'A',
  'verified', 'verified', 'pending', 'pending', 'A', 'A', 'A'];
int? _actor(String scope) => switch (scope) {
  'A' => 90001, 'B' => 90002, 'verified' => 90003, 'pending' => 90004,
  'guest' => null, _ => throw StateError('UNDECLARED_SYNTHETIC_SCOPE'),
};
String _role(String scope) => scope == 'guest' ? 'guest'
  : scope == 'verified' || scope == 'pending' ? 'broker' : 'regular';

AuthUser? _identity(String scope) {
  if (scope == 'guest') return null;
  final broker = _role(scope) == 'broker';
  return AuthUser.fromJson({
    'id': _actor(scope), 'name': 'حساب اصطناعي للاختبار $scope',
    'email': 'synthetic@example.invalid', 'account_type': broker ? 'broker' : 'regular',
    'account_status': 'active', 'phone_verified_at': '2026-01-01T00:00:00Z',
    'profile_completed_at': '2026-01-01T00:00:00Z',
    'roles': <String>[], 'permissions': <String>[],
    if (broker) 'verification_profile': {
      'type': 'broker', 'status': scope == 'verified' ? 'approved' : 'pending',
      if (scope == 'verified') 'reviewed_at': '2026-01-01T00:00:00Z',
    },
  });
}

class _SyntheticAuth extends AuthController {
  @override
  Future<AuthUser?> build() async => _identity('A');
  void selectSyntheticScope(String scope) { state = AsyncData(_identity(scope)); }
}

class _NoCredentials implements AuthRepository {
  @override
  Future<Options> requiredAuthOptions() async => Options();
  @override
  Future<Options> optionalAuthOptions() async => Options();
  @override
  dynamic noSuchMethod(Invocation invocation) {
    _failure('auth_operation_forbidden');
    throw StateError('OFFLINE_JOURNEY_AUTH_FORBIDDEN');
  }
}

class _MemoryAdapter implements HttpClientAdapter {
  int requests = 0, workspaceRequests = 0, threadRequests = 0;
  static const paths = <String>{'/marketplace', '/favorites', '/favorites/ids', '/broker/workspace',
    '/messages/threads/9010',
    '/properties/9001', '/properties/9002',
    '/properties/9001/sai', '/properties/9002/sai',
    '/properties/9001/market-context', '/properties/9002/market-context'};
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    if (options.uri.scheme != 'https' || options.uri.host != 'synthetic.invalid' ||
        options.uri.hasPort || options.method != 'GET' || !paths.contains(options.path) ||
        options.data != null ||
        options.headers.keys.any((key) => key.toLowerCase() == 'authorization')) {
      _failure('unapproved_request');
      throw DioException(requestOptions: options, error: 'OFFLINE_JOURNEY_REQUEST_FORBIDDEN');
    }
    requests++;
    final path = options.path;
    if (path == '/favorites') {
      return ResponseBody.fromString(jsonEncode({'data': <Object>[],
        'meta': {'current_page': 1, 'last_page': 1, 'total': 0}}), 200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
    }
    Map<String, dynamic> data;
    if (path == '/marketplace') {
      data = {'context': {'label': 'منطقة اصطناعية للاختبار', 'source': 'default'},
        'sections': <String, Object>{}, 'brokers': <Object>[]};
    } else if (path == '/favorites/ids') {
      data = {'property_ids': <int>[]};
    } else if (path == '/broker/workspace') {
      workspaceRequests++;
      data = {'listings': <String, Object>{}, 'customer_activity': <String, Object>{},
        'needs_attention': <String, Object>{}, 'financial_summary': <String, Object>{}};
    } else if (path == '/messages/threads/9010') {
      threadRequests++;
      data = {'thread': {'id': 9010,
        'other_user': {'id': 90099, 'name': 'محادثة اصطناعية للاختبار'},
        'unread_count': 0, 'can_send': false, 'can_call_advertiser': false,
        'can_manage_customer': false},
        'messages': [{'id': 901001, 'sender_user_id': 90099,
          'sender_name': 'مستخدم اصطناعي', 'is_mine': false,
          'body': 'رسالة اصطناعية عبر رابط أندرويد'}],
        'pagination': {'has_more': false}};
    } else if (path.endsWith('/sai')) {
      data = <String, dynamic>{};
    } else if (path.endsWith('/market-context')) {
      data = {'sufficient_data': false, 'sample_count': 0,
        'message': 'مؤشر اصطناعي للاختبار فقط.'};
    } else {
      final id = int.parse(path.split('/').last);
      // Owned published properties exercise real local history recording while
      // the actual details widget correctly skips its remote recordView POST.
      // No coordinates/images: neither a map nor remote media is initialized.
      data = {'id': id, 'title': 'عقار اصطناعي للاختبار $id',
        'description': 'هذا عقار اصطناعي للاختبار المحلي فقط.',
        'status': 'published', 'review_status': 'approved', 'is_owner': true,
        'price': 100000, 'currency': 'YER', 'purpose': 'sale', 'type': 'house',
        'images': <Object>[], 'similar': <Object>[]};
    }
    return ResponseBody.fromString(jsonEncode({'data': data}), 200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType],
        'x-aqer-filter-contract': ['2']});
  }
  @override
  void close({bool force = false}) {}
}

class _Journey {
  _Journey(this.directory, this.control, this.stage, this.restartCount) {
    dio.httpClientAdapter = adapter;
    container = ProviderContainer(overrides: [
      authControllerProvider.overrideWith(_SyntheticAuth.new),
      authRepositoryProvider.overrideWithValue(_NoCredentials()),
      dioProvider.overrideWithValue(dio),
      homeLocationAttemptedProvider.overrideWith((ref) => true),
      homeLocationProvider.overrideWith((ref) => const HomeLocation(
        label: 'منطقة اصطناعية للاختبار', manual: true)),
    ]);
  }
  final Directory directory;
  final File control;
  int stage;
  final int restartCount;
  final adapter = _MemoryAdapter();
  final dio = Dio(BaseOptions(baseUrl: 'https://synthetic.invalid'));
  late final ProviderContainer container;
  late final GoRouter router;
  String get scope => _scopes[stage];

  Future<void> prepare() async {
    await container.read(authControllerProvider.future);
    router = container.read(appRouterProvider);
    router.go('/recent');
  }

  Future<Map<String, Object?>> proof() async {
    // Read the product's actual store, then inspect that same scoped real file.
    // The target never calls record(), clear(), or overrides the history store.
    final rows = await container.read(recentPropertiesStoreProvider).load();
    final actor = _actor(scope);
    final filename = actor == null ? 'guest' : 'user_$actor';
    final history = File('${directory.path}/aqer_recent_properties_$filename.json');
    final exists = await history.exists();
    return {'event': 'ready', 'stage': stage, 'role': _role(scope), 'scope': scope,
      'recent_ids': rows.map((row) => row.id).toList(growable: false),
      'file_exists': exists, 'file_bytes': exists ? await history.length() : 0,
      'restart_count': restartCount, 'requests': adapter.requests, 'failures': _failureCount};
  }

  void dispose() { router.dispose(); container.dispose(); dio.close(force: true); }
}

Future<void> main() async {
  if (!_enabled) throw StateError('EXPLICIT_OFFLINE_JOURNEYS_FLAG_REQUIRED');
  HttpOverrides.global = _NoNetwork();
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (_) => _failure('flutter_error');
  PlatformDispatcher.instance.onError = (_, __) { _failure('unhandled_error'); return true; };
  final directory = await getApplicationSupportDirectory();
  final control = File('${directory.path}/aqer_synthetic_journey_control.json');
  var stage = 0, restarts = 0;
  if (await control.exists()) {
    final raw = jsonDecode(await control.readAsString());
    if (raw is! Map || raw['stage'] != 4 || raw['restart_count'] != 0) {
      _failure('unexpected_restart_state');
      throw StateError('OFFLINE_JOURNEY_RESTART_STATE');
    }
    stage = 5;
    restarts = 1;
    // Only harness progress is written here. Existing product history is untouched.
    await control.writeAsString(jsonEncode({'stage': 5, 'restart_count': 1}), flush: true);
  }
  final journey = _Journey(directory, control, stage, restarts);
  await journey.prepare();
  runApp(_OfflineJourneysApp(journey: journey));
}

class _OfflineJourneysApp extends StatefulWidget {
  const _OfflineJourneysApp({required this.journey});
  final _Journey journey;
  @override
  State<_OfflineJourneysApp> createState() => _OfflineJourneysAppState();
}

class _OfflineJourneysAppState extends State<_OfflineJourneysApp> {
  _Journey get journey => widget.journey;
  final _bodyKey = GlobalKey();
  bool _busy = true;
  Timer? _readyTimer;
  @override
  void initState() {
    super.initState();
    journey.router.routeInformationProvider.addListener(_observeNativeRoute);
    _markReady();
  }

  void _observeNativeRoute() {
    // The collector sends Android ACTION_VIEW. Flutter's ordinary embedding
    // and the unmodified app router dispatch it. This target never navigates
    // to the thread itself; it only observes the resulting route and pixels.
    if (!mounted || journey.stage != 13 ||
        journey.router.routeInformationProvider.value.uri.path != '/messages/9010') return;
    setState(() { journey.stage = 14; _busy = true; });
    _readyTimer?.cancel();
    _markReady();
  }

  void _markReady() {
    final stage = journey.stage;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _readyTimer = Timer(const Duration(milliseconds: 900), () async {
        if (!mounted || journey.stage != stage) return;
        try {
          if (stage == 14 && (journey.adapter.threadRequests == 0 ||
              !_hasActualText('محادثة اصطناعية للاختبار'))) {
            _failure('native_thread_not_loaded');
            return;
          }
          final proof = await journey.proof();
          if (!mounted || journey.stage != stage) return;
          setState(() => _busy = false);
          await WidgetsBinding.instance.endOfFrame;
          if (!mounted || journey.stage != stage) return;
          _event(proof);
        } catch (_) { _failure('history_read_failed'); }
      });
    });
  }

  bool _hasActualText(String text) {
    var found = false;
    void visit(Element element) {
      final widget = element.widget;
      if (widget is Text && widget.data == text) found = true;
      element.visitChildElements(visit);
    }
    _bodyKey.currentContext?.visitChildElements(visit);
    return found;
  }

  Future<void> _next() async {
    if (_busy || journey.stage == 4 || journey.stage == 13 ||
        journey.stage == 15 || _failureCount != 0) return;
    // These stages may advance only after the collector taps the real AppShell tab.
    if (journey.stage == 9 && (journey.adapter.workspaceRequests == 0 ||
        !_hasActualText('لوحة الدلال'))) { _failure('natural_workspace_tap_missing'); return; }
    if (journey.stage == 11 && !_hasActualText('أدوات الدلال بعد اعتماد التوثيق')) {
      _failure('natural_gate_tap_missing'); return;
    }
    setState(() => _busy = true);
    _readyTimer?.cancel();
    final next = journey.stage + 1;
    final nextScope = _scopes[next];
    final oldScope = journey.scope;
    journey.stage = next;
    if (oldScope != nextScope) {
      (journey.container.read(authControllerProvider.notifier) as _SyntheticAuth)
        .selectSyntheticScope(nextScope);
    }
    if (next == 1 || next == 3) {
      journey.router.go('/properties/9001');
    } else if (next == 2) {
      journey.router.go('/properties/9002');
    } else if (next >= 4 && next <= 8) {
      journey.router.go('/recent');
    } else if (next == 9 || next == 11 || next == 13) {
      journey.router.go('/');
    } else if (next == 15) {
      journey.router.go('/favorites');
    }
    // At 10 and 12 keep the naturally selected real AppShell tab in place.
    if (next == 4) {
      await journey.control.parent.create(recursive: true);
      await journey.control.writeAsString(jsonEncode({'stage': 4, 'restart_count': 0}), flush: true);
    }
    if (!mounted) return;
    setState(() {});
    _markReady();
  }

  ScrollPosition? _verticalPosition(bool forward) {
    ScrollPosition? position;
    void visit(Element element) {
      if (position != null) return;
      if (element is StatefulElement && element.state is ScrollableState) {
        final candidate = (element.state as ScrollableState).position;
        if ((candidate.axisDirection == AxisDirection.down ||
             candidate.axisDirection == AxisDirection.up) &&
            candidate.hasContentDimensions && candidate.maxScrollExtent > 0 &&
            (forward ? candidate.pixels < candidate.maxScrollExtent - .5
              : candidate.pixels > candidate.minScrollExtent + .5)) {
          position = candidate;
          return;
        }
      }
      element.visitChildElements(visit);
    }
    _bodyKey.currentContext?.visitChildElements(visit);
    return position;
  }

  void _scrollBy(double delta) {
    if (_busy || journey.stage != 15 || _failureCount != 0) return;
    final position = _verticalPosition(delta > 0);
    if (position == null) return;
    position.jumpTo((position.pixels + delta)
      .clamp(position.minScrollExtent, position.maxScrollExtent).toDouble());
  }

  void _scrollPage(bool forward) {
    final position = _verticalPosition(forward);
    if (position != null) _scrollBy(position.viewportDimension * (forward ? .65 : -.65));
  }

  @override
  void dispose() {
    _readyTimer?.cancel();
    journey.router.routeInformationProvider.removeListener(_observeNativeRoute);
    journey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final marker = 'AQER_JOURNEY_STAGE_${journey.stage.toString().padLeft(2, '0')}';
    final canAdvance = !_busy && journey.stage != 4 && journey.stage != 13 &&
      journey.stage != 15 && _failureCount == 0;
    return UncontrolledProviderScope(container: journey.container,
      child: MaterialApp.router(debugShowCheckedModeBanner: false,
        routerConfig: journey.router, theme: journey.stage == 15 ? AppTheme.dark : AppTheme.light,
        locale: const Locale('ar'), supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1)),
          child: Directionality(textDirection: TextDirection.rtl,
          child: Scaffold(body: SafeArea(child: Column(children: [
            MediaQuery.withNoTextScaling(child: Directionality(textDirection: TextDirection.ltr,
              child: ColoredBox(color: const Color(0xff112233), child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(targetMarker, style: TextStyle(fontSize: 9, color: Colors.white)),
                    const Text('SYNTHETIC OFFLINE', style: TextStyle(fontSize: 10, color: Colors.white)),
                    Text(marker, style: const TextStyle(fontSize: 11, color: Colors.white)),
                    ValueListenableBuilder<int>(valueListenable: _failures, builder: (_, count, __) =>
                      Text(count == 0 ? '${_role(journey.scope)}/${journey.scope}' : 'AQER_JOURNEY_FAILURE',
                        style: const TextStyle(fontSize: 10, color: Colors.white))),
                  ])),
                  Semantics(label: 'AQER_JOURNEY_NEXT', button: true, enabled: canAdvance,
                    excludeSemantics: true, onTap: canAdvance ? _next : null,
                    child: TextButton(onPressed: canAdvance ? _next : null,
                      child: const Text('Next', style: TextStyle(color: Colors.white)))),
                ]))))),
            Expanded(child: Semantics(container: true, explicitChildNodes: true,
              label: journey.stage == 15 ? 'AQER_JOURNEY_SCROLL' : null,
              onScrollDown: journey.stage == 15 ? () => _scrollPage(true) : null,
              onScrollUp: journey.stage == 15 ? () => _scrollPage(false) : null,
              child: GestureDetector(behavior: HitTestBehavior.opaque, excludeFromSemantics: true,
                onVerticalDragUpdate: journey.stage == 15
                  ? (details) => _scrollBy(-details.delta.dy) : null,
                child: AbsorbPointer(absorbing: journey.stage == 15,
                  child: KeyedSubtree(key: _bodyKey, child: child!))))),
          ])))))));
  }
}

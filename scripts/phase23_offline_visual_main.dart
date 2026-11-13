// Copied to mobile_app/lib ONLY in the isolated visual CI job.
// Native layout evidence with synthetic in-memory fixtures; never live access evidence.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show PlatformDispatcher;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:real_estate_mobile/core/network/api_client.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/broker/data/customer_help_store.dart';
import 'package:real_estate_mobile/features/broker/presentation/broker_workspaces.dart';
import 'package:real_estate_mobile/features/messages/presentation/conversation_reports_screen.dart';
import 'package:real_estate_mobile/features/messages/presentation/messages_screen.dart';
import 'package:real_estate_mobile/features/messages/presentation/notifications_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/favorites_screen.dart';
import 'package:real_estate_mobile/features/support/presentation/support_admin_screen.dart';

const targetMarker = 'AQER_OFFLINE_VISUAL_TARGET_V1';
const _enabled = bool.fromEnvironment('AQER_OFFLINE_VISUAL_QA');
final _failures = ValueNotifier<int>(0);
int _failureCount = 0;

void _event(Map<String, Object?> value) => debugPrint('AQER_VISUAL ${jsonEncode(value)}');
void _failure(String code) {
  _failureCount++;
  _event({'event': 'failure', 'code': code, 'failures': _failureCount});
  // A framework error can occur during build; update the banner after that stack.
  scheduleMicrotask(() => _failures.value = _failureCount);
}

class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    _failure('socket_forbidden');
    throw const SocketException('OFFLINE_VISUAL_NETWORK_FORBIDDEN');
  }
}

class _VisualCase {
  const _VisualCase(this.surface, this.role, this.state, this.dark, this.scale);
  final String surface, role, state;
  final bool dark;
  final double scale;
  Widget get screen => switch (surface) {
    'favorites' => const FavoritesScreen(),
    'availability' => const BrokerAvailabilityScreen(),
    'customers' => const BrokerCustomersScreen(),
    'messages' => const MessagesScreen(),
    'support' => const SupportAdminScreen(),
    'notifications' => const NotificationsScreen(),
    'reports' => const ConversationReportsScreen(),
    _ => throw StateError('UNDECLARED_VISUAL_SCREEN'),
  };
  Set<String> get paths => switch (surface) {
    'favorites' => {'/favorites'},
    'availability' => {'/broker/listings/availability'},
    'customers' => {'/broker/customers'},
    'messages' => {'/messages/threads'},
    'support' => {'/admin/support/summary', '/admin/support/cases'},
    'notifications' => {'/notifications'},
    'reports' => {'/admin/messages/reports'},
    _ => <String>{},
  };
}

const _cases = <_VisualCase>[
  _VisualCase('favorites', 'regular', 'populated', false, 1),
  _VisualCase('favorites', 'regular', 'empty', true, 1),
  _VisualCase('favorites', 'regular', 'error', false, 1),
  _VisualCase('favorites', 'regular', 'loading', true, 1),
  _VisualCase('availability', 'broker', 'populated', true, 2.4),
  _VisualCase('customers', 'broker', 'populated', false, 2.4),
  _VisualCase('messages', 'regular', 'populated', true, 1),
  _VisualCase('messages', 'regular', 'empty', false, 2.4),
  _VisualCase('support', 'support', 'populated', true, 1),
  _VisualCase('support', 'support', 'empty', false, 1),
  _VisualCase('support', 'support', 'error', true, 2.4),
  _VisualCase('support', 'support', 'loading', false, 1),
  _VisualCase('notifications', 'regular', 'populated', true, 2.4),
  _VisualCase('reports', 'support', 'populated', false, 2.4),
];

class _SyntheticAuth extends AuthController {
  _SyntheticAuth(this.role);
  final String role;
  @override
  Future<AuthUser?> build() async => AuthUser.fromJson({
    'id': role == 'broker' ? 90002 : role == 'support' ? 90003 : 90001,
    'name': 'حساب اصطناعي للاختبار',
    'email': 'synthetic@example.invalid',
    'account_type': role == 'broker' ? 'broker' : 'regular',
    'account_status': 'active',
    'phone_verified_at': '2026-01-01T00:00:00Z',
    'profile_completed_at': '2026-01-01T00:00:00Z',
    'roles': role == 'support' ? ['support_agent'] : <String>[],
    'permissions': role == 'support'
      ? ['support.handle_reports', 'conversations.review_private'] : <String>[],
    if (role == 'broker') 'verification_profile': {
      'type': 'broker', 'status': 'approved',
      'reviewed_at': '2026-01-01T00:00:00Z',
    },
  });
}

class _NoCredentials implements AuthRepository {
  @override
  Future<Options> requiredAuthOptions() async => Options();
  @override
  dynamic noSuchMethod(Invocation invocation) {
    _failure('auth_operation_forbidden');
    throw StateError('OFFLINE_VISUAL_AUTH_FORBIDDEN');
  }
}

class _MemoryHelp implements CustomerHelpStore {
  @override
  Future<bool> seen(int accountId) async => true;
  @override
  Future<void> markSeen(int accountId) async {}
}

class _MemoryAdapter implements HttpClientAdapter {
  _MemoryAdapter(this.visualCase);
  final _VisualCase visualCase;
  int requests = 0;
  final List<Completer<ResponseBody>> _pending = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (options.uri.scheme != 'https' || options.uri.host != 'synthetic.invalid' ||
        options.uri.hasPort || options.method != 'GET' ||
        !visualCase.paths.contains(options.path) || options.data != null ||
        options.headers.keys.any((key) => key.toLowerCase() == 'authorization')) {
      _failure('unapproved_request');
      throw DioException(requestOptions: options, error: 'OFFLINE_VISUAL_REQUEST_FORBIDDEN');
    }
    requests++;
    if (visualCase.state == 'loading') {
      final pending = Completer<ResponseBody>();
      _pending.add(pending);
      return pending.future;
    }
    if (visualCase.state == 'error') {
      return _json({'message': 'خطأ اصطناعي للاختبار فقط'}, 503);
    }
    if (options.path == '/admin/support/summary') {
      final count = visualCase.state == 'empty' ? 0 : 2;
      return _json({'data': {'new_tickets': count, 'open': count,
        'assigned_to_me': count, 'team': <Object>[]}});
    }
    final rows = visualCase.state == 'empty' ? <Map<String, dynamic>>[]
      : List.generate(2, (index) => _row(index + 1));
    return _json({'data': rows, 'meta': {
      'current_page': 1, 'last_page': 1, 'total': rows.length,
    }});
  }

  Map<String, dynamic> _row(int id) => switch (visualCase.surface) {
    'favorites' => {'property': {'id': id, 'title': 'عقار اصطناعي للاختبار $id',
      'price': 100000, 'currency': 'YER', 'purpose': 'sale', 'type': 'house',
      'latitude': 15.3, 'longitude': 44.2}},
    'availability' => {'id': id, 'title': 'إعلان اصطناعي للاختبار $id',
      'purpose': 'sale', 'availability_status': 'available', 'needs_confirmation': id == 2},
    'customers' => {'thread_id': id, 'customer_name': 'عميل اصطناعي $id',
      'property_id': id, 'property_title': 'عقار اصطناعي للاختبار $id', 'stage': 'new'},
    'support' => {'id': id, 'reference': 'SYNTHETIC-$id', 'kind': 'support_ticket',
      'subject': 'طلب دعم اصطناعي للاختبار $id', 'status': 'open',
      'priority': 'normal', 'escalation_level': 0},
    _ => {'id': id, 'other_user': {'id': id + 1000, 'name': 'مستخدم اصطناعي $id'},
      'unread_count': 1, 'thread_id': id, 'reporter_name': 'مبلّغ اصطناعي',
      'reason_code': 'other', 'status': 'open', 'property_title': 'عقار اصطناعي $id',
      'title': 'إشعار اصطناعي للاختبار $id', 'body': 'هذا محتوى اصطناعي للاختبار فقط.',
      'type': 'synthetic_notice', 'read_at': null},
  };

  ResponseBody _json(Map<String, dynamic> value, [int status = 200]) =>
    ResponseBody.fromString(jsonEncode(value), status,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});

  @override
  void close({bool force = false}) {
    for (final pending in _pending) {
      if (!pending.isCompleted) pending.complete(_json({'message': 'closed'}, 503));
    }
    _pending.clear();
  }
}

class _Scene {
  _Scene(this.index) {
    adapter = _MemoryAdapter(_cases[index]);
    dio = Dio(BaseOptions(baseUrl: 'https://synthetic.invalid'));
    dio.httpClientAdapter = adapter;
    container = ProviderContainer(overrides: [
      authControllerProvider.overrideWith(() => _SyntheticAuth(_cases[index].role)),
      authRepositoryProvider.overrideWithValue(_NoCredentials()),
      dioProvider.overrideWithValue(dio),
      customerHelpStoreProvider.overrideWithValue(_MemoryHelp()),
    ]);
  }
  final int index;
  final bodyKey = GlobalKey();
  late final _MemoryAdapter adapter;
  late final Dio dio;
  late final ProviderContainer container;
  Future<void> prepare() async { await container.read(authControllerProvider.future); }
  void dispose() { container.dispose(); dio.close(force: true); }
}

Future<void> main() async {
  if (!_enabled) throw StateError('EXPLICIT_OFFLINE_VISUAL_FLAG_REQUIRED');
  HttpOverrides.global = _NoNetwork();
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (_) => _failure('flutter_error');
  PlatformDispatcher.instance.onError = (_, __) { _failure('unhandled_error'); return true; };
  final scene = _Scene(0);
  await scene.prepare();
  runApp(_OfflineVisualApp(initial: scene));
}

class _OfflineVisualApp extends StatefulWidget {
  const _OfflineVisualApp({required this.initial});
  final _Scene initial;
  @override
  State<_OfflineVisualApp> createState() => _OfflineVisualAppState();
}

class _OfflineVisualAppState extends State<_OfflineVisualApp> {
  late _Scene _scene;
  bool _busy = false;
  Timer? _readyTimer;
  @override
  void initState() { super.initState(); _scene = widget.initial; _markReady(); }

  void _markReady() {
    final current = _scene;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _readyTimer = Timer(const Duration(milliseconds: 600), () {
          if (!mounted || !identical(current, _scene)) return;
          if (current.adapter.requests == 0) _failure('fixture_request_missing');
          final item = _cases[current.index];
          _event({'event': 'ready', 'case': current.index, 'surface': item.surface,
            'role': item.role, 'state': item.state, 'dark': item.dark,
            'textScale': item.scale, 'requests': current.adapter.requests,
            'failures': _failures.value});
        });
      });
      WidgetsBinding.instance.scheduleFrame();
    });
  }

  Future<void> _next() async {
    if (_busy || _scene.index == _cases.length - 1 || _failures.value != 0) return;
    setState(() => _busy = true);
    _readyTimer?.cancel();
    final next = _Scene(_scene.index + 1);
    await next.prepare();
    if (!mounted) { next.dispose(); return; }
    final previous = _scene;
    setState(() { _scene = next; _busy = false; });
    WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    _markReady();
  }

  ScrollPosition? _verticalPosition() {
    ScrollPosition? position;
    void visit(Element element) {
      if (position != null) return;
      if (element is StatefulElement && element.state is ScrollableState) {
        final scrollable = element.state as ScrollableState;
        final candidate = scrollable.position;
        if ((candidate.axisDirection == AxisDirection.down ||
             candidate.axisDirection == AxisDirection.up) &&
            candidate.hasContentDimensions && candidate.maxScrollExtent > 0) {
          position = candidate;
          return;
        }
      }
      element.visitChildElements(visit);
    }
    _scene.bodyKey.currentContext?.visitChildElements(visit);
    return position;
  }

  void _scrollBy(double delta) {
    if (_busy || _failures.value != 0) return;
    final position = _verticalPosition();
    if (position == null) return;
    final offset = (position.pixels + delta)
      .clamp(position.minScrollExtent, position.maxScrollExtent).toDouble();
    position.jumpTo(offset);
  }

  void _scrollPage(bool forward) {
    final position = _verticalPosition();
    if (position != null) _scrollBy(position.viewportDimension * (forward ? .65 : -.65));
  }

  @override
  void dispose() { _readyTimer?.cancel(); _scene.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final item = _cases[_scene.index];
    final marker = 'AQER_VISUAL_CASE_${_scene.index.toString().padLeft(2, '0')}';
    final canAdvance = !_busy && _scene.index < _cases.length - 1;
    return UncontrolledProviderScope(key: ValueKey(_scene.index), container: _scene.container,
      child: MaterialApp(debugShowCheckedModeBanner: false,
        theme: AppTheme.light, darkTheme: AppTheme.dark,
        themeMode: item.dark ? ThemeMode.dark : ThemeMode.light,
        locale: const Locale('ar'), supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(item.scale)),
          child: Directionality(textDirection: TextDirection.rtl, child: child!)),
        home: Scaffold(body: SafeArea(child: Column(children: [
          MediaQuery.withNoTextScaling(child: Directionality(textDirection: TextDirection.ltr,
            child: ColoredBox(color: const Color(0xff112233), child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(targetMarker, style: TextStyle(fontSize: 10, color: Colors.white)),
                  const Text('SYNTHETIC OFFLINE', style: TextStyle(fontSize: 10, color: Colors.white)),
                  Text(marker, style: const TextStyle(fontSize: 11, color: Colors.white)),
                  ValueListenableBuilder<int>(valueListenable: _failures, builder: (_, count, __) =>
                    Text(count == 0 ? '${item.surface}/${item.state}/${item.role}' : 'AQER_VISUAL_FAILURE',
                      style: const TextStyle(fontSize: 10, color: Colors.white))),
                ])),
                Semantics(label: 'AQER_VISUAL_NEXT', button: true, enabled: canAdvance,
                  excludeSemantics: true, onTap: canAdvance ? _next : null,
                  child: TextButton(onPressed: canAdvance ? _next : null,
                    child: const Text('Next', style: TextStyle(color: Colors.white)))),
              ]))))),
          // Only this outer vertical gesture/semantic action moves the actual
          // scroll position. All product taps, drags and write actions stay blocked.
          Expanded(child: Semantics(container: true, explicitChildNodes: true,
            label: 'AQER_VISUAL_SCROLL',
            onScrollDown: () => _scrollPage(true), onScrollUp: () => _scrollPage(false),
            child: GestureDetector(behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onVerticalDragUpdate: (details) => _scrollBy(-details.delta.dy),
              child: AbsorbPointer(child: KeyedSubtree(
                key: _scene.bodyKey, child: item.screen))))),
        ])))),
    );
  }
}

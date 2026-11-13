// Opt-in, read-only UAT target. Product main.dart never imports this file.
// Existing screens, repositories, authentication and server permissions stay real.
import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'main.dart' show RealEstateApp;
import 'core/local/stage6_secure_session_store.dart';
import 'core/network/api_client.dart';
import 'core/theme/theme_controller.dart';
import 'features/account/data/auth_controller.dart';
import 'router/app_router.dart';

const privatePagesMarker = 'AQER_PHASE23_PRIVATE_PAGES_READ_ONLY_V1';
const privatePagesApi = 'https://real-estate-uat-api-frankfurt.onrender.com/api';
// Only endpoints that actually support per_page are changed. Customers retain30.
const privatePageSizes = <String, (int, int)>{
  '/properties/mine/list': (1, 10), '/favorites': (2, 1),
  '/broker/listings/availability': (3, 10), '/broker/customers': (4, 0),
  '/admin/workspace/tasks': (5, 2), '/admin/account-verifications': (6, 2),
  '/messages/threads': (7, 1), '/admin/support/cases': (8, 2),
  '/admin/messages/reports': (9, 1), '/admin/listing-review/queue': (10, 2),
};

bool privatePagesAllowed({required bool enabled, required String environment, required String api}) =>
  enabled && environment == 'uat' && api == privatePagesApi;

void main() {
  if (!privatePagesAllowed(enabled: const bool.fromEnvironment('AQER_PHASE23_PRIVATE_PAGES'),
      environment: ApiEnvironmentConfig.environment, api: ApiEnvironmentConfig.configuredBaseUrl)) {
    throw StateError('Explicit pinned read-only UAT target required');
  }
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ProviderScope(child: PrivatePagesApp(gate: PrivatePagesGate())));
}

class PrivatePagesGate extends ChangeNotifier {
  int Function() actor = () => 0;
  int Function() epoch = () => Stage6SecureSessionStore.instance.sessionEpoch;
  int sequence = 0, errors = 0, writes = 0, pushCleanup = 0;
  final Map<String, Set<String>> _seen = {};
  void changed() => scheduleMicrotask(notifyListeners);
  void event(Map<String, int> row) {
    // Numbers only, no URLs, filters, row IDs, credentials or private content.
    debugPrint('AQER_PRIVATE:${jsonEncode({'seq': ++sequence, ...row})}');
    changed();
  }
  Map<String, int> get metadata => {'v': 1, 'actor': actor(), 'epoch': epoch(),
    'events': sequence, 'errors': errors, 'writes': writes, 'pushCleanup': pushCleanup};
}

class PrivatePagesTransport extends Interceptor {
  PrivatePagesTransport(this.gate);
  final PrivatePagesGate gate;
  static const _key = 'phase23PrivateRead';
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final pinned = options.uri.origin == Uri.parse(privatePagesApi).origin;
    final path = options.uri.path;
    final auth = pinned && options.method == 'POST' &&
      const {'/api/auth/whatsapp/start','/api/auth/whatsapp/verify','/api/auth/logout'}.contains(path);
    final read = options.method == 'GET' || options.method == 'HEAD';
    if ((!read && !auth) || RegExp(r'(^|/)ai(/|$)').hasMatch(path) ||
        RegExp(r'/properties/[0-9]+/ask$').hasMatch(path)) {
      if (pinned && options.method == 'DELETE' && path == '/api/push/devices') {
        gate.pushCleanup++;
      } else { gate.writes++; }
      gate.changed();
      handler.reject(DioException(requestOptions: options, error: 'Read-only UAT target'));
      return;
    }
    final endpoint = path.startsWith('/api/') ? path.substring(4) : '';
    final config = pinned && options.method == 'GET' ? privatePageSizes[endpoint] : null;
    if (config != null && gate.actor() != 0) {
      final page = int.tryParse('${options.queryParameters['page'] ?? 1}') ?? 1;
      final original = int.tryParse('${options.queryParameters['per_page'] ?? 0}') ?? 0;
      if (config.$2 > 0) options.queryParameters['per_page'] = config.$2;
      final row = {'surface': config.$1, 'actor': gate.actor(), 'epoch': gate.epoch(),
        'page': page, 'original': original, 'size': config.$2, 'phase': 1,
        'count': 0, 'last': 0, 'total': 0, 'duplicate': 0, 'changed': 0};
      // Internal key may contain filters; it is never logged or exported.
      final filters = Map<String, dynamic>.from(options.queryParameters)..remove('page');
      options.extra[_key] = (row, '${row['actor']}:${row['epoch']}:$endpoint:${jsonEncode(filters)}');
      gate.event(row);
    }
    handler.next(options);
  }
  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final trace = response.requestOptions.extra[_key];
    if (trace is (Map<String, int>, String)) {
      final row = Map<String, int>.from(trace.$1), body = response.data;
      final data = body is Map ? body['data'] : null, meta = body is Map ? body['meta'] : null;
      if (data is List && meta is Map && meta['current_page'] == row['page'] &&
          meta['last_page'] is int && meta['total'] is int) {
        final ids = data.map((item) => item is Map
          ? '${item['id'] ?? item['user_id'] ?? item['thread_id'] ?? (item['property'] is Map ? (item['property'] as Map)['id'] : null)}'
          : 'invalid').toList();
        final seen = row['page'] == 1 ? <String>{} : (gate._seen[trace.$2] ?? <String>{});
        row['duplicate'] = ids.length - ids.toSet().length + ids.where(seen.contains).length;
        seen.addAll(ids); gate._seen[trace.$2] = seen;
        row.addAll({'phase': 2, 'count': data.length, 'last': meta['last_page'] as int,
          'total': meta['total'] as int,
          'changed': gate.actor() == row['actor'] && gate.epoch() == row['epoch'] ? 0 : 1});
      } else { row['phase'] = 4; }
      gate.event(row);
    }
    handler.next(response);
  }
  @override
  void onError(DioException error, ErrorInterceptorHandler handler) {
    final trace = error.requestOptions.extra[_key];
    if (trace is (Map<String, int>, String)) {
      gate.event({...trace.$1, 'phase': 3,
        'changed': gate.actor() == trace.$1['actor'] && gate.epoch() == trace.$1['epoch'] ? 0 : 1});
    }
    handler.next(error);
  }
}

class PrivatePagesApp extends ConsumerStatefulWidget {
  const PrivatePagesApp({required this.gate, super.key});
  final PrivatePagesGate gate;
  @override
  ConsumerState<PrivatePagesApp> createState() => _PrivatePagesAppState();
}
class _PrivatePagesAppState extends ConsumerState<PrivatePagesApp> {
  late final void Function(FlutterErrorDetails)? previousError;
  @override
  void initState() {
    super.initState();
    final g = widget.gate;
    g.actor = () => const {28: 1, 26: 2, 25: 3, 8: 4, 9: 5}[
      ref.read(authControllerProvider).asData?.value?.id] ?? 0;
    ref.read(dioProvider).interceptors.insert(0, PrivatePagesTransport(g));
    previousError = FlutterError.onError;
    FlutterError.onError = (details) { g.errors++; g.changed(); previousError?.call(details); };
  }
  @override
  void dispose() { FlutterError.onError = previousError; super.dispose(); }
  @override
  Widget build(BuildContext context) => RealEstateApp(acceptanceWrapper: (context, child) =>
    PrivatePagesPanel(gate: widget.gate, child: child));
}

class PrivatePagesPanel extends ConsumerStatefulWidget {
  const PrivatePagesPanel({required this.gate, required this.child, super.key});
  final PrivatePagesGate gate;
  final Widget child;
  @override
  ConsumerState<PrivatePagesPanel> createState() => _PrivatePagesPanelState();
}
class _PrivatePagesPanelState extends ConsumerState<PrivatePagesPanel> {
  bool expanded = false;
  static const routes = {'PC home': '/', 'PC listings': '/my-listings', 'PC favorites': '/favorites',
    'PC availability': '/broker/availability', 'PC customers': '/broker/customers',
    'PC verification': '/admin/account-verifications', 'PC messages': '/messages',
    'PC support': '/admin/support'};
  void route(String path) {
    ref.read(appRouterProvider).go(path);
    setState(() => expanded = false);
  }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: widget.gate, builder: (context, _) {
    final g = widget.gate;
    return Stack(children: [widget.child, Positioned(top: MediaQuery.paddingOf(context).top + 4, left: 8,
      child: Directionality(textDirection: TextDirection.ltr, child: Material(elevation: 6,
        borderRadius: BorderRadius.circular(8), child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 292, maxHeight: MediaQuery.sizeOf(context).height * .7),
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextButton(onPressed: () => setState(() => expanded = !expanded), child: Text(expanded ? 'PC hide' : 'PC controls')),
            if (expanded) ...[
              Semantics(container: true, excludeSemantics: true, label: privatePagesMarker,
                child: const Text('Read-only private pages', style: TextStyle(fontSize: 10))),
              Semantics(container: true, excludeSemantics: true, button: true, onTap: () {},
                label: 'PC-META:${jsonEncode(g.metadata)}',
                child: const SizedBox(width: 270, height: 36, child: Center(child: Text('PC state')))),
              Wrap(children: [
                for (final entry in routes.entries) TextButton(onPressed: () => route(entry.value), child: Text(entry.key)),
                TextButton(onPressed: () => ref.read(appThemeModeProvider.notifier).setMode(ThemeMode.light), child: const Text('PC light')),
                TextButton(onPressed: () => ref.read(appThemeModeProvider.notifier).setMode(ThemeMode.dark), child: const Text('PC dark')),
              ]),
            ],
          ])),
        )))),
    ]);
  });
}

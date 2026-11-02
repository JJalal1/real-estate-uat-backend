import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:real_estate_mobile/features/discovery/presentation/marketplace_home_screen.dart';
import 'support/owner_ux_fixtures.dart';

List<RouteBase> _routes() => [
  GoRoute(path: '/', builder: (_, __) => const MarketplaceHomeScreen(), routes: [
    GoRoute(path: 'properties/:id', builder: (_, __) => Scaffold(
      appBar: AppBar(), body: const Text('phase1 property destination'))),
  ]),
  GoRoute(path: '/marketplace-search', name: 'phase1-search',
    builder: (_, __) => const Scaffold(body: Text('phase1 search destination'))),
  GoRoute(path: '/marketplace-search-map', name: 'phase1-map',
    builder: (_, __) => const Scaffold(body: Text('phase1 map destination'))),
];

class _PushObserver extends NavigatorObserver {
  final names = <String?>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) { names.add(route.settings.name); }
}

class _DelayedPopRouter extends GoRouter {
  factory _DelayedPopRouter() => _DelayedPopRouter._(ValueNotifier(RoutingConfig(routes: _routes())));
  _DelayedPopRouter._(this.config) : super.routingConfig(routingConfig: config);
  final ValueNotifier<RoutingConfig> config;
  final completedPops = <VoidCallback>[];
  final attempts = <String>[];
  @override
  Future<T?> push<T extends Object?>(String location, {Object? extra}) {
    attempts.add(location);
    final delayed = Completer<T?>();
    unawaited(super.push<T>(location, extra: extra).then<void>((value) {
      completedPops.add(() => delayed.complete(value));
    }, onError: (Object error, StackTrace stack) { delayed.completeError(error, stack); }));
    return delayed.future;
  }
  @override
  void dispose() { super.dispose(); config.dispose(); }
}

void main() {
  setUpAll(loadUxFixtures);

  testWidgets('phase1 retained home opens map after platform deep link', (tester) async {
    final scope = uxContainer(), navigation = GoRouter(routes: _routes());
    addTearDown(navigation.dispose);
    await pumpUx(tester, scope, const SizedBox(), router: navigation);
    final original = tester.state(find.byType(MarketplaceHomeScreen));
    try {
      await tester.tap(find.byKey(const ValueKey('home-search')));
      await tester.pumpAndSettle();
      expect(find.text('phase1 search destination'), findsOneWidget);
      // Flutter 3.27.3's public testing entry notifies didPushRouteInformation,
      // the observer path used by the Android platform navigation channel.
      expect(await tester.binding.handlePushRoute('/properties/60'), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('phase1 property destination'), findsOneWidget);
      expect(identical(original, tester.state(find.byType(MarketplaceHomeScreen, skipOffstage: false))),
        isTrue, reason: 'AQER_PHASE1_HOME_STATE_RECREATED');
      debugPrint('AQER_PHASE1_RETAINED_HOME_VERIFIED');
      navigation.pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-map')));
      await tester.pumpAndSettle();
      if (navigation.state.uri.path == '/') {
        debugPrint('AQER_PHASE1_MAP_AFTER_DEEP_LINK_NOT_OPEN');
      }
      expect(navigation.state.uri.path, '/marketplace-search-map',
        reason: 'AQER_PHASE1_MAP_AFTER_DEEP_LINK_NOT_OPEN');
      expect(find.text('phase1 map destination'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally { await closeUx(tester); }
  });

  testWidgets('phase1 same-frame duplicate search pushes only once', (tester) async {
    final scope = uxContainer(), observer = _PushObserver();
    final navigation = GoRouter(routes: _routes(), observers: [observer]);
    addTearDown(navigation.dispose);
    await pumpUx(tester, scope, const SizedBox(), router: navigation);
    try {
      final search = find.byKey(const ValueKey('home-search'));
      await tester.tap(search);
      await tester.tap(search);
      await tester.pumpAndSettle();
      expect(observer.names.where((name) => name == 'phase1-search'), hasLength(1));
      expect(tester.takeException(), isNull);
    } finally { await closeUx(tester); }
  });

  testWidgets('phase1 stale pop completion cannot unlock a newer push', (tester) async {
    final scope = uxContainer(), navigation = _DelayedPopRouter();
    addTearDown(navigation.dispose);
    await pumpUx(tester, scope, const SizedBox(), router: navigation);
    try {
      await tester.tap(find.byKey(const ValueKey('home-search')));
      await tester.pumpAndSettle();
      navigation.pop();
      await tester.pumpAndSettle();
      expect(navigation.completedPops, hasLength(1));
      final map = find.byKey(const ValueKey('home-map'));
      await tester.tap(map);
      navigation.completedPops.removeAt(0)();
      await tester.idle(); // Flush the old finally without pumping the new frame.
      await tester.tap(map);
      await tester.pumpAndSettle();
      expect(navigation.attempts.where((path) => Uri.parse(path).path == '/marketplace-search-map'), hasLength(1));
      expect(find.text('phase1 map destination'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally { await closeUx(tester); }
  });
}

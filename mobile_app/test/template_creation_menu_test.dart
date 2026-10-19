import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/core/widgets/app_components.dart';
import 'package:real_estate_mobile/core/widgets/ebroker_widgets.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/account/presentation/auth_gate.dart';
import 'package:real_estate_mobile/features/app_shell/presentation/app_shell_screen.dart';
import 'package:real_estate_mobile/features/app_shell/presentation/listing_creation_menu.dart';
import 'package:real_estate_mobile/features/broker/data/broker_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_repository.dart';

import 'broker_experience_ui_test.dart' show BrokerTestRepository, brokerTestUser;
import 'support/wave3_fakes.dart';

class _UserAuth extends AuthController {
  _UserAuth(this.user);
  final AuthUser? user;
  @override
  Future<AuthUser?> build() async => user;
}

class _EditorPushes extends NavigatorObserver {
  int count = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name == 'editor') count++;
    super.didPush(route, previousRoute);
  }
}

Future<GoRouter> _pump(WidgetTester tester, {
  AuthUser? user, double scale = 1, Size size = const Size(412, 915),
  bool reducedMotion = false, GlobalKey? boundary, _EditorPushes? observer,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(observers: [if (observer != null) observer], routes: [
    GoRoute(path: '/', builder: (_, __) => const AppShellScreen()),
    GoRoute(name: 'editor', path: '/add-property', builder: (_, state) => Stage6AuthGate(
      requireListingEligible: true, child: Scaffold(appBar: AppBar(),
        body: Text('editor-assistant=${state.uri.queryParameters['assistant']}')))),
    GoRoute(path: '/auth', builder: (_, __) => const Scaffold(body: Text('auth'))),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(overrides: [
    authControllerProvider.overrideWith(() => _UserAuth(user)),
    brokerRepositoryProvider.overrideWithValue(BrokerTestRepository()),
    marketplaceRepositoryProvider.overrideWithValue(Wave3MarketplaceFake()),
    homeLocationAttemptedProvider.overrideWith((_) => true),
  ], child: MaterialApp.router(theme: AppTheme.light, routerConfig: router,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale),
        disableAnimations: reducedMotion),
      child: Directionality(textDirection: TextDirection.rtl,
        child: RepaintBoundary(key: boundary, child: child!))))));
  await tester.pumpAndSettle();
  return router;
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('home-add-property')));
  await tester.pumpAndSettle();
}

Future<void> _capture(GlobalKey boundary, String name, WidgetTester tester) async {
  await tester.runAsync(() async {
    final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/listing-design-preview/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final family in ['sans-serif', 'NotoSansArabic']) {
      await (FontLoader(family)
        ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'))).load();
    }
    final font = FontLoader('PrimaryFont');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      font.addFont(rootBundle.load('assets/ebroker/fonts/Manrope-$weight.ttf'));
    }
    await font.load();
    final icons = await File('${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytes();
    await (FontLoader('MaterialIcons')..addFont(Future.value(icons.buffer.asByteData()))).load();
  });

  testWidgets('template pills sit above the undimmed bar with original SVGs', (tester) async {
    final key = GlobalKey();
    await _pump(tester, user: brokerTestUser(), boundary: key);
    await _capture(key, 'template-menu-closed', tester);
    await _open(tester);
    final nav = tester.getRect(find.byType(AppNavigationBar));
    final scrim = tester.getRect(find.byKey(const ValueKey('create-listing-scrim')));
    final manual = tester.getRect(find.byKey(const ValueKey('create-listing-manual')));
    final ai = tester.getRect(find.byKey(const ValueKey('create-listing-ai')));
    expect(scrim.bottom, closeTo(nav.top, .1));
    expect(manual.size, const Size(180, 44));
    expect(ai.size, const Size(128, 44));
    expect(manual.center.dx, closeTo(206, .1));
    expect(ai.center.dx, closeTo(manual.center.dx, .1));
    expect(nav.top - manual.bottom, closeTo(30, .1));
    expect(nav.top - ai.bottom, closeTo(80, .1));
    expect(ai.bottom, lessThan(manual.top));
    expect(find.text('ذكاء اصطناعي'), findsOneWidget);
    expect(find.text('تعبئة يدوي'), findsOneWidget);
    expect(find.text('إعلانك يبدأ هنا'), findsNothing);
    expect(find.byType(Dialog), findsNothing);
    for (final asset in ['add_shape', 'plus_btn', 'upcoming_projects_icon',
      'properties_icon', 'home_active', 'properties', 'chat', 'profile_outlined']) {
      final scope = ['upcoming_projects_icon', 'properties_icon'].contains(asset)
          ? find.byType(ListingCreationMenu) : find.byType(AppNavigationBar);
      expect(find.descendant(of: scope, matching: find.byWidgetPredicate(
        (widget) => widget is EbrokerImage && widget.name == asset)),
        findsOneWidget, reason: 'Use the purchased $asset vector.');
    }
    final aiIcon = find.byWidgetPredicate((widget) => widget is EbrokerImage &&
      widget.name == 'upcoming_projects_icon');
    expect(tester.getCenter(aiIcon).dx, greaterThan(tester.getCenter(find.text('ذكاء اصطناعي')).dx));
    await _capture(key, 'template-menu-open', tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rise progresses and finishes the lower pill before the upper', (tester) async {
    final key = GlobalKey();
    await _pump(tester, user: brokerTestUser(), boundary: key);
    await tester.tap(find.byKey(const ValueKey('home-add-property')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final moving = tester.getRect(find.byKey(const ValueKey('create-listing-manual')));
    await _capture(key, 'template-menu-motion-150ms', tester);
    await tester.pump(const Duration(milliseconds: 150));
    final nav = tester.getRect(find.byType(AppNavigationBar));
    final settled = tester.getRect(find.byKey(const ValueKey('create-listing-manual')));
    final movingAi = tester.getRect(find.byKey(const ValueKey('create-listing-ai')));
    expect(settled.top, lessThan(moving.top));
    expect(nav.top - settled.bottom, closeTo(30, .1));
    expect(nav.top - movingAi.bottom, lessThan(80));
    await tester.pumpAndSettle();
    expect(nav.top - tester.getRect(find.byKey(const ValueKey('create-listing-ai'))).bottom,
      closeTo(80, .1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('hexagon, outside, system back and tab selection all close', (tester) async {
    await _pump(tester, user: brokerTestUser());
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey('home-add-property')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('create-listing-ai')), findsNothing);
    await _open(tester);
    await tester.tapAt(const Offset(20, 100));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('create-listing-ai')), findsNothing);
    await _open(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('create-listing-ai')), findsNothing);
    expect(find.text('الخروج من التطبيق؟'), findsNothing);
    await _open(tester);
    await tester.tap(find.byTooltip('الرئيسية'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('create-listing-ai')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final assisted in [true, false]) {
    testWidgets('$assisted opens the canonical editor once', (tester) async {
      final observer = _EditorPushes();
      await _pump(tester, user: brokerTestUser(), observer: observer);
      await _open(tester);
      final menu = tester.widget<ListingCreationMenu>(find.byType(ListingCreationMenu));
      await tester.tap(find.byKey(ValueKey(assisted ? 'create-listing-ai' : 'create-listing-manual')));
      menu.onSelected(!assisted);
      await tester.pumpAndSettle();
      expect(observer.count, 1);
      expect(find.text('editor-assistant=${assisted ? 1 : 0}'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final regular in [false, true]) {
      testWidgets('$assisted retains the $regular account gate', (tester) async {
        await _pump(tester, user: regular ? brokerTestUser(2) : null);
        await _open(tester);
        await tester.tap(find.byKey(ValueKey(assisted ? 'create-listing-ai' : 'create-listing-manual')));
        await tester.pumpAndSettle();
        expect(find.text(regular ? 'توثيق نوع الحساب مطلوب' : 'سجّل الدخول أولاً'), findsOneWidget);
        expect(find.textContaining('editor-assistant='), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('large Arabic keeps both actions separate and tappable', (tester) async {
    final key = GlobalKey();
    await _pump(tester, user: brokerTestUser(), scale: 2.4,
      size: const Size(320, 568), boundary: key);
    await _open(tester);
    final manual = tester.getRect(find.byKey(const ValueKey('create-listing-manual')));
    final ai = tester.getRect(find.byKey(const ValueKey('create-listing-ai')));
    expect(ai.bottom, lessThan(manual.top));
    for (final rect in [manual, ai]) {
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
      expect(rect.top, greaterThanOrEqualTo(0));
    }
    await _capture(key, 'template-menu-large-arabic', tester);
    await tester.tap(find.byKey(const ValueKey('create-listing-ai')));
    await tester.pumpAndSettle();
    expect(find.text('editor-assistant=1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion opens and closes without a running ticker', (tester) async {
    await _pump(tester, user: brokerTestUser(), reducedMotion: true);
    await tester.tap(find.byKey(const ValueKey('home-add-property')));
    await tester.pump();
    expect(find.byKey(const ValueKey('create-listing-ai')).hitTestable(), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.tap(find.byKey(const ValueKey('home-add-property')));
    await tester.pump();
    expect(find.byKey(const ValueKey('create-listing-ai')), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });
}

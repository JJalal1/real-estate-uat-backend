import 'dart:async';
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
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/account/presentation/auth_gate.dart';
import 'package:real_estate_mobile/features/discovery/presentation/marketplace_home_screen.dart';
import 'package:real_estate_mobile/features/map/presentation/map_screen.dart';
import 'package:real_estate_mobile/features/broker/data/broker_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/property_marker.dart';

final _exampleProperty = PropertyMarker.fromJson({
  'id': 37,
  'title': 'منزل للعائلة في حدة',
  'price': 100000000,
  'display_price': 102000000,
  'currency': 'YER',
  'latitude': 15.3694,
  'longitude': 44.1910,
  'distance_km': 2,
  'purpose': 'sale',
  'address': 'صنعاء، حدة',
  'price_display_note': 'السعر المعروض يشمل السعي',
});

class _TestAuthController extends AuthController {
  _TestAuthController(this.user);

  final AuthUser? user;

  @override
  Future<AuthUser?> build() async => user;
}

Future<GoRouter> _pumpHome(
  WidgetTester tester, {
  Future<List<PropertyMarker>> Function()? load,
  bool advertiser = false,
  AuthUser? user,
  double scale = 1,
  GlobalKey? boundaryKey,
}) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => MarketplaceHomeScreen(
          showAdvertiserActions: advertiser,
        ),
      ),
      GoRoute(
        path: '/property-market',
        builder: (_, __) => const Scaffold(body: Text('map destination')),
      ),
      GoRoute(
        path: '/properties/:id',
        builder: (_, state) => Scaffold(
          body: Text('property ${state.pathParameters['id']}'),
        ),
      ),
      GoRoute(
        path: '/favorites',
        builder: (_, state) => Stage6AuthGate(
          child: Scaffold(
            body: Text('favorites compare=${state.uri.queryParameters['compare']}'),
          ),
        ),
      ),
      GoRoute(
        path: '/notifications',
        builder: (_, __) => const Stage6AuthGate(
          child: Scaffold(body: Text('notifications destination')),
        ),
      ),
      GoRoute(
        path: '/add-property',
        builder: (_, __) => const Stage6AuthGate(
          requireListingEligible: true,
          child: Scaffold(body: Text('listing destination')),
        ),
      ),
      GoRoute(
        path: '/auth',
        builder: (_, __) => const Scaffold(body: Text('auth destination')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => _TestAuthController(user)),
        brokerDirectoryProvider.overrideWith((_) async => []),
        nearbyPropertiesProvider(homeDiscoveryQuery).overrideWith(
          (_) => load?.call() ?? Future.value([_exampleProperty]),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light,
        routerConfig: router,
        builder: (context, child) => RepaintBoundary(
          key: boundaryKey,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: child!,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return router;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final fonts = FontLoader('NotoSansArabic')
      ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf'));
    await fonts.load();
    final manrope = FontLoader('PrimaryFont');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      manrope.addFont(rootBundle.load('assets/ebroker/fonts/Manrope-$weight.ttf'));
    }
    await manrope.load();
    // Widget tests omit the SDK icon and platform fallback fonts by default.
    // Load the pinned SDK fonts so previews render the same glyphs as Android.
    final flutterRoot = Platform.environment['FLUTTER_ROOT']!;
    final fontDirectory = '$flutterRoot/bin/cache/artifacts/material_fonts';
    final icons = await File('$fontDirectory/MaterialIcons-Regular.otf').readAsBytes();
    await (FontLoader('MaterialIcons')
          ..addFont(Future.value(icons.buffer.asByteData())))
        .load();
    final latin = await File('$fontDirectory/Roboto-Regular.ttf').readAsBytes();
    for (final family in ['Arial', 'sans-serif']) {
      final loader = FontLoader(family)..addFont(Future.value(latin.buffer.asByteData()));
      if (family == 'sans-serif') loader.addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
      await loader.load();
    }
  });

  testWidgets('public home uses display price and opens the real property ID',
      (tester) async {
    final router = await _pumpHome(tester);
    await tester.pumpAndSettle();
    expect(find.text('السعر المعروض يشمل السعي'), findsOneWidget);
    expect(
      find.byWidgetPredicate((widget) => widget is Text &&
          widget.textSpan?.toPlainText().contains('102000000 YER') == true),
      findsOneWidget,
    );
    expect(find.text('إضافة عقار'), findsNothing);
    final property = find.byKey(const ValueKey('home-property-37'));
    await tester.ensureVisible(property);
    await tester.pumpAndSettle();
    await tester.tap(property);
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/properties/37');
    expect(find.text('property 37'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final entry in ['home-search', 'home-map']) {
    testWidgets('$entry keeps anonymous map discovery accessible',
        (tester) async {
      final router = await _pumpHome(tester);
      await tester.pumpAndSettle();
      final target = find.byKey(ValueKey(entry));
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/property-market');
      expect(find.text('map destination'), findsOneWidget);
    });
  }

  for (final entry in ['home-favorites', 'home-compare']) {
    testWidgets('$entry retains the real account gate', (tester) async {
      final router = await _pumpHome(tester);
      await tester.pumpAndSettle();
      // Favorites/compare moved to the template profile menu; their original
      // protected routes must still enforce account access.
      router.push(entry == 'home-compare' ? '/favorites?compare=1' : '/favorites');
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/favorites');
      expect(find.text('سجّل الدخول أولاً'), findsOneWidget);
      if (entry == 'home-compare') {
        expect(router.state.uri.queryParameters['compare'], '1');
      }
      expect(find.textContaining('favorites compare='), findsNothing);
    });
  }

  testWidgets('empty home leaves discovery usable', (tester) async {
    final router = await _pumpHome(tester, load: () async => []);
    await tester.pumpAndSettle();
    expect(find.text('لا توجد عقارات في هذا النطاق'), findsOneWidget);
    final action = find.text('استكشاف الخريطة');
    await tester.scrollUntilVisible(action, 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/property-market');
    expect(find.text('map destination'), findsOneWidget);
  });

  testWidgets('a failed feed can be retried without losing navigation',
      (tester) async {
    var calls = 0;
    await _pumpHome(tester, load: () async {
      if (calls++ == 0) throw StateError('offline');
      return [_exampleProperty];
    });
    await tester.pumpAndSettle();
    final retry = find.text('إعادة المحاولة');
    await tester.ensureVisible(retry);
    await tester.pumpAndSettle();
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.byKey(const ValueKey('home-property-37')), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('home-search')), -300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-search')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh reloads the existing feed provider', (tester) async {
    var calls = 0;
    await _pumpHome(tester, load: () async {
      calls++;
      return [_exampleProperty];
    });
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 450));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('advertiser shortcut cannot bypass publishing eligibility',
      (tester) async {
    final user = AuthUser.fromJson({
      'id': 9,
      'name': 'مستخدم للاختبار',
      'email': 'example@example.invalid',
      'account_status': 'active',
      'phone_verified_at': '2026-10-11T00:00:00Z',
      'profile_completed_at': '2026-10-11T00:00:00Z',
    });
    await _pumpHome(tester, advertiser: true, user: user);
    await tester.pumpAndSettle();
    final action = find.text('إضافة عقار');
    await tester.scrollUntilVisible(action, 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.text('توثيق نوع الحساب مطلوب'), findsOneWidget);
    expect(find.text('listing destination'), findsNothing);
  });

  for (final size in [const Size(320, 640), const Size(412, 915), const Size(800, 1000)]) {
    for (final scale in [1.0, 2.4]) {
      testWidgets('home ${size.width} scale $scale remains RTL and scrollable',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final pending = Completer<List<PropertyMarker>>();
        await _pumpHome(tester, load: () => pending.future, scale: scale);
        expect(find.byType(AppSkeleton), findsWidgets);
        expect(Directionality.of(tester.element(find.byType(MarketplaceHomeScreen))),
            TextDirection.rtl);
        pending.complete([_exampleProperty]);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final card = find.byKey(const ValueKey('home-property-37'));
        await tester.ensureVisible(card);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('home-search')), findsOneWidget);
      });
    }
  }

  testWidgets('exports the rendered home with synthetic preview data',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await _pumpHome(tester, boundaryKey: key);
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final output = File('build/v3-preview/$name.png');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture('home-top');
    await tester.ensureVisible(find.byKey(const ValueKey('home-property-37')));
    await tester.pumpAndSettle();
    await capture('home-properties');
    expect(tester.takeException(), isNull);
  });
}

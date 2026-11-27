import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:real_estate_mobile/features/account/presentation/account_screen.dart';
import 'package:real_estate_mobile/features/properties/data/saved_search_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/saved_property_search.dart';
import 'package:real_estate_mobile/features/services/data/service_repository.dart';
import 'package:real_estate_mobile/features/services/domain/service_models.dart';
import 'package:real_estate_mobile/router/app_router.dart';

import 'support/owner_ux_fixtures.dart';

void main() {
  setUpAll(loadUxFixtures);

  testWidgets(
      'the authenticated services route still opens a broker’s owned saved searches',
      (tester) async {
    final auth = UxAuth(uxUser(id: 28, type: 'broker'));
    final scope = uxContainer(auth: auth, extra: [
      freeServicesHubProvider
          .overrideWith((_) async => FreeServicesHubModel.fromJson({
                'account_type': 'broker',
                'verification_status': 'approved',
                'verified_professional': true,
              })),
      savedSearchesProvider.overrideWith((_) async => const [
            SavedPropertySearch(
                id: 6,
                name: 'UAT1822 10',
                filters: {'type': 'land'},
                alertFrequency: 'off',
                isActive: true,
                matchingCount: 36),
          ]),
    ]);
    final production = scope.read(appRouterProvider);
    addTearDown(production.dispose);
    final services = production.configuration.routes
        .whereType<GoRoute>()
        .firstWhere((route) => route.path == '/services');
    final navigation = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const AccountScreen()),
      GoRoute(path: services.path, builder: services.builder),
    ]);
    addTearDown(navigation.dispose);
    await pumpUx(tester, scope, const SizedBox(), router: navigation,
      size: const Size(412, 1320));
    expect(find.text('الخدمات والدعم'), findsOneWidget);
    expect(find.text('الخدمات والأدوات'), findsNothing);
    navigation.go('/services');
    await tester.pumpAndSettle();
    final saved = find.text('البحوث المحفوظة والتنبيهات');
    await tester.ensureVisible(saved);
    await tester.tap(saved);
    await tester.pumpAndSettle();
    expect(find.text('UAT1822 10'), findsOneWidget);
    expect(find.text('عرض النتائج'), findsOneWidget);

    auth.change(null);
    await tester.pumpAndSettle();
    expect(find.text('سجّل الدخول للمتابعة.'), findsOneWidget);
    expect(find.text('UAT1822 10'), findsNothing);
    expect(tester.takeException(), isNull);
    await closeUx(tester);
  });

  testWidgets(
      'the services shortcut stays absent in the administrative account layout',
      (tester) async {
    final scope =
        uxContainer(user: uxUser(type: 'broker', roles: ['support_agent']));
    await pumpUx(tester, scope, const AccountScreen());
    expect(find.text('الخدمات والأدوات'), findsNothing);
    await tester.scrollUntilVisible(find.text('تسجيل الخروج'), 220,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('الخدمات والأدوات'), findsNothing);
    await closeUx(tester);
  });
}

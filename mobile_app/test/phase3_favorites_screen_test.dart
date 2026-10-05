import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:real_estate_mobile/core/widgets/app_components.dart';
import 'package:real_estate_mobile/features/properties/data/favorites_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/favorite_list_item.dart';
import 'package:real_estate_mobile/features/properties/presentation/favorites_screen.dart';

const _unavailableMessage =
    'هذا العقار محفوظ في المفضلة لكنه غير متاح حالياً.';

Map<String, dynamic> _available(int id) => {
      'property_id': id,
      'is_favorited': true,
      'favorited_at': '2026-10-05T12:00:00Z',
      'availability': 'available',
      'property': {
        'id': id,
        'status': 'published',
        'title': 'عقار محفوظ $id',
        'price': 25000000,
        'currency': 'YER',
        'latitude': 15.3694,
        'longitude': 44.1910,
        'purpose': 'sale',
        'type': 'apartment',
        'area_m2': 120,
        'bedrooms': 3,
        'bathrooms': 2,
        'address': 'صنعاء',
      },
    };

Map<String, dynamic> _unavailable(int id) => {
      'property_id': id,
      'is_favorited': true,
      'favorited_at': '2026-10-05T12:00:00Z',
      'availability': 'unavailable',
      'message': _unavailableMessage,
    };

class _FixtureFavorites implements FavoritesRepository {
  _FixtureFavorites(this.rows);

  List<Map<String, dynamic>> rows;
  final removed = <int>[];
  int loads = 0;

  @override
  Future<List<FavoriteListItem>> favorites() async {
    loads++;
    return rows.map(FavoriteListItem.fromJson).toList(growable: false);
  }

  @override
  Future<void> remove(int propertyId) async {
    removed.add(propertyId);
    rows.removeWhere((row) => row['property_id'] == propertyId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(
  WidgetTester tester,
  _FixtureFavorites repository, {
  bool compare = false,
  GoRouter? router,
}) async {
  tester.view.physicalSize = const Size(400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        favoritesRepositoryProvider.overrideWithValue(repository),
      ],
      child: router == null
          ? MaterialApp(home: FavoritesScreen(startInCompareMode: compare))
          : MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

GoRouter _router() => GoRouter(
      initialLocation: '/favorites',
      routes: [
        GoRoute(
          path: '/favorites',
          builder: (_, __) => const FavoritesScreen(),
        ),
        GoRoute(
          path: '/properties/:id',
          builder: (_, state) => Scaffold(
            body: Text('تفاصيل ${state.pathParameters['id']}'),
          ),
        ),
      ],
    );

Future<void> _refresh(WidgetTester tester) async {
  final indicator = tester.widget<RefreshIndicator>(find.byType(RefreshIndicator));
  await indicator.onRefresh();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('favorites screen has a real empty state', (tester) async {
    await _pump(tester, _FixtureFavorites([]));
    expect(find.text('المفضلة'), findsOneWidget);
    expect(find.text('لا توجد عقارات محفوظة'), findsOneWidget);
    expect(
      find.text('اضغط على رمز القلب في أي عقار ليظهر هنا ويظل محفوظاً في حسابك.'),
      findsOneWidget,
    );
  });

  testWidgets('available favorite retains normal card and details navigation',
      (tester) async {
    final router = _router();
    addTearDown(router.dispose);
    await _pump(tester, _FixtureFavorites([_available(42)]), router: router);

    expect(find.text('عقار محفوظ 42'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Text &&
            widget.textSpan?.toPlainText().contains('25,000,000 YER') == true,
      ),
      findsOneWidget,
    );
    expect(find.text('صنعاء'), findsOneWidget);
    expect(find.text('للبيع'), findsOneWidget);
    expect(find.text('120 م²'), findsOneWidget);
    expect(find.byTooltip('إزالة من المفضلة'), findsOneWidget);
    await tester.tap(find.text('عقار محفوظ 42'));
    await tester.pumpAndSettle();
    expect(find.text('تفاصيل 42'), findsOneWidget);
  });

  testWidgets('unavailable favorite stays visible with generic wording only',
      (tester) async {
    await _pump(tester, _FixtureFavorites([_unavailable(42)]));
    expect(find.byKey(const ValueKey('unavailable-favorite-42')), findsOneWidget);
    expect(find.text('غير متاح حالياً'), findsOneWidget);
    expect(find.text(_unavailableMessage), findsOneWidget);
    expect(find.text('إزالة من المفضلة'), findsOneWidget);
    expect(find.byType(AppPropertyCard), findsNothing);
    expect(find.byType(AppPropertyPrice), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.location_on_outlined), findsNothing);
    expect(find.byIcon(Icons.phone), findsNothing);
    expect(find.text('طلب معاينة'), findsNothing);
    expect(find.textContaining('تفاصيل'), findsNothing);
  });

  testWidgets('unavailable card ignores stale or private summary fields',
      (tester) async {
    final contaminated = _unavailable(42);
    contaminated['property'] = {
      'id': 42,
      'status': 'published',
      'title': 'PRIVATE TITLE',
      'price': 987654321,
      'currency': 'YER',
      'address': 'PRIVATE ADDRESS',
      'latitude': 16.123456,
      'longitude': 45.654321,
      'main_image': 'https://private.example.test/edit.jpg',
      'description': 'PRIVATE DESCRIPTION',
    };
    expect(FavoriteListItem.fromJson(contaminated).property, isNull);
    await _pump(tester, _FixtureFavorites([contaminated]));
    for (final value in [
      'PRIVATE TITLE', 'PRIVATE ADDRESS', 'PRIVATE DESCRIPTION',
      '987', '16.123456', '45.654321', 'private.example.test',
    ]) {
      expect(find.textContaining(value), findsNothing);
    }
    expect(find.byType(Image), findsNothing);
    expect(find.byType(AppPropertyPrice), findsNothing);
    expect(find.text(_unavailableMessage), findsOneWidget);
  });

  testWidgets('tapping unavailable favorite cannot navigate to details',
      (tester) async {
    final router = _router();
    addTearDown(router.dispose);
    await _pump(tester, _FixtureFavorites([_unavailable(42)]), router: router);
    await tester.tap(find.text(_unavailableMessage));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/favorites');
    expect(find.text('تفاصيل 42'), findsNothing);
    expect(find.text(_unavailableMessage), findsOneWidget);
  });

  testWidgets('unavailable favorites cannot be selected or count for compare',
      (tester) async {
    await _pump(
      tester,
      _FixtureFavorites([_unavailable(99), _available(42), _available(43)]),
      compare: true,
    );
    await tester.tap(find.text(_unavailableMessage));
    await tester.pumpAndSettle();
    expect(find.text('اختر للمقارنة (0/4)'), findsOneWidget);

    await tester.tap(find.text('عقار محفوظ 42'));
    await tester.pumpAndSettle();
    expect(find.text('اختر للمقارنة (1/4)'), findsOneWidget);
    expect(
      tester.widget<AppButton>(find.widgetWithText(AppButton, 'اختر عقارين على الأقل')).onPressed,
      isNull,
    );
    await tester.ensureVisible(find.text('عقار محفوظ 43'));
    await tester.tap(find.text('عقار محفوظ 43'));
    await tester.pumpAndSettle();
    expect(find.text('اختر للمقارنة (2/4)'), findsOneWidget);
    expect(
      tester.widget<AppButton>(find.widgetWithText(AppButton, 'مقارنة 2 عقارات')).onPressed,
      isNotNull,
    );
    expect(find.text('إزالة من المفضلة'), findsOneWidget);
  });

  for (final compare in [false, true]) {
    testWidgets('unavailable removal refreshes account state (compare=$compare)',
        (tester) async {
      final repository = _FixtureFavorites([_unavailable(42)]);
      await _pump(tester, repository, compare: compare);
      await tester.tap(find.text('إزالة من المفضلة'));
      await tester.pumpAndSettle();
      expect(repository.removed, [42]);
      expect(repository.loads, 2);
      expect(find.byKey(const ValueKey('unavailable-favorite-42')), findsNothing);
      expect(find.text('لا توجد عقارات محفوظة'), findsOneWidget);
      expect(find.text('تمت إزالة العقار من المفضلة.'), findsOneWidget);
    });
  }

  testWidgets('republishing refresh restores the same favorite as a normal card',
      (tester) async {
    final repository = _FixtureFavorites([_unavailable(42)]);
    await _pump(tester, repository);
    expect(find.text(_unavailableMessage), findsOneWidget);
    repository.rows = [_available(42)];
    await _refresh(tester);
    expect(repository.removed, isEmpty);
    expect(repository.loads, 2);
    expect(find.text(_unavailableMessage), findsNothing);
    expect(find.text('عقار محفوظ 42'), findsOneWidget);
    expect(find.byType(AppPropertyCard), findsOneWidget);
    expect(find.byType(AppPropertyPrice), findsOneWidget);
    expect(find.byTooltip('إزالة من المفضلة'), findsOneWidget);
  });

  testWidgets('refresh removes newly unavailable favorites from compare selection',
      (tester) async {
    final repository = _FixtureFavorites([_available(42), _available(43)]);
    await _pump(tester, repository, compare: true);
    for (final id in [42, 43]) {
      await tester.tap(find.text('عقار محفوظ $id'));
      await tester.pumpAndSettle();
    }
    expect(find.text('اختر للمقارنة (2/4)'), findsOneWidget);
    repository.rows = [_unavailable(42), _available(43)];
    await _refresh(tester);
    expect(find.text('اختر للمقارنة (1/4)'), findsOneWidget);
    expect(find.text(_unavailableMessage), findsOneWidget);
    expect(
      tester.widget<AppButton>(find.widgetWithText(AppButton, 'اختر عقارين على الأقل')).onPressed,
      isNull,
    );
    await tester.tap(find.text(_unavailableMessage));
    await tester.pumpAndSettle();
    expect(find.text('اختر للمقارنة (1/4)'), findsOneWidget);

    repository.rows = [_available(42), _available(43)];
    await _refresh(tester);
    // Republishing never silently re-selects a previously unavailable item.
    expect(find.text('اختر للمقارنة (1/4)'), findsOneWidget);
    await tester.tap(find.text('عقار محفوظ 42'));
    await tester.pumpAndSettle();
    expect(find.text('اختر للمقارنة (2/4)'), findsOneWidget);
  });

  testWidgets('compare still accepts two to four available favorites',
      (tester) async {
    final repository = _FixtureFavorites([
      _unavailable(99),
      for (final id in [41, 42, 43, 44, 45]) _available(id),
    ]);
    await _pump(tester, repository, compare: true);
    for (final id in [41, 42, 43, 44]) {
      await tester.ensureVisible(find.text('عقار محفوظ $id'));
      await tester.tap(find.text('عقار محفوظ $id'));
      await tester.pumpAndSettle();
    }
    expect(find.text('اختر للمقارنة (4/4)'), findsOneWidget);
    await tester.ensureVisible(find.text('عقار محفوظ 45'));
    await tester.tap(find.text('عقار محفوظ 45'));
    await tester.pumpAndSettle();
    expect(find.text('اختر للمقارنة (4/4)'), findsOneWidget);
    expect(find.text('يمكن مقارنة أربعة عقارات كحد أقصى.'), findsOneWidget);
  });
}

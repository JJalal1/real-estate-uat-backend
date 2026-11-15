import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/widgets/app_components.dart';
import 'package:real_estate_mobile/features/discovery/data/ai_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/smart_search_session.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_search_session.dart';
import 'package:real_estate_mobile/features/discovery/presentation/assisted_search_screen.dart';
import 'package:real_estate_mobile/features/discovery/presentation/marketplace_search_screen.dart';
import 'package:real_estate_mobile/features/discovery/presentation/marketplace_section_screen.dart';
import 'package:real_estate_mobile/features/discovery/presentation/smart_search_assistant.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';

import 'support/wave3_fakes.dart';

class _NoHint extends AssistantHintStore {
  @override
  Future<bool> take() async => false;
}

DioException _unavailable() {
  final request = RequestOptions(path: '/properties');
  return DioException(
    requestOptions: request,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: request, statusCode: 503),
  );
}

void main() {
  for (final surface in ['assisted', 'home', 'section']) {
    testWidgets('$surface long-list failure keeps page-two retry at the visible footer', (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final properties = Wave3PropertiesFake();
      var fails = true;
      properties.onSearch = (_, page) async {
        if (page == 1) return ([for (var id = 1; id <= 20; id++) wave3Property(id)], true);
        if (fails) throw _unavailable();
        return ([wave3Property(20), wave3Property(21)], false);
      };
      final container = ProviderContainer(overrides: [
        aiRepositoryProvider.overrideWithValue(Wave3AiFake()),
        propertyRepositoryProvider.overrideWithValue(properties),
        assistantHintStoreProvider.overrideWithValue(_NoHint()),
      ]);
      addTearDown(container.dispose);
      final screen = switch (surface) {
        'home' => const MarketplaceSearchScreen(),
        'section' => const MarketplaceSectionScreen(),
        _ => const AssistedSearchScreen(),
      };
      await tester.pumpWidget(UncontrolledProviderScope(container: container,
        child: MaterialApp(home: screen)));
      await tester.pumpAndSettle();
      if (surface == 'assisted') {
        await container.read(smartSearchSessionProvider.notifier).search();
      } else if (surface == 'home') {
        await container.read(marketplaceSearchControllerProvider.notifier).submit();
      }
      await tester.pumpAndSettle();
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('المزيد من العقارات'), 500, scrollable: list);
      await tester.tap(find.text('المزيد من العقارات'));
      await tester.pumpAndSettle();
      expect(properties.queries.map((q) => q.page), [1, 2]);
      await tester.scrollUntilVisible(find.text('إعادة المحاولة'), 120,
        scrollable: list, maxScrolls: 4);
      expect(find.text('إعادة المحاولة').hitTestable(), findsOneWidget);
      expect(tester.state<ScrollableState>(list).position.pixels, greaterThan(1000));
      expect(find.byType(AppErrorState), findsNothing);
      fails = false;
      await tester.tap(find.text('إعادة المحاولة').hitTestable());
      await tester.pumpAndSettle();
      expect(properties.queries.map((q) => q.page), [1, 2, 2]);
      final prefix = switch (surface) {
        'home' => 'home-result', 'section' => 'section-property', _ => 'smart-search-result',
      };
      await tester.scrollUntilVisible(find.byKey(ValueKey('$prefix-21')), 250, scrollable: list);
      expect(find.byKey(ValueKey('$prefix-21')), findsOneWidget);
      expect(find.text('المزيد من العقارات'), findsNothing);
      expect(find.text('إعادة المحاولة'), findsNothing);
      if (surface != 'section') {
        final state = surface == 'home' ? container.read(homeSearchResultsProvider)
          : container.read(smartSearchSessionProvider);
        expect(state.rows.map((r) => r.id), [for (var id = 1; id <= 21; id++) id]);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('second-page outage preserves previous cards and retries page two', (tester) async {
    final properties = Wave3PropertiesFake();
    final ai = Wave3AiFake();
    var secondPageFails = true;
    properties.onSearch = (_, page) async {
      if (page == 1) return ([wave3Property(11)], true);
      if (secondPageFails) throw _unavailable();
      return ([wave3Property(11), wave3Property(12)], false);
    };

    final container = ProviderContainer(overrides: [
      aiRepositoryProvider.overrideWithValue(ai),
      propertyRepositoryProvider.overrideWithValue(properties),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AssistedSearchScreen()),
    ));
    await tester.pumpAndSettle();

    final session = container.read(smartSearchSessionProvider.notifier);
    await session.search();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('smart-search-result-11')), findsOneWidget);
    expect(container.read(smartSearchSessionProvider).more, isTrue);
    // ListView creates offscreen children lazily; ensureVisible requires a
    // built element, so scroll until the pagination button is actually built.
    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('المزيد من العقارات'), 250, scrollable: list);
    await tester.tap(find.text('المزيد من العقارات'));
    await tester.pumpAndSettle();

    expect(container.read(smartSearchSessionProvider).rows.map((row) => row.id).toList(), [11]);
    await tester.scrollUntilVisible(find.byType(AppRefreshStatus), -250, scrollable: list);
    expect(find.byType(AppRefreshStatus), findsOneWidget);
    expect(find.byKey(const ValueKey('smart-search-result-11')), findsOneWidget);
    expect(find.byType(AppErrorState), findsNothing);
    expect(find.text('إعادة المحاولة'), findsOneWidget);

    secondPageFails = false;
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(properties.queries.map((q) => q.page).toList(), [1, 2, 2]);
    expect(container.read(smartSearchSessionProvider).rows.map((row) => row.id).toList(), [11, 12]);
    // Check both cards independently: a lazy ListView can unmount the first
    // while scrolling to the second, even though both remain in session state.
    await tester.scrollUntilVisible(find.byKey(const ValueKey('smart-search-result-11')), -250, scrollable: list);
    expect(find.byKey(const ValueKey('smart-search-result-11')), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('smart-search-result-12')), 250, scrollable: list);
    expect(find.byKey(const ValueKey('smart-search-result-12')), findsOneWidget);
    expect(find.byType(AppRefreshStatus), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

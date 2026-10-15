import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:real_estate_mobile/core/platform/voice_input.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/core/widgets/app_components.dart';
import 'package:real_estate_mobile/core/widgets/ebroker_property_card.dart';
import 'package:real_estate_mobile/core/widgets/property_card_gallery.dart';
import 'package:real_estate_mobile/features/discovery/data/ai_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_repository.dart';
import 'package:real_estate_mobile/features/discovery/presentation/assisted_search_screen.dart';
import 'package:real_estate_mobile/features/discovery/presentation/marketplace_home_screen.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_ai_sheet.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_question_section.dart';
import 'support/wave3_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('voice transcript updates the same text search context and retains place and purpose', (tester) async {
    final ai = Wave3AiFake(), voice = Wave3VoiceFake(), properties = Wave3PropertiesFake();
    await tester.pumpWidget(ProviderScope(overrides: [aiRepositoryProvider.overrideWithValue(ai),
      voiceInputProvider.overrideWithValue(voice), propertyRepositoryProvider.overrideWithValue(properties)],
      child: MaterialApp(theme: AppTheme.light, home: const AssistedSearchScreen())));
    await tester.enterText(find.byKey(const ValueKey('smart-search-description')), 'شقة إيجار في صنعاء');
    await tester.tap(find.byKey(const ValueKey('smart-search-send'))); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('smart-search-voice'))); await tester.pump();
    await tester.tap(find.byKey(const ValueKey('voice-finish'))); await tester.pumpAndSettle();
    expect(voice.calls, 1); expect(ai.requests.last.filters['search'], 'صنعاء'); expect(ai.requests.last.filters['purpose'], 'rent');
    expect(properties.queries.last.filters['max_monthly_rent'], 100000);
    expect(find.byKey(const ValueKey('smart-chip-type')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gallery pages update the RTL indicator while taps, favorite action and vertical scrolling remain usable', (tester) async {
    var opens = 0, favorites = 0;
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: Directionality(textDirection: TextDirection.rtl,
      child: Scaffold(body: ListView(children: [EbrokerPropertyHorizontalCard(imageFirst: true,
        title: 'شقة مصورة', price: '100000', currency: 'YER', imageUrl: 'https://example.invalid/one.jpg',
        imageUrls: const ['https://example.invalid/one.jpg', 'https://example.invalid/two.jpg'], isSpotlight: true,
        trailing: IconButton(key: const ValueKey('gallery-favorite'), icon: const Icon(Icons.favorite_border), onPressed: () => favorites++),
        onTap: () => opens++), const SizedBox(height: 1000), const Text('نهاية القائمة')])))));
    await tester.pumpAndSettle();
    final pager = find.byKey(const ValueKey('property-card-gallery'));
    expect(find.byType(PropertyCardGallery), findsOneWidget); expect(find.byKey(const ValueKey('photo-dot-2')), findsNothing);
    await tester.drag(pager, Offset(tester.getSize(pager).width * .75, 0)); await tester.pumpAndSettle();
    expect(tester.widget<Container>(find.byKey(const ValueKey('photo-dot-1'))).constraints!.maxWidth, 12);
    expect(opens, 0); await tester.tap(pager); await tester.pumpAndSettle(); expect(opens, 1);
    await tester.tap(find.byKey(const ValueKey('gallery-favorite'))); await tester.pumpAndSettle(); expect(favorites, 1); expect(opens, 1);
    await tester.drag(pager, const Offset(0, -250)); await tester.pumpAndSettle();
    expect(tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('field proposals require review and apply only the checked fields', (tester) async {
    Map<String, dynamic>? applied;
    await tester.pumpWidget(ProviderScope(overrides: [aiRepositoryProvider.overrideWithValue(Wave3AiFake())],
      child: MaterialApp(theme: AppTheme.light, home: Builder(builder: (context) => Scaffold(body: TextButton(onPressed: () async {
        applied = await AppBottomSheet.show<Map<String, dynamic>>(context, builder: (_) => const ListingAiSheet(facts: {'type': 'apartment'}));
      }, child: const Text('المساعد')))))));
    await tester.tap(find.text('المساعد')); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'أربع غرف ومصعد');
    await tester.tap(find.text('اقتراح الحقول')); await tester.pumpAndSettle(); expect(applied, isNull);
    final elevator = find.widgetWithText(CheckboxListTile, 'المصعد'); await tester.ensureVisible(elevator); await tester.pumpAndSettle(); await tester.tap(elevator); await tester.pumpAndSettle();
    final apply = find.text('تطبيق المواصفات المحددة'); await tester.ensureVisible(apply); await tester.pumpAndSettle(); await tester.tap(apply); await tester.pumpAndSettle();
    expect(applied, {'bedrooms': 4}); expect(tester.takeException(), isNull);
  });

  testWidgets('missing listing information is stated clearly and questions do not create a conversation', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [aiRepositoryProvider.overrideWithValue(Wave3AiFake())],
      child: MaterialApp(theme: AppTheme.light, home: const Scaffold(body: SingleChildScrollView(child: PropertyQuestionSection(propertyId: 11))))));
    await tester.enterText(find.byType(TextField), 'هل يوجد مصعد؟'); await tester.tap(find.text('عرض الإجابة')); await tester.pumpAndSettle();
    expect(find.text('هذه المعلومة غير مذكورة في الإعلان.'), findsOneWidget); expect(tester.takeException(), isNull);
  });

  testWidgets('home location chooser changes the actual feed and map destination to the selected region', (tester) async {
    final feed = Wave3MarketplaceFake(onFeed: (q) async => MarketplaceFeed(label: q.governorate ?? 'صنعاء',
      governorate: q.governorate ?? 'صنعاء', sections: {'latest': [wave3Property(11)]}));
    final router = GoRouter(routes: [GoRoute(path: '/', builder: (_, __) => const MarketplaceHomeScreen()),
      GoRoute(path: '/property-market', builder: (_, __) => const Scaffold(body: Text('الخريطة')))]); addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [marketplaceRepositoryProvider.overrideWithValue(feed), homeLocationAttemptedProvider.overrideWith((_) => true)],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router)));
    await tester.pumpAndSettle(); expect(feed.queries.single.device, false); expect(feed.queries.single.governorate, isNull);
    await tester.tap(find.text('صنعاء')); await tester.pumpAndSettle(); await tester.tap(find.text('تعز')); await tester.pumpAndSettle();
    expect(feed.queries.last.governorate, 'تعز'); expect(feed.queries.last.device, false);
    await tester.tap(find.byKey(const ValueKey('home-map'))); await tester.pumpAndSettle();
    expect(router.state.uri.path, '/property-market'); expect(router.state.uri.queryParameters['lat'], '13.58'); expect(router.state.uri.queryParameters['lon'], '44.02');
    expect(tester.takeException(), isNull);
  });
}

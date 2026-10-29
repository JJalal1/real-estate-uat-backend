import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:real_estate_mobile/core/network/api_client.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_search_session.dart';
import 'package:real_estate_mobile/features/discovery/data/published_listing_suggestions.dart';
import 'package:real_estate_mobile/features/discovery/domain/smart_search_filters.dart';
import 'package:real_estate_mobile/features/discovery/presentation/marketplace_home_screen.dart';
import 'package:real_estate_mobile/features/discovery/presentation/marketplace_search_screen.dart';
import 'package:real_estate_mobile/features/discovery/presentation/marketplace_search_panel.dart';
import 'package:real_estate_mobile/features/map/presentation/map_screen.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'support/owner_ux_fixtures.dart';

PropertySummary row(int id, {String title = 'شقة منشورة في حدة', String type = 'apartment', String purpose = 'sale'}) => PropertySummary(
  id: id, title: '$title $id', type: type, purpose: purpose, price: 45000000,
  monthlyRent: purpose == 'rent' ? 180000 : null, currency: 'YER', latitude: 15.36,
  longitude: 44.19, address: 'صنعاء، حدة', bedrooms: type == 'land' ? null : 3);
typedef PageResult = (List<PropertySummary>, bool);
class Listings implements PropertyRepository {
  final calls = <Map<String, dynamic>>[];
  final transfers = <CancelToken?>[];
  Future<PageResult> Function(Map<String, dynamic>, int)? respond;
  @override
  Future<PageResult> searchListings(Map<String, dynamic> filters, {int page = 1, CancelToken? cancelToken, bool refresh = false}) async {
    calls.add({...filters, 'page': page}); transfers.add(cancelToken);
    if (respond != null) return respond!(filters, page);
    return (List.generate(12, (i) => row(i+1, type: filters['type']?.toString() ?? 'apartment',
      purpose: filters['purpose']?.toString() ?? 'sale')), false);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}

Dio suggestionsDio(List<Map<String, dynamic>> calls, {Completer<void>? delayed}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://synthetic.example/api'));
  dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) async {
    calls.add(Map.of(options.queryParameters));
    if (delayed != null) await delayed.future;
    handler.resolve(Response(requestOptions: options, statusCode: 200, data: {'data': [
      for (var i=1;i<=9;i++) {'id': i, 'title': 'شقة منشورة $i', 'status': i==9 ? 'draft' : 'published',
        'type': 'apartment', 'purpose': 'sale', 'price': 45000000, 'currency': 'YER',
        'address': 'صنعاء، حدة', 'latitude': 15.36, 'longitude': 44.19},
    ]}));
  }));
  addTearDown(() => dio.close(force: true)); return dio;
}

GoRouter router() => GoRouter(routes: [
  GoRoute(path: '/', builder: (_, __) => const MarketplaceHomeScreen()),
  GoRoute(path: '/marketplace-search', builder: (_, __) => const MarketplaceSearchScreen()),
  GoRoute(path: '/marketplace-search-map', builder: (_, __) => const MarketplaceSearchMapScreen()),
  GoRoute(path: '/properties/:id', builder: (context, state) => Scaffold(appBar: AppBar(),
    body: Text('تفاصيل العقار ${state.pathParameters['id']}'))),
]);

void main() {
  setUpAll(loadUxFixtures);
  test('S07 S08 one literal submit and no implicit GPS or AI interpretation', () async {
    final properties = Listings(), scope = uxContainer(extra: [propertyRepositoryProvider.overrideWithValue(properties)]);
    final controller = scope.read(marketplaceSearchControllerProvider.notifier);
    controller.edit('شقة في حدة');
    await controller.submit(); await controller.submit();
    expect(properties.calls, hasLength(1));
    expect(properties.calls.single['search'], 'شقة في حدة');
    expect(properties.calls.single['governorate'], 'صنعاء');
    expect(properties.calls.single.containsKey('latitude'), isFalse);
    expect(scope.read(marketplaceSearchControllerProvider).draftQuery, 'شقة في حدة');
  });

  test('S21 late ignored transport cannot overwrite newer Home search', () async {
    final first = Completer<PageResult>(), second = Completer<PageResult>();
    final properties = Listings()..respond = (filters, _) => filters['search']=='ش' ? first.future : second.future;
    final scope = uxContainer(extra: [propertyRepositoryProvider.overrideWithValue(properties)]);
    final controller = scope.read(marketplaceSearchControllerProvider.notifier);
    controller.edit('ش'); final old = controller.submit();
    controller.edit('ج'); final fresh = controller.submit();
    expect(properties.transfers.first!.isCancelled, isTrue);
    second.complete(([row(2, title:'جامع')], false)); await fresh;
    first.complete(([row(1)], false)); await old;
    expect(scope.read(homeSearchResultsProvider).rows.single.id, 2);
    expect(scope.read(marketplaceSearchControllerProvider).submittedQuery, 'ج');
  });

  test('S14 S17 S20 map viewport and filters keep independent Home spatial snapshot', () async {
    final properties = Listings(), scope = uxContainer(extra: [propertyRepositoryProvider.overrideWithValue(properties)]);
    final controller = scope.read(marketplaceSearchControllerProvider.notifier);
    controller.edit('شقة'); await controller.submit(); controller.enterMap(); await Future<void>.delayed(Duration.zero);
    scope.read(marketplaceMapResultsProvider.notifier).updateViewport(south:14,west:43,north:16,east:45);
    await Future<void>.delayed(Duration.zero);
    expect(scope.read(homeSearchResultsProvider).filters.values['governorate'], 'صنعاء');
    expect(scope.read(homeSearchResultsProvider).filters.values.containsKey('south'), isFalse);
    expect(scope.read(marketplaceMapResultsProvider).filters.values['south'], 14);
    controller.setChoice('purpose', 'rent'); await Future<void>.delayed(Duration.zero);
    expect(scope.read(homeSearchResultsProvider).filters.values['purpose'], 'rent');
    expect(scope.read(marketplaceMapResultsProvider).filters.values['purpose'], 'rent');
    expect(scope.read(marketplaceMapResultsProvider).filters.values['south'], 14);
    expect(scope.read(homeSearchResultsProvider).filters.values['governorate'], 'صنعاء');
    final callsBeforeReturn = properties.calls.length;
    controller.leaveMap(); controller.enterMap(); await Future<void>.delayed(Duration.zero);
    expect(scope.read(marketplaceMapResultsProvider).filters.values['south'], 14);
    expect(scope.read(marketplaceMapResultsProvider).filters.values['west'], 43);
    expect(scope.read(homeSearchResultsProvider).filters.values.containsKey('south'), isFalse);
    expect(properties.calls, hasLength(callsBeforeReturn));
  });

  test('S10 S14 S20 entering map applies edited text to both existing result snapshots once', () async {
    final properties = Listings()..respond = (filters, _) async => ([
      row(filters['search'] == 'ش' ? 1 : 2, title: filters['search'].toString()),
    ], false);
    final scope = uxContainer(extra: [propertyRepositoryProvider.overrideWithValue(properties)]);
    final controller = scope.read(marketplaceSearchControllerProvider.notifier);
    controller.edit('ش'); await controller.submit();
    controller.edit('ج'); controller.enterMap(); await Future<void>.delayed(Duration.zero);
    expect(properties.calls, hasLength(3));
    expect(properties.calls.skip(1).every((call) => call['search'] == 'ج'), isTrue);
    expect(scope.read(homeSearchResultsProvider).filters.values['search'], 'ج');
    expect(scope.read(homeSearchResultsProvider).rows.single.id, 2);
    expect(scope.read(marketplaceMapResultsProvider).filters.values['search'], 'ج');
    expect(scope.read(marketplaceMapResultsProvider).rows.single.id, 2);
    controller.leaveMap();
    expect(scope.read(marketplaceSearchControllerProvider).draftQuery, 'ج');
    expect(scope.read(marketplaceSearchControllerProvider).submittedQuery, 'ج');
  });

  test('S13 land removes housing criteria and declared-use keyword remains visible and reversible', () async {
    final scope = uxContainer(extra: [propertyRepositoryProvider.overrideWithValue(Listings())]);
    final controller = scope.read(marketplaceSearchControllerProvider.notifier);
    controller.edit('أرض'); controller.applyFilters(SmartSearchFilters.fromMap({'type':'land','min_bedrooms':3,'min_area_m2':100}));
    controller.setLandUse('تجاري'); await Future<void>.delayed(Duration.zero);
    expect(scope.read(homeSearchResultsProvider).filters.values.containsKey('min_bedrooms'), isFalse);
    expect(scope.read(homeSearchResultsProvider).filters.values['search'], 'أرض تجاري');
    expect(scope.read(marketplaceSearchControllerProvider).draftQuery, 'أرض');
    controller.setChoice('type', 'apartment'); await Future<void>.delayed(Duration.zero);
    expect(scope.read(marketplaceSearchControllerProvider).landUse, isEmpty);
    expect(scope.read(homeSearchResultsProvider).filters.values['search'], 'أرض');
  });

  test('S22 retain rows on 503, retry exact failed page and deduplicate pagination', () async {
    var fail = false;
    final properties = Listings()..respond = (_, page) async {
      if (fail) {
        throw DioException(requestOptions: RequestOptions(path:'/properties'),
          response: Response(requestOptions: RequestOptions(path:'/properties'),statusCode:503),type:DioExceptionType.badResponse);
      }
      return ([row(1), if(page==2) row(2)], page==1);
    };
    final scope = uxContainer(extra: [propertyRepositoryProvider.overrideWithValue(properties)]);
    final controller = scope.read(marketplaceSearchControllerProvider.notifier);
    controller.edit('ش'); await controller.submit();
    final engine = scope.read(homeSearchResultsProvider.notifier);
    fail=true; await engine.search(more:true);
    expect(scope.read(homeSearchResultsProvider).rows.single.id, 1);
    expect(scope.read(homeSearchResultsProvider).resultsError, isNotNull);
    fail=false; await engine.retryResults();
    expect(properties.calls.map((c)=>c['page']), [1,2,2]);
    expect(scope.read(homeSearchResultsProvider).rows.map((r)=>r.id), [1,2]);
    await engine.search(more:true); expect(properties.calls, hasLength(3));
  });

  test('S02 first-character public suggestions are bounded, scoped and contain actual listings', () async {
    final calls = <Map<String,dynamic>>[], dio = suggestionsDio(calls);
    final repository = PublishedListingSuggestions(dio);
    final key = publishedSuggestionKey(SmartSearchFilters.fromMap({'search':'ش','governorate':'صنعاء','purpose':'sale','type':'apartment'}));
    final results = await repository.load(key,CancelToken());
    expect(calls.single, containsPair('search','ش')); expect(calls.single['per_page'],6);
    expect(calls.single['governorate'],'صنعاء'); expect(calls.single['type'],'apartment');
    expect(results,hasLength(6)); expect(results.every((r)=>r.status=='published'),isTrue);
    expect(repository.cached(key).map((r)=>r.id),results.map((r)=>r.id));
  });

  test('S21 disposed suggestions do not seed a reusable cache', () async {
    final delayed=Completer<void>(), calls=<Map<String,dynamic>>[], transfer=CancelToken();
    final repository=PublishedListingSuggestions(suggestionsDio(calls,delayed:delayed));
    final key=publishedSuggestionKey(SmartSearchFilters.fromMap({'search':'ش'}));
    final load=repository.load(key,transfer);
    final assertion=expectLater(load,throwsA(isA<DioException>()));
    await Future<void>.delayed(const Duration(milliseconds:10)); transfer.cancel(); delayed.complete();
    await assertion; expect(repository.cached(key),isEmpty);
  });

  test('S23 account transition invalidates typed search, map rows and public suggestion memory', () async {
    final auth=UxAuth(uxUser(id:1)), calls=<Map<String,dynamic>>[];
    final scope=uxContainer(auth:auth,extra:[propertyRepositoryProvider.overrideWithValue(Listings()),dioProvider.overrideWithValue(suggestionsDio(calls))]);
    await scope.read(authControllerProvider.future);
    final controller=scope.read(marketplaceSearchControllerProvider.notifier);
    controller.edit('ش'); await controller.submit(); controller.enterMap();
    final key=publishedSuggestionKey(SmartSearchFilters.fromMap({'search':'ش'}));
    await scope.read(publishedListingSuggestionsRepositoryProvider).load(key,CancelToken());
    auth.change(uxUser(id:2));
    expect(scope.read(marketplaceSearchControllerProvider).draftQuery,isEmpty);
    expect(scope.read(homeSearchResultsProvider).rows,isEmpty);
    expect(scope.read(marketplaceMapResultsProvider).rows,isEmpty);
    expect(scope.read(publishedListingSuggestionsRepositoryProvider).cached(key),isEmpty);
  });

  for(final keyboard in [true,false]) {
    testWidgets('S01 S02 S06 S07 S08 S09 S10 ${keyboard?'IME':'button'} uses standalone search and restores a selected listing', (tester) async {
      final properties=Listings(),calls=<Map<String,dynamic>>[],boundary=GlobalKey();
      final scope=uxContainer(extra:[propertyRepositoryProvider.overrideWithValue(properties),dioProvider.overrideWithValue(suggestionsDio(calls))]);
      final navigation=router(); addTearDown(navigation.dispose);
      await pumpUx(tester,scope,const SizedBox(),router:navigation,boundary:boundary);
      final input=find.byKey(const ValueKey('home-search'));
      await tester.tap(input); await tester.pumpAndSettle(); await tester.enterText(input,'ش'); await uxFrames(tester);
      expect(find.byType(MapScreen),findsNothing);
      expect(tester.widget<TextField>(input).readOnly,isFalse);
      expect(tester.widget<TextField>(input).maxLines,1);
      expect(tester.widget<TextField>(input).textInputAction,TextInputAction.search);
      expect(find.byKey(const ValueKey('published-suggestion-1')),findsOneWidget);
      if(keyboard) await uxPreview(tester,boundary,'w2-A-home-suggestions');
      await tester.tap(find.byKey(const ValueKey('published-suggestion-1'))); await tester.pumpAndSettle();
      expect(find.text('تفاصيل العقار 1'),findsOneWidget);
      navigation.pop(); await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text,'ش');
      expect(find.byKey(const ValueKey('published-suggestion-1')),findsOneWidget);
      await tester.tap(input);
      if(keyboard) { await tester.testTextInput.receiveAction(TextInputAction.search); }
      else { await tester.tap(find.byKey(const ValueKey('published-search-submit'))); }
      await tester.pumpAndSettle();
      expect(properties.calls,hasLength(1));
      expect(find.byKey(const ValueKey('home-result-1')),findsOneWidget);
      expect(find.byType(MapScreen),findsNothing);
      expect(tester.widget<TextField>(input).controller!.text,'ش');
      if(keyboard) await uxPreview(tester,boundary,'w2-B-home-results');
      expect(tester.takeException(),isNull); await closeUx(tester);
    });
  }

  testWidgets('S14-S20 map suggestions, shared snapshot, sheet drag and Home scroll restore', (tester) async {
    final properties=Listings(),calls=<Map<String,dynamic>>[],boundary=GlobalKey();
    var pins=<int>[]; late void Function(int) select; late void Function(double,double,double,double) pan;
    final scope=uxContainer(extra:[propertyRepositoryProvider.overrideWithValue(properties),dioProvider.overrideWithValue(suggestionsDio(calls)),
      sharedSearchMapBuilderProvider.overrideWithValue((context,rows,pick,viewport){
        pins=rows.map((r)=>r.id).toList(); select=pick; pan=viewport;
        return ColoredBox(key:const ValueKey('w2-native-canvas'),color:Colors.teal.shade50,
          child:const Center(child:Text('خريطة اختبار اصطناعية')));
      }),
    ]);
    final navigation=router(); addTearDown(navigation.dispose);
    await pumpUx(tester,scope,const SizedBox(),router:navigation,boundary:boundary);
    await tester.tap(find.byKey(const ValueKey('home-search'))); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('home-search')),'ش');
    await tester.tap(find.byKey(const ValueKey('published-search-submit'))); await tester.pumpAndSettle();
    final homeScroll=tester.widget<CustomScrollView>(find.byKey(const PageStorageKey('home-search-results'))).controller!;
    final open=tester.widget<TextButton>(find.byKey(const ValueKey('home-search-map'))).onPressed!;
    homeScroll.jumpTo(150); await tester.pump();
    // The entry lives at the top of the result sliver. Invoke its real callback
    // without altering the saved scroll position to make the restoration check exact.
    open(); await tester.pumpAndSettle();
    expect(scope.read(marketplaceMapResultsProvider).filters.values['search'],'ش');
    final element=tester.element(find.byKey(const ValueKey('w2-native-canvas')));
    await tester.enterText(find.byKey(const ValueKey('map-published-search-input')),'شقة'); await uxFrames(tester);
    expect(find.byKey(const ValueKey('published-suggestion-1')),findsOneWidget);
    await uxPreview(tester,boundary,'w2-C-map-suggestions');
    await tester.testTextInput.receiveAction(TextInputAction.search); await tester.pumpAndSettle();
    expect(scope.read(homeSearchResultsProvider).filters.values['search'],'شقة');
    expect(pins,scope.read(marketplaceMapResultsProvider).rows.map((r)=>r.id));
    await uxPreview(tester,boundary,'w2-D-map-results');
    select(5); await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('map-result-5')),findsOneWidget);
    await tester.drag(find.byKey(const ValueKey('map-results-handle')),const Offset(0,-400)); await tester.pumpAndSettle();
    expect(tester.element(find.byKey(const ValueKey('w2-native-canvas'))),same(element));
    final sheet=tester.widget<DraggableScrollableSheet>(find.byKey(const ValueKey('map-results-sheet')));
    expect(sheet.controller!.size,greaterThan(.5));
    final toolbar = tester.getRect(find.byKey(const ValueKey('marketplace-search-toolbar')));
    final sheetBounds = tester.getRect(find.byKey(const ValueKey('map-results-list')));
    expect(sheetBounds.top - toolbar.bottom, greaterThanOrEqualTo(70));
    await uxPreview(tester,boundary,'w2-E-map-expanded');
    pan(15,44,16,45); await tester.pumpAndSettle();
    expect(scope.read(homeSearchResultsProvider).filters.values.containsKey('south'),isFalse);
    expect(scope.read(marketplaceMapResultsProvider).filters.values['south'],15);
    navigation.pop(); await tester.pumpAndSettle();
    expect(homeScroll.offset,150);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('home-search'))).controller!.text,'شقة');
    expect(tester.takeException(),isNull); await closeUx(tester);
  });

  for(final dark in [false,true]) {
    testWidgets('S11 S12 S13 S24 small RTL large text and keyboard theme $dark', (tester) async {
      final scope=uxContainer(extra:[propertyRepositoryProvider.overrideWithValue(Listings())]);
      await pumpUx(tester,scope,const MarketplaceSearchScreen(),size:const Size(320,568),scale:2.4,dark:dark);
      final controller=scope.read(marketplaceSearchControllerProvider.notifier);
      controller.edit(''); await controller.submit(); await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('published-type-land')));
      await tester.tap(find.byKey(const ValueKey('published-type-land'))); await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('published-filter-rooms')),findsNothing);
      expect(find.byKey(const ValueKey('published-filter-land-use')),findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>),findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('home-search'))); await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-search'))); await tester.enterText(find.byKey(const ValueKey('home-search')),'ش\nق');
      expect(tester.widget<TextField>(find.byKey(const ValueKey('home-search'))).controller!.text, 'شق');
      tester.view.viewInsets=const FakeViewPadding(bottom:200); await uxFrames(tester);
      addTearDown(tester.view.resetViewInsets);
      await tester.ensureVisible(find.byKey(const ValueKey('published-search-submit')));
      expect(tester.getRect(find.byKey(const ValueKey('published-search-submit'))).bottom,lessThanOrEqualTo(368));
      expect(tester.takeException(),isNull); await closeUx(tester);
    });
  }
  for (final scale in [1.0, 2.4]) {
    testWidgets('S18 expanded map list reserves visible map on 320px and text $scale', (tester) async {
      final scope = uxContainer(extra: [propertyRepositoryProvider.overrideWithValue(Listings()),
        sharedSearchMapBuilderProvider.overrideWithValue((context, rows, pick, viewport) =>
          const ColoredBox(key: ValueKey('small-map-canvas'), color: Colors.teal)),
      ]);
      await pumpUx(tester, scope, const MarketplaceSearchMapScreen(), size: const Size(320,568), scale: scale);
      await tester.pumpAndSettle();
      final canvas = tester.element(find.byKey(const ValueKey('small-map-canvas')));
      await tester.drag(find.byKey(const ValueKey('map-results-handle')), const Offset(0,-500)); await tester.pumpAndSettle();
      final toolbar = tester.getRect(find.byKey(const ValueKey('marketplace-search-toolbar')));
      final list = tester.getRect(find.byKey(const ValueKey('map-results-list')));
      expect(list.top - toolbar.bottom, greaterThanOrEqualTo(70));
      expect(tester.element(find.byKey(const ValueKey('small-map-canvas'))), same(canvas));
      expect(tester.takeException(), isNull); await closeUx(tester);
    });
  }
}

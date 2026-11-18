import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/ai_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/smart_search_session.dart';
import 'package:real_estate_mobile/features/discovery/domain/smart_search_filters.dart';
import 'package:real_estate_mobile/features/discovery/presentation/assisted_search_screen.dart';
import 'package:real_estate_mobile/features/discovery/presentation/search_result_pagination.dart';
import 'package:real_estate_mobile/features/map/domain/property_marker_cluster.dart';
import 'package:real_estate_mobile/features/map/presentation/map_screen.dart';
import 'package:real_estate_mobile/features/map/presentation/property_map_results_sheet.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/discovery_match.dart';
import 'package:real_estate_mobile/features/properties/domain/property_marker.dart';
import 'package:real_estate_mobile/features/properties/domain/saved_property_search.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_summary_card.dart';

import 'support/owner_ux_fixtures.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions) respond;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) => respond(options);
  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _row(int id, {bool nearby = false, int? misses, int? metres}) => {
  'id':id,'title':'عقار اختبار $id','purpose':'rent','type':'house','price':100000,'currency':'YER',
  'latitude':15.37,'longitude':44.19,'discovery_match':{'kind':nearby?'nearby':'exact',
    'reasons':nearby?[{'field':'location','message':'خارج المنطقة المرسومة'}]:[],
    'distance_m':nearby?80:null,'distance_reference':nearby?'drawn_boundary':null,
    'criteria_misses':misses ?? (nearby ? 1 : 0),'rank_distance_m':metres ?? (nearby ? 80 : 0)},
};
ResponseBody _body(List<Map<String,dynamic>> rows, {int page=1,int last=1,bool acknowledge=true, String contract = '1', (int, int)? totals}) {
  final exact = totals?.$1 ?? (last > 1 ? 20 : rows.where((row) => (row['discovery_match'] as Map)['kind'] == 'exact').length);
  final alternatives = totals?.$2 ?? (last > 1 ? 1 : rows.length - exact);
  return ResponseBody.fromString(jsonEncode({'data': rows, 'meta': {
    'current_page': page, 'last_page': last, 'total': exact + alternatives, 'exact_total': exact, 'alternative_total': alternatives,
  }}), 200, headers: {
    'content-type': ['application/json'], 'x-aqer-filter-contract': ['2'], if (acknowledge) 'x-aqer-ranked-contract': [contract],
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadUxFixtures);

  test('classification retains internal reasons, grade and real distances with legacy compatibility', () {
    final match=DiscoveryMatch.fromJson(_row(2,nearby:true)['discovery_match'])!;
    expect(match.nearby,isTrue);
    expect(match.reasons,['خارج المنطقة المرسومة']);
    expect(match.distanceMetres,80);
    expect(match.distanceReference,'drawn_boundary');
    expect(match.criteriaMisses,1);
    expect(match.rankDistanceMetres,80);
    final geographyOnly = DiscoveryMatch.fromJson(_row(3, nearby: true, misses: 0)['discovery_match'])!;
    expect(geographyOnly.nearby, isTrue);
    expect(geographyOnly.criteriaMisses, 0);
    expect(geographyOnly.reasons, ['خارج المنطقة المرسومة']);
    final old=DiscoveryMatch.fromJson({'kind':'exact','reasons':[]})!;
    expect(old.criteriaMisses,isNull);
    expect(old.rankDistanceMetres,isNull);
    expect(DiscoveryMatch.fromJson(null),isNull);
    expect(()=>DiscoveryMatch.fromJson({'kind':'nearby','reasons':[]}),throwsFormatException);
    expect(()=>DiscoveryMatch.fromJson({'kind':'exact','reasons':[],'distance_m':-1}),throwsFormatException);
    expect(()=>DiscoveryMatch.fromJson({'kind':'exact','reasons':[],'criteria_misses':1}),throwsFormatException);
    expect(()=>DiscoveryMatch.fromJson(_row(4, nearby: true, misses: -1)['discovery_match']), throwsFormatException);
    expect(()=>DiscoveryMatch.fromJson({'kind':'exact','reasons':[],'rank_distance_m':double.nan}),throwsFormatException);
  });

  test('co-located exact and nearby units remain visible as separate counts at every zoom', () async {
    final rows=[PropertyMarker.fromJson(_row(1)),PropertyMarker.fromJson(_row(2)),PropertyMarker.fromJson(_row(3,nearby:true))];
    for (final zoom in [11.0, 16.0, 19.0]) {
      final clusters=clusterPropertyMarkers(rows,zoom:zoom,selectedPropertyId:3);
      expect(clusters,hasLength(1));
      expect(clusters.single.items.map((p)=>p.id).toSet(),{1,2,3});
      expect(clusters.single.exactCount,2);
      expect(clusters.single.nearbyCount,1);
      expect(clusters.single.latitude,closeTo(15.37,1e-9));
      expect(clusters.single.longitude,closeTo(44.19,1e-9));
    }
    expect(mapPropertyClusterLabel(3,nearbyCount:1),'2 + ≈1');
    expect(mapPropertyClusterImageName(3,nearbyCount:1),isNot(mapPropertyClusterImageName(3)));
    final bytes=await renderMapPropertyClusterImage(3,nearbyCount:1);
    final codec=await ui.instantiateImageCodec(bytes);
    final frame=await codec.getNextFrame();
    expect(frame.image.width,greaterThan(frame.image.height));
    frame.image.dispose();codec.dispose();
    await Directory('phase04-proof').create(recursive:true);
    await File('phase04-proof/mixed-cluster-2-exact-1-nearby.png').writeAsBytes(bytes);
  });

  test('ranked map does not silently lose loaded exact results or alternatives after marker 250', () {
    final rows=List.generate(300,(index)=>PropertyMarker.fromJson(_row(index+1)));
    rows.add(PropertyMarker.fromJson(_row(301,nearby:true)));
    final visible=propertyMarkersForAnnotations(rows);
    expect(visible,hasLength(301));
    expect(visible.last.discoveryMatch!.nearby,isTrue);
    final clusters=clusterPropertyMarkers(visible,zoom:19);
    expect(clusters.single.exactCount,300);
    expect(clusters.single.nearbyCount,1);
    expect(clusters.single.items.map((p)=>p.id).toSet(),rows.map((p)=>p.id).toSet());
  });

  test('ranked repository requests v2 on every page, accepts v1 and requires a ranked response', () async {
    final requests=<RequestOptions>[];
    final dio=Dio(BaseOptions(baseUrl:'https://example.invalid/api'));
    dio.httpClientAdapter=_Adapter((q) async {requests.add(q);return _body([_row(q.queryParameters['page'] as int,nearby:q.queryParameters['page']==2)],page:q.queryParameters['page'] as int,last:2);});
    final repo=PropertyRepository(dio,AuthRepository(dio),rankedDiscovery:true);
    final filters={'purpose':'rent','max_monthly_rent':100000,'area_polygon':'[[44,15],[45,15],[45,16],[44,15]]'};
    await repo.searchListings(filters);
    final next=await repo.searchListings(filters,page:2);
    expect(next.$1.single.discoveryMatch!.nearby,isTrue);
    for(final request in requests) {
      expect(request.queryParameters['ranked_search'],1);
      expect(request.queryParameters['ranking_version'],2);
      for(final entry in filters.entries) {expect(request.queryParameters[entry.key],entry.value);}
    }
    dio.httpClientAdapter=_Adapter((_) async => _body([],acknowledge:false));
    await expectLater(repo.searchListings({'search':'another'}),throwsStateError);
    dio.close(force:true);
  });

  test('network failure stays an error and never becomes an empty successful ranked page', () async {
    final dio=Dio(BaseOptions(baseUrl:'https://example.invalid/api'));
    dio.httpClientAdapter=_Adapter((_) async => ResponseBody.fromString('{"message":"unavailable"}',503,headers:{'content-type':['application/json']}));
    final repo=PropertyRepository(dio,AuthRepository(dio),rankedDiscovery:true);
    await expectLater(repo.searchListings({'search':'سنعا'}),throwsA(isA<DioException>()));
    dio.httpClientAdapter=_Adapter((_) async => ResponseBody.fromString('{"data":[],"meta":{}}',200,
      headers:{'content-type':['application/json'],'x-aqer-filter-contract':['2'],'x-aqer-ranked-contract':['1']}));
    await expectLater(repo.searchListings({'search':'سنعا'}),throwsFormatException);
    dio.close(force:true);
  });

  test('changing query fences late responses while keeping the newest match classification', () async {
    final old=Completer<ResponseBody>();
    final dio=Dio(BaseOptions(baseUrl:'https://example.invalid/api'));
    dio.httpClientAdapter=_Adapter((q) async => q.queryParameters['search']=='قديم' ? old.future : _body([_row(9,nearby:true)]));
    final session=SmartSearchSession(AiRepository(dio,AuthRepository(dio)),PropertyRepository(dio,AuthRepository(dio),rankedDiscovery:true));
    final first=session.replaceManually(SmartSearchFilters.fromMap({'search':'قديم','purpose':'rent'}));
    await Future<void>.delayed(Duration.zero);
    await session.replaceManually(SmartSearchFilters.fromMap({'search':'سنعا','purpose':'rent'}));
    old.complete(_body([_row(1)]));
    await first;
    expect(session.snapshot.rows.single.id,9);
    expect(session.snapshot.rows.single.discoveryMatch!.nearby,isTrue);
    session.dispose();dio.close(force:true);
  });

  for (final startInMap in [false, true]) {
    testWidgets('ranked pages load on scroll and the list and drawer share their order (map=$startInMap)', (tester) async {
      final pages = [
        [_row(44, metres: 200), _row(12, metres: 400), _row(41, metres: 800), _row(2, nearby: true, misses: 0, metres: 900)],
        [_row(20, metres: 2000), _row(9, nearby: true, metres: 100), _row(99, nearby: true, metres: 1100)],
        [_row(80, nearby: true, misses: 2, metres: 50)],
      ];
      final requests = <Map<String, dynamic>>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid/api'));
      addTearDown(() => dio.close(force: true));
      dio.httpClientAdapter = _Adapter((request) async {
        final query = Map<String, dynamic>.of(request.queryParameters);
        requests.add(query);
        final page = query['page'] as int;
        return _body(pages[page - 1], page: page, last: pages.length, totals: (4, 4), contract: '2');
      });
      final scope = uxContainer(extra: [
        propertyRepositoryProvider.overrideWithValue(PropertyRepository(dio, AuthRepository(dio), rankedDiscovery: true)),
        sharedSearchMapBuilderProvider.overrideWithValue((context, rows, select, viewport) => const ColoredBox(color: Colors.teal)),
      ]);
      const filters = {'purpose': 'rent', 'latitude': 15.37, 'longitude': 44.19, 'radius_km': 3, 'min_bedrooms': 3};
      await pumpUx(tester, scope, const AssistedSearchScreen(savedSearch: SavedPropertySearch(id: 33, name: 'ترتيب تجريبي',
        filters: filters, alertFrequency: 'off', isActive: true, matchingCount: 4)), size: const Size(412, 740));
      await tester.pumpAndSettle();

      final mapButton = find.byKey(const ValueKey('smart-search-map'));
      Future<void> openDrawer() async {
        tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
        await tester.pumpAndSettle();
        await tester.ensureVisible(mapButton);
        await tester.tap(mapButton);
        await tester.pumpAndSettle();
        await tester.drag(find.byKey(const ValueKey('map-results-handle')), const Offset(0, -535));
        await tester.pumpAndSettle();
      }
      if (startInMap) await openDrawer();
      expect(requests.map((query) => query['page']), [1]);

      final list = startInMap ? find.byKey(const ValueKey('map-results-list')) : find.byType(ListView).first;
      for (var page = 2; page <= 3; page++) {
        for (var drag = 0; drag < 16 && scope.read(smartSearchSessionProvider).page < page; drag++) {
          final bounds = tester.getRect(list);
          await tester.dragFrom(Offset(bounds.center.dx, bounds.top + bounds.height * .78), Offset(0, -bounds.height * .55));
          await tester.pumpAndSettle();
        }
        expect(scope.read(smartSearchSessionProvider).page, page);
      }
      const order = [44, 12, 41, 2, 20, 9, 99, 80];
      expect(requests, [for (var page = 1; page <= 3; page++)
        {...filters, 'page': page, 'per_page': 20, 'sort': 'latest', 'ranked_search': 1, 'ranking_version': 2},
      ]);
      if (!startInMap) await openDrawer();
      final drawer = tester.widget<PropertyMapResultsSheet>(find.byType(PropertyMapResultsSheet));
      expect(drawer.items.map((row) => row.id), order);
      expect(drawer.items.map((row) => row.discoveryMatch!.criteriaMisses), [0, 0, 0, 0, 0, 1, 1, 2]);
      expect(drawer.items.map((row) => row.discoveryMatch!.nearby), [false, false, false, true, false, true, true, true]);
      expect(drawer.items.last.discoveryMatch!.reasons, ['خارج المنطقة المرسومة']);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('map-result-80')), 260,
        scrollable: find.descendant(of: find.byKey(const ValueKey('map-results-list')), matching: find.byType(Scrollable)).first);
      expect(find.textContaining('خارج المنطقة المرسومة'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('smart-search-list')));
      await tester.pumpAndSettle();
      final delegate = tester.widget<ListView>(find.byType(ListView).first).childrenDelegate as SliverChildListDelegate;
      final cards = delegate.children.whereType<Padding>().map((padding) => padding.child).whereType<PropertySummaryCard>();
      expect(cards.map((card) => card.property.id), order);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('smart-search-result-80')), 400,
        scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('خارج المنطقة المرسومة'), findsNothing);
      expect(requests, hasLength(3), reason: 'Switching views must retain all loaded pages.');
      expect(tester.takeException(), isNull);
      await closeUx(tester);
    });
  }

  testWidgets('momentum can load the next page, and scroll restoration cannot', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var loads = 0;
    await tester.pumpWidget(MaterialApp(home: SearchResultPagination(
      onLoadMore: () => loads++,
      child: ListView.builder(controller: controller, itemExtent: 100, itemCount: 20,
        itemBuilder: (_, index) => Text('عقار $index')),
    )));
    final bottom = controller.position.maxScrollExtent;
    controller.jumpTo(bottom - 100);
    await tester.pumpAndSettle();
    expect(loads, 0);
    controller.jumpTo(bottom - 330);
    await tester.pumpAndSettle();
    await tester.fling(find.byType(ListView), const Offset(0, -75), 2400);
    await tester.pumpAndSettle();
    expect(loads, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
  });

  for(final dark in [false,true]) {
    testWidgets('ranked map sheet keeps exact order when a nearby pin is selected, RTL dark=$dark', (tester) async {
      tester.view.physicalSize=const Size(412,1000);tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
      final rows=[PropertyMarker.fromJson(_row(1)),PropertyMarker.fromJson(_row(2,nearby:true))];
      final key=GlobalKey();
      await tester.pumpWidget(MaterialApp(theme:ThemeData(brightness:dark?Brightness.dark:Brightness.light,fontFamily:'NotoSansArabic'),home:MediaQuery(
        data:MediaQueryData(size:const Size(412,1000),textScaler:TextScaler.linear(dark?2.4:1)),child:Directionality(textDirection:TextDirection.rtl,
          child:RepaintBoundary(key:key,child:Scaffold(body:PropertyMapResultsSheet(items:rows,selectedId:2,
            itemBuilder:(p)=>SizedBox(height:52,child:Text(p.title)))))))));
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(const ValueKey('map-results-handle')),const Offset(0,-650));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('عقار اختبار 1')).dy,lessThan(tester.getTopLeft(find.text('عقار اختبار 2')).dy));
      expect(find.text('نتائج قريبة من بحثك'),findsNothing);
      expect(find.textContaining('خارج المنطقة المرسومة'),findsNothing);
      expect(find.text('2 نتيجة'),findsOneWidget);
      expect(tester.takeException(),isNull);
      final boundary=key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image=await boundary.toImage();
        final bytes=(await image.toByteData(format:ui.ImageByteFormat.png))!.buffer.asUint8List();image.dispose();
        await Directory('phase04-proof').create(recursive:true);
        await File('phase04-proof/map-sheet-${dark?'dark-large':'light'}.png').writeAsBytes(bytes);
      });
      await tester.pumpWidget(const SizedBox());await tester.pumpAndSettle();
    });
  }
}

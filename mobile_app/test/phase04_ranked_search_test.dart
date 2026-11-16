import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/ai_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/smart_search_session.dart';
import 'package:real_estate_mobile/features/discovery/domain/smart_search_filters.dart';
import 'package:real_estate_mobile/features/map/domain/property_marker_cluster.dart';
import 'package:real_estate_mobile/features/map/presentation/property_map_results_sheet.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/discovery_match.dart';
import 'package:real_estate_mobile/features/properties/domain/property_marker.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions) respond;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) => respond(options);
  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _row(int id, {bool nearby = false}) => {
  'id':id,'title':'عقار اختبار $id','purpose':'rent','type':'house','price':100000,'currency':'YER',
  'latitude':15.37,'longitude':44.19,'discovery_match':{'kind':nearby?'nearby':'exact',
    'reasons':nearby?[{'field':'location','message':'خارج المنطقة المرسومة'}]:[],
    'distance_m':nearby?80:null,'distance_reference':nearby?'drawn_boundary':null},
};
ResponseBody _body(List<Map<String,dynamic>> rows, {int page=1,int last=1,bool acknowledge=true}) => ResponseBody.fromString(
  jsonEncode({'data':rows,'meta':{'current_page':page,'last_page':last}}),200,
  headers:{'content-type':['application/json'],'x-aqer-filter-contract':['2'],if(acknowledge)'x-aqer-ranked-contract':['1']});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('NotoSansArabic')..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'))).load();
  });

  test('classification validates explanations and preserves real distance reference', () {
    final match=DiscoveryMatch.fromJson(_row(2,nearby:true)['discovery_match'])!;
    expect(match.nearby,isTrue);
    expect(match.explanation,contains('80 مترًا عن حدود الرسم'));
    expect(DiscoveryMatch.fromJson(null),isNull);
    expect(()=>DiscoveryMatch.fromJson({'kind':'nearby','reasons':[]}),throwsFormatException);
    expect(()=>DiscoveryMatch.fromJson({'kind':'exact','reasons':[],'distance_m':-1}),throwsFormatException);
  });

  test('mixed classifications never share a cluster and two co-located units retain both identities', () {
    final rows=[PropertyMarker.fromJson(_row(1)),PropertyMarker.fromJson(_row(2)),PropertyMarker.fromJson(_row(3,nearby:true))];
    final clusters=clusterPropertyMarkers(rows,zoom:11);
    expect(clusters,hasLength(2));
    expect(clusters.expand((c)=>c.items).map((p)=>p.id).toSet(),{1,2,3});
    expect(clusters.singleWhere((c)=>c.items.length==2).items.every((p)=>p.discoveryMatch?.nearby==false),isTrue);
  });

  test('ranked repository carries identical filters through pages and rejects an old server', () async {
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
    dio.close(force:true);
  });

  test('changing query fences late responses while keeping the newest match classification', () async {
    final old=Completer<ResponseBody>();
    final dio=Dio(BaseOptions(baseUrl:'https://example.invalid/api'));
    dio.httpClientAdapter=_Adapter((q) async => q.queryParameters['search']=='قديم' ? old.future : _body([_row(9,nearby:true)]));
    final session=SmartSearchSession(AiRepository(dio),PropertyRepository(dio,AuthRepository(dio),rankedDiscovery:true));
    final first=session.replaceManually(SmartSearchFilters.fromMap({'search':'قديم','purpose':'rent'}));
    await Future<void>.delayed(Duration.zero);
    await session.replaceManually(SmartSearchFilters.fromMap({'search':'سنعا','purpose':'rent'}));
    old.complete(_body([_row(1)]));
    await first;
    expect(session.snapshot.rows.single.id,9);
    expect(session.snapshot.rows.single.discoveryMatch!.nearby,isTrue);
    session.dispose();dio.close(force:true);
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
      expect(find.text('نتائج قريبة من بحثك'),findsOneWidget);
      expect(find.textContaining('خارج المنطقة المرسومة'),findsOneWidget);
      expect(tester.takeException(),isNull);
      final boundary=key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image=await boundary.toImage();
      final bytes=(await image.toByteData(format:ui.ImageByteFormat.png))!.buffer.asUint8List();image.dispose();
      await tester.runAsync(() async {await Directory('phase04-proof').create(recursive:true);await File('phase04-proof/map-sheet-${dark?'dark-large':'light'}.png').writeAsBytes(bytes);});
      await tester.pumpWidget(const SizedBox());await tester.pumpAndSettle();
    });
  }
}

import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/ai_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/discovery_location.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/smart_search_session.dart';
import 'package:real_estate_mobile/features/discovery/domain/smart_search_filters.dart';
import 'package:real_estate_mobile/features/properties/domain/arabic_price_words.dart';
import 'package:real_estate_mobile/features/properties/domain/property_schema.dart';
import 'support/wave3_fakes.dart';

class MemoryLocationStore extends DiscoveryLocationStore {
  DiscoveryLocationPreferences value = const DiscoveryLocationPreferences();
  @override
  Future<DiscoveryLocationPreferences> load() async => value;
  @override
  Future<void> save(DiscoveryLocationPreferences preferences) async { value = preferences; }
}
class FakeLocationAccess extends DiscoveryLocationAccess {
  LocationPermission current = LocationPermission.denied, decision = LocationPermission.denied;
  int requests = 0, fixes = 0;
  Completer<HomeLocation>? pending;
  @override
  Future<LocationPermission> permission() async => current;
  @override
  Future<LocationPermission> requestPermission() async { requests++; return current = decision; }
  @override
  Future<HomeLocation> locate() async { fixes++; return pending?.future ?? Future.value(const HomeLocation(latitude:12.8,longitude:45.0,label:'موقعي',device:true)); }
}
class DescriptionAuth implements AuthRepository {
  String token = 'fixture-a';
  @override
  Future<Options> requiredAuthOptions() async => Options(headers:{'Authorization':'Bearer $token'});
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  test('apartment selector stops at seven while office and historical floor labels remain readable', () {
    expect(DynamicPropertySchema.floorOptionsFor('apartment').keys, ['0','1','2','3','4','5','6','7']);
    expect(DynamicPropertySchema.floorOptionsFor('office').containsKey('8'), true);
    expect(DynamicPropertySchema.floorLabel('8'), 'الثامن');
    expect(arabicRiyalAmountInWords('١٠٠٬٠٠٠'), 'مائة ألف ريال يمني');
    expect(arabicRiyalAmountInWords('100000.25'), 'مائة ألف ريال يمني وخمسة وعشرون فلس');
    expect(arabicRiyalAmountInWords('100.001'), isNull);
  });
  test('permission denial is persisted across launches and never blocks manual city selection', () async {
    final store = MemoryLocationStore(), access = FakeLocationAccess();
    var location = const HomeLocation();
    DiscoveryLocationCoordinator controller() => DiscoveryLocationCoordinator(store,access,()=>location,(next)=>location=next);
    await Future.wait([controller().initialize(), Future<void>.value()]);
    expect(access.requests,1); expect(access.fixes,0); expect(store.value.permissionResolved,true);
    await controller().initialize(); expect(access.requests,1);
    final c = controller();
    await c.selectManual(const HomeLocation(latitude:13.58,longitude:44.02,governorate:'تعز',label:'تعز',manual:true));
    location = const HomeLocation(); await controller().initialize();
    expect(location.governorate,'تعز');expect(location.manual,true);expect(access.requests,1);
  });
  test('first approved permission sets device context and a later manual choice wins a delayed fix', () async {
    final store=MemoryLocationStore(),access=FakeLocationAccess()..decision=LocationPermission.whileInUse;
    var location=const HomeLocation();
    final c=DiscoveryLocationCoordinator(store,access,()=>location,(next)=>location=next);
    await Future.wait([c.initialize(),c.initialize()]);
    expect(access.requests,1);expect(location.device,true);expect(location.latitude,12.8);
    expect(store.value.manual,isNull);
    access.pending=Completer<HomeLocation>();final pending=c.useDevice();await Future<void>.delayed(Duration.zero);
    await c.selectManual(const HomeLocation(latitude:13.58,longitude:44.02,governorate:'تعز',label:'تعز',manual:true));
    access.pending!.complete(const HomeLocation(latitude:15,longitude:44,device:true));await pending;
    expect(location.governorate,'تعز');expect(store.value.manual!.governorate,'تعز');
  });
  test('default location seeds search without restoring a prior journey and explicit cities and saved searches override it', () async {
    final ai=Wave3AiFake()..onRefine=(message,filters,revision) async => {'revision':revision,'filters':{
      ...filters,'type':'shop', if(message.contains('عدن')) 'governorate':'عدن'}};
    final properties=Wave3PropertiesFake();
    const home=HomeLocation(latitude:13.58,longitude:44.02,governorate:'تعز',manual:true);
    final session=SmartSearchSession(ai,properties,defaultLocation:()=>SmartSearchFilters.fromMap(home.searchContext));
    addTearDown(session.dispose);
    final first=session.beginJourney();expect(session.state.started,false);expect(properties.queries,isEmpty);
    await session.interpret('محل');expect(properties.queries.last.filters['latitude'],13.58);expect(properties.queries.last.filters['governorate'],'تعز');
    await session.interpret('في عدن');expect(session.state.filters.values['governorate'],'عدن');expect(session.state.filters.values.containsKey('latitude'),false);
    session.endJourney(first);await Future<void>.delayed(Duration.zero);expect(session.state.filters.values,isEmpty);
    session.beginJourney(savedFilters:SmartSearchFilters.fromMap({'governorate':'صنعاء','type':'land'}));
    expect(session.state.filters.values,{'governorate':'صنعاء','type':'land'});
  });
  test('one description request serves double taps, then a later explicit request is allowed', () async {
    final dio=Dio(),auth=DescriptionAuth(),pending=Completer<void>(),started=Completer<void>();int calls=0;
    dio.interceptors.add(InterceptorsWrapper(onRequest:(options,handler) async {
      calls++;if(!started.isCompleted)started.complete();await pending.future;handler.resolve(Response(requestOptions:options,statusCode:200,data:{'data':{'description':'وصف من الحقائق'}}));
    }));
    final ai=AiRepository(dio,auth);
    final a=ai.description({'type':'house'}),b=ai.description({'type':'house'});
    await started.future;expect(calls,1);pending.complete();await Future.wait([a,b]);
    await ai.description({'type':'house'});expect(calls,2);dio.close();
  });
  test('429 respects Retry-After across repeats and never starts an automatic retry', () async {
    final dio=Dio(),ai=AiRepository(dio,DescriptionAuth());int calls=0;
    dio.interceptors.add(InterceptorsWrapper(onRequest:(options,handler) {
      calls++;handler.reject(DioException(requestOptions:options,type:DioExceptionType.badResponse,
        response:Response(requestOptions:options,statusCode:429,headers:Headers.fromMap({'retry-after':['120']}))));
    }));
    await expectLater(ai.description({'type':'house'}),throwsA(isA<DescriptionRateLimit>()));
    await expectLater(ai.description({'type':'house'}),throwsA(isA<DescriptionRateLimit>()));
    expect(calls,1);expect(ai.descriptionRetryAt!.difference(DateTime.now()).inSeconds,greaterThanOrEqualTo(118));dio.close();
  });
  test('description coalescing never crosses authenticated sessions', () async {
    final dio=Dio(),auth=DescriptionAuth(),pending=Completer<void>(),first=Completer<void>(),second=Completer<void>();int calls=0;
    dio.interceptors.add(InterceptorsWrapper(onRequest:(options,handler) async {
      calls++;if(calls==1)first.complete();if(calls==2)second.complete();await pending.future;handler.resolve(Response(requestOptions:options,statusCode:200,data:{'data':{'description':'وصف'}}));
    }));
    final ai=AiRepository(dio,auth),a=ai.description({'type':'house'});
    await first.future;auth.token='fixture-b';final b=ai.description({'type':'house'});
    await second.future;expect(calls,2);pending.complete();await Future.wait([a,b]);dio.close();
  });
}

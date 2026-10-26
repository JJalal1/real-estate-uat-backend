import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/network/api_client.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/community/data/community_repository.dart';
import 'package:real_estate_mobile/features/community/presentation/listing_community_screen.dart';
import 'package:real_estate_mobile/features/admin/presentation/general_manager_pages.dart';
import 'package:real_estate_mobile/features/properties/data/recent_properties_store.dart';
import 'package:real_estate_mobile/features/properties/presentation/recent_properties_screen.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/account/data/access_control_repository.dart';
import 'package:real_estate_mobile/features/account/presentation/actor_scoped_page.dart';
import 'package:real_estate_mobile/features/account/presentation/access_control_screen.dart';
import 'package:real_estate_mobile/features/account/presentation/account_verification_admin_screen.dart';
import 'package:real_estate_mobile/features/account/presentation/broker_verification_admin_screen.dart';
import 'package:real_estate_mobile/features/admin/presentation/general_manager_accounts_screen.dart';
import 'package:real_estate_mobile/features/account/data/account_verification_repository.dart';
import 'package:real_estate_mobile/features/account/data/broker_verification_repository.dart';
import 'package:real_estate_mobile/features/regions/data/region_repository.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/account/presentation/auth_screen.dart';
import 'package:real_estate_mobile/features/account/presentation/profile_screen.dart';
import 'package:real_estate_mobile/features/account/presentation/complete_profile_screen.dart';
import 'package:real_estate_mobile/features/account/presentation/forgot_password_screen.dart';
import 'package:real_estate_mobile/features/account/presentation/phone_verification_screen.dart';
import 'package:real_estate_mobile/features/account/presentation/broker_account_verification_screen.dart';
import 'package:real_estate_mobile/features/messages/presentation/conversation_reports_screen.dart';
import 'package:real_estate_mobile/features/regions/presentation/regions_management_screen.dart';
import 'package:real_estate_mobile/features/regions/presentation/platform_regions_screen.dart';

AuthUser _actor(int id) => AuthUser.fromJson({'id':id,'name':id==1?'أحمد علي محمد صالح':'خالد علي محمد صالح',
  'email':'synthetic-$id@example.invalid','phone':'+12025550101','account_status':'active',
  'phone_verified_at':'2026-10-26T00:00:00Z','profile_completed_at':'2026-10-26T00:00:00Z',
  'account_type':'broker','roles':['super_admin','broker'],'is_platform_owner':true,
  'permissions':['conversations.review_private']});
class _Auth extends AuthController {
  @override
  Future<AuthUser?> build() async => _actor(1);
  void change(int? id) => state=AsyncData(id==null?null:_actor(id));
}
class _Credentials implements AuthRepository {
  Completer<void>? pending;
  @override
  Future<Options> requiredAuthOptions() async {await pending?.future;return Options(headers:{'Authorization':'Bearer synthetic-only'});}
  @override
  Future<Options?> optionalAuthOptions() async => requiredAuthOptions();
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}
class _Harness {
  final account=_Auth();
  final credentials=_Credentials();
  final dio=Dio(BaseOptions(baseUrl:'https://synthetic.invalid/api'));
  late final ProviderContainer container;
  int status=200,calls=0,recentAttempts=0;
  bool recentStub=false,recentFail=false;
  Completer<void>? pending;
  Future<void> start() async {
    dio.interceptors.add(InterceptorsWrapper(onRequest:(request,handler) async {
      calls++;await pending?.future;
      if(status!=200) {handler.reject(DioException(requestOptions:request,type:DioExceptionType.badResponse,
        response:Response<Object>(requestOptions:request,statusCode:status)));return;}
      final Object data=switch(request.path) {
        '/advertisers/9/ratings/summary'=>{'advertiser_id':9,'average':4,'count':1,
          if(container.read(authControllerProvider).asData?.value?.id==1) 'my_rating':{'id':1,'rating':4,'status':'visible','comment':'Synthetic private rating A'}},
        '/advertisers/9/rating'=>{'advertiser_id':9,'average':4,'count':1},
        '/admin/access/catalog'=>{'roles':<Object>[],'permissions':<Object>[]},
        '/admin/access/users'=><Object>[{'id':17,'name':'Private administrative user A','email':'synthetic-private@example.invalid','account_status':'active'}],
        '/admin/account-verifications'=><Object>[{'user_id':17,'name':'Private administrative user A','type':'broker','status':'pending','details':<String,dynamic>{},'documents':<Object>[]}],
        '/admin/broker-account-verifications'=><Object>[{'user_id':17,'name':'Private administrative user A','status':'pending','documents':<Object>[]}],
        '/account-verification'=>{'user_id':1,'type':'broker','status':'rejected','documents':<Object>[]},
        '/broker/account-verification'=>{'user_id':1,'name':'Synthetic broker','status':'rejected',
          'note':'Private broker review A','documents':<Object>[]},
        '/admin/messages/reports'=><Object>[{'id':7,'thread_id':4,'reporter_name':'Synthetic reporter',
          'property_title':'Private report A','status':'open','reason_code':'other'}],
        '/admin/messages/reports/7/content'=>{'report':{'id':7,'thread_id':4},'messages':<Object>[
          {'id':1,'sender_name':'Synthetic author','body':'Private reported message A'}]},
        _=><Object>[],
      };
      handler.resolve(Response<Map<String,dynamic>>(requestOptions:request,statusCode:200,data:{'data':data}));
    }));
    container=ProviderContainer(overrides:[authControllerProvider.overrideWith(()=>account),
      authRepositoryProvider.overrideWithValue(credentials),dioProvider.overrideWithValue(dio),
      if(recentStub) recentPropertiesProvider.overrideWith((ref)async{recentAttempts++;if(recentFail) throw StateError('synthetic local failure');return <PropertySummary>[];})]);
    await container.read(authControllerProvider.future);
  }
  void dispose(){if(credentials.pending!=null&&!credentials.pending!.isCompleted) {credentials.pending!.complete();}if(pending!=null&&!pending!.isCompleted) {pending!.complete();}container.dispose();dio.close(force:true);}
}
Future<void> _frames(WidgetTester tester) async {for(var i=0;i<10;i++){await tester.pump(const Duration(milliseconds:30));}}
Future<_Harness> _mount(WidgetTester tester,Widget page,{bool large=false,_Harness? harness}) async {
  final h=harness??_Harness();await h.start();
  tester.view.physicalSize=const Size(320,640);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(h.dispose);addTearDown(() async {await tester.pumpWidget(const SizedBox.shrink());await tester.pump();});
  await tester.pumpWidget(UncontrolledProviderScope(container:h.container,child:MaterialApp(
    theme:large?AppTheme.dark:AppTheme.light,
    builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:TextScaler.linear(large?2.4:1),
      padding:const EdgeInsets.only(top:24,bottom:34)),child:Directionality(textDirection:TextDirection.rtl,child:child!)),home:page)));
  await _frames(tester);return h;
}
void main(){
  WidgetController.hitTestWarningShouldBeFatal=true;
  setUpAll(() async {final font=FontLoader('NotoSansArabic')
    ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf'));await font.load();});
  for(final kind in ['account-verification','broker-verification','regions','admin-access','community']){
    for(final phase in ['retained','token-lookup','late-read']){
      test('$kind repository expires across account change during $phase',() async {
        final h=_Harness();await h.start();addTearDown(h.dispose);
        late final Future<dynamic> Function() operation;
        if(kind=='account-verification'){
          h.container.listen(accountVerificationRepositoryProvider,(_,__){});
          final repo=h.container.read(accountVerificationRepositoryProvider);
          operation=phase=='late-read'?repo.status:()=>repo.approve(17);
        }else if(kind=='broker-verification'){
          h.container.listen(brokerVerificationRepositoryProvider,(_,__){});
          final repo=h.container.read(brokerVerificationRepositoryProvider);
          operation=phase=='late-read'?repo.status:()=>repo.approve(17);
        }else if(kind=='community'){
          h.container.listen(communityRepositoryProvider,(_,__){});
          final repo=h.container.read(communityRepositoryProvider);
          operation=phase=='late-read'?()=>repo.rateAdvertiser(advertiserId:9,rating:4,propertyId:60):()=>repo.deleteComment(17);
        }else if(kind=='admin-access'){
          h.container.listen(accessControlRepositoryProvider,(_,__){});
          final repo=h.container.read(accessControlRepositoryProvider);
          operation=phase=='late-read'?repo.users:()=>repo.updateStatus(17,'suspended');
        }else{
          h.container.listen(regionRepositoryProvider,(_,__){});
          final repo=h.container.read(regionRepositoryProvider);
          operation=phase=='late-read'?repo.governorates:()=>repo.createGovernorate(code:'TEST',nameAr:'اصطناعي');
        }
        if(phase=='retained'){
          h.account.change(2);await expectLater(operation(),throwsStateError);expect(h.calls,0);
        }else{
          final gate=Completer<void>();
          if(phase=='token-lookup') {h.credentials.pending=gate;}else{h.pending=gate;}
          final assertion=expectLater(operation(),throwsStateError);
          for(var i=0;i<10;i++){await Future<void>.delayed(Duration.zero);}
          h.account.change(null);h.account.change(1);gate.complete();await assertion;
          expect(h.calls,phase=='late-read'?1:0);
        }
      });
    }
  }
  for(final sameActor in [false,true]){
    for(final kind in ['profile','completion','broker','reports','admin-access','admin-accounts','admin-verification','admin-broker']){
      testWidgets('$kind private state expires across account change same actor=$sameActor',(tester) async {
        final page=switch(kind){'profile'=>const ProfileScreen(),'completion'=>const CompleteProfileScreen(),
          'broker'=>const BrokerAccountVerificationScreen(),'admin-access'=>const AccessControlScreen(),
          'admin-accounts'=>const GeneralManagerAccountsScreen(),'admin-verification'=>const AccountVerificationAdminScreen(),
          'admin-broker'=>const BrokerVerificationAdminScreen(),_=>const ConversationReportsScreen()};
        final h=await _mount(tester,page);
        final privateText=switch(kind){'profile'=>'أحمد علي محمد صالح','completion'=>'Private completion A',
          'broker'=>'Private broker review A','reports'=>'Private report A',_=>'Private administrative user A'};
        if(kind=='completion') {await tester.enterText(find.byType(TextField).first,privateText);}
        expect(find.text(privateText),findsWidgets);
        h.account.change(null);h.account.change(sameActor?1:2);await _frames(tester);
        expect(find.text(privateText),findsNothing,reason:'Old private values cannot be transferred across account boundaries');
        expect(tester.takeException(),isNull);
      });
    }
  }
  testWidgets('a route carrying preloaded private data rejects an account change before its first frame',(tester) async {
    final h=_Harness();await h.start();h.account.change(2);var built=false;
    await tester.pumpWidget(UncontrolledProviderScope(container:h.container,child:MaterialApp(home:
      ActorBoundPage(title:'Private route',actorId:1,builder:(_){built=true;return const Text('Private old route data');}))));
    expect(built,isFalse);expect(find.text('تغيّر الحساب'),findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());h.dispose();
  });
  final forms=<String,Widget Function()>{'auth':()=>const AuthScreen(),'profile':()=>const ProfileScreen(),
    'administration':()=>const GeneralManagerAdministrationScreen(),
    'community':()=>const ListingCommunityScreen(propertyId:60,advertiserId:9,advertiserName:'معلن اصطناعي'),
    'completion':()=>const CompleteProfileScreen(),'password':()=>const ForgotPasswordScreen(),
    'phone':()=>const PhoneVerificationScreen(),'broker':()=>const BrokerAccountVerificationScreen()};
  for(final entry in forms.entries){for(final large in [false,true]){
    testWidgets('${entry.key} form RTL ${large?'dark 2.4':'light'} stays scrollable and renders Arabic',(tester) async {
      await _mount(tester,entry.value(),large:large);expect(find.byType(Scaffold),findsWidgets);
      expect(find.byType(Scrollable),findsWidgets);expect(tester.takeException(),isNull);
      final scroll=find.byWidgetPredicate((w)=>w is Scrollable&&w.axisDirection==AxisDirection.down);
      if(scroll.evaluate().isNotEmpty){tester.state<ScrollableState>(scroll.first).position.jumpTo(
        tester.state<ScrollableState>(scroll.first).position.maxScrollExtent);await _frames(tester);}
      expect(tester.takeException(),isNull);
    });
  }}
  for(final large in [false,true]){
    testWidgets('personal rating is refreshed for the new account without hiding public community large=$large',(tester)async{
      final h=await _mount(tester,const ListingCommunityScreen(propertyId:60,advertiserId:9,advertiserName:'معلن اصطناعي'),large:large);
      expect(find.text('تقييمك الحالي: 4/5'),findsOneWidget);
      h.account.change(2);await _frames(tester);
      expect(find.text('تقييمك الحالي: 4/5'),findsNothing);expect(find.text('قيّم المعلن'),findsOneWidget);
      h.account.change(null);await _frames(tester);expect(find.text('التعليقات وتقييم المعلن'),findsOneWidget);
      expect(tester.takeException(),isNull);
    });
    testWidgets('recent screen retries local read and reaches empty state large=$large',(tester)async{
      final h=_Harness()..recentStub=true..recentFail=true;
      await _mount(tester,const RecentPropertiesScreen(),large:large,harness:h);
      expect(find.text('تعذر تحميل السجل المحلي.'),findsOneWidget);h.recentFail=false;final before=h.recentAttempts;
      final retry=find.text('إعادة المحاولة');await tester.ensureVisible(retry);await tester.pump();await tester.tap(retry);await _frames(tester);
      expect(h.recentAttempts,greaterThan(before));expect(find.text('ما شاهدت عقارات بعد'),findsOneWidget);expect(tester.takeException(),isNull);
    });
  }
  for(final entry in <String,Widget Function()>{'reports':()=>const ConversationReportsScreen(),
    'broker':()=>const BrokerAccountVerificationScreen(),'regions':()=>const RegionsManagementScreen(),
    'platform-regions':()=>const PlatformRegionsScreen()}.entries){for(final large in [false,true]){
    testWidgets('${entry.key} first network failure has visible friendly error and a working retry large=$large',(tester) async {
      final h=_Harness()..status=503..pending=Completer<void>();await _mount(tester,entry.value(),large:large,harness:h);
      expect(h.calls,greaterThan(0));expect(tester.takeException(),isNull);
      h.pending!.complete();await _frames(tester);
      final error=find.textContaining('الخادم غير متاح مؤقتاً');
      if(error.evaluate().isEmpty){
        final scroll=find.byWidgetPredicate((w)=>w is Scrollable&&w.axisDirection==AxisDirection.down);
        if(scroll.evaluate().isNotEmpty){await tester.scrollUntilVisible(error,250,scrollable:scroll.first,maxScrolls:15);}
      }
      expect(error,findsWidgets);
      final retry=find.text('إعادة المحاولة');expect(retry,findsWidgets);
      await tester.ensureVisible(retry.first);await tester.pump();final before=h.calls;await tester.tap(retry.first);await _frames(tester);
      expect(h.calls,greaterThan(before));expect(tester.takeException(),isNull);
      // Native map drawing/gestures remain an explicit Android acceptance step.
    });
  }}
}

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
  @override
  Future<Options> requiredAuthOptions() async => Options(headers:{'Authorization':'Bearer synthetic-only'});
  @override
  Future<Options?> optionalAuthOptions() async => requiredAuthOptions();
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}
class _Harness {
  final account=_Auth();
  final dio=Dio(BaseOptions(baseUrl:'https://synthetic.invalid/api'));
  late final ProviderContainer container;
  int status=200,calls=0;
  Completer<void>? pending;
  Future<void> start() async {
    dio.interceptors.add(InterceptorsWrapper(onRequest:(request,handler) async {
      calls++;await pending?.future;
      if(status!=200) {handler.reject(DioException(requestOptions:request,type:DioExceptionType.badResponse,
        response:Response<Object>(requestOptions:request,statusCode:status)));return;}
      final Object data=switch(request.path) {
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
      authRepositoryProvider.overrideWithValue(_Credentials()),dioProvider.overrideWithValue(dio)]);
    await container.read(authControllerProvider.future);
  }
  void dispose(){if(pending!=null&&!pending!.isCompleted) {pending!.complete();}container.dispose();dio.close(force:true);}
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
  for(final sameActor in [false,true]){
    for(final kind in ['profile','completion','broker','reports']){
      testWidgets('$kind private state expires across account change same actor=$sameActor',(tester) async {
        final page=switch(kind){'profile'=>const ProfileScreen(),'completion'=>const CompleteProfileScreen(),
          'broker'=>const BrokerAccountVerificationScreen(),_=>const ConversationReportsScreen()};
        final h=await _mount(tester,page);
        final privateText=switch(kind){'profile'=>'أحمد علي محمد صالح','completion'=>'Private completion A',
          'broker'=>'Private broker review A',_=>'Private report A'};
        if(kind=='completion') {await tester.enterText(find.byType(TextField).first,privateText);}
        expect(find.text(privateText),findsWidgets);
        h.account.change(null);h.account.change(sameActor?1:2);await _frames(tester);
        expect(find.text(privateText),findsNothing,reason:'Old private values cannot be transferred across account boundaries');
        expect(tester.takeException(),isNull);
      });
    }
  }
  final forms=<String,Widget Function()>{'auth':()=>const AuthScreen(),'profile':()=>const ProfileScreen(),
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
  for(final entry in <String,Widget Function()>{'reports':()=>const ConversationReportsScreen(),
    'broker':()=>const BrokerAccountVerificationScreen(),'regions':()=>const RegionsManagementScreen(),
    'platform-regions':()=>const PlatformRegionsScreen()}.entries){for(final large in [false,true]){
    testWidgets('${entry.key} first network failure has visible friendly error and a working retry large=$large',(tester) async {
      final h=_Harness()..status=503..pending=Completer<void>();await _mount(tester,entry.value(),large:large,harness:h);
      expect(h.calls,greaterThan(0));expect(tester.takeException(),isNull);
      h.pending!.complete();await _frames(tester);
      expect(find.textContaining('الخادم غير متاح مؤقتاً'),findsWidgets);
      final retry=find.text('إعادة المحاولة');expect(retry,findsWidgets);
      await tester.ensureVisible(retry.first);await tester.pump();final before=h.calls;await tester.tap(retry.first);await _frames(tester);
      expect(h.calls,greaterThan(before));expect(tester.takeException(),isNull);
      // Native map drawing/gestures remain an explicit Android acceptance step.
    });
  }}
}

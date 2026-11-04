import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/account/presentation/auth_gate.dart';
import 'package:real_estate_mobile/features/account/presentation/actor_scoped_page.dart';

AuthUser _user(int id,{Map<String,dynamic> changes=const {}})=>AuthUser.fromJson({
  'id':id,'name':'أحمد علي محمد صالح','email':'synthetic@example.invalid','account_status':'active',
  'phone_verified_at':'2026-10-26T00:00:00Z','profile_completed_at':'2026-10-26T00:00:00Z',...changes});
class _Auth extends AuthController{
  _Auth(this.initial);
  final AuthUser? initial;
  @override
  Future<AuthUser?> build() async=>initial;
  void change(AuthUser? value)=>state=AsyncData(value);
}
Future<void> _frames(WidgetTester t) async{for(var i=0;i<12;i++){await t.pump(const Duration(milliseconds:30));}}
Future<ProviderContainer> _mount(WidgetTester t,_Auth auth,Widget page,{bool large=false,bool observe=false}) async{
  t.view.devicePixelRatio=1;t.view.physicalSize=const Size(320,568);
  addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
  final c=ProviderContainer(overrides:[authControllerProvider.overrideWith(()=>auth)]);
  addTearDown(c.dispose);addTearDown(() async{await t.pumpWidget(const SizedBox.shrink());await t.pump();});
  await c.read(authControllerProvider.future);
  await t.pumpWidget(UncontrolledProviderScope(container:c,child:MaterialApp(
    navigatorObservers:observe?[c.read(accountPopupObserverProvider)]:[],
    theme:large?AppTheme.dark:AppTheme.light,
    builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:TextScaler.linear(large?2.4:1),
      padding:const EdgeInsets.only(top:24,bottom:34)),child:Directionality(textDirection:TextDirection.rtl,child:child!)),home:page)));
  await _frames(t);return c;
}
void main(){
  setUpAll(() async {final font=FontLoader('NotoSansArabic')
    ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf'));await font.load();});
  final cases=<String,(AuthUser?,bool,bool,String)>{
    'guest':(null,false,false,'سجّل الدخول أولاً'),
    'phone':(_user(1,changes:{'account_status':'pending_verification','phone_verified_at':null}),false,false,'تحقق من رقم واتساب'),
    'profile':(_user(1,changes:{'name':'مستخدم جديد','profile_completed_at':null}),true,false,'أكمل الاسم الرباعي أولاً'),
    'publishing':(_user(1),true,false,'توثيق نوع الحساب مطلوب'),
    'professional':(_user(1),false,true,'أدوات الدلال بعد اعتماد التوثيق'),
  };
  for(final e in cases.entries){for(final large in [false,true]){
    testWidgets('auth gate ${e.key} remains readable on small RTL phone large=$large',(t) async{
      final c=e.value;
      await _mount(t,_Auth(c.$1),Stage6AuthGate(requireListingEligible:c.$2,requireProfessional:c.$3,
        child:const Text('Must remain protected')),large:large);
      expect(find.text(c.$4),findsOneWidget);expect(find.text('Must remain protected'),findsNothing);
      expect(find.byType(Scrollable),findsWidgets);expect(t.takeException(),isNull);
    });
  }}
  for(final same in [false,true]){
    testWidgets('protected route cannot reuse preloaded private child after logout and login same=$same',(t) async{
      final auth=_Auth(_user(1));
      await _mount(t,auth,const Stage6AuthGate(child:Scaffold(body:Text('Private routed state A'))));
      expect(find.text('Private routed state A'),findsOneWidget);
      auth.change(null);auth.change(_user(same?1:2));await _frames(t);
      expect(find.text('Private routed state A'),findsNothing);expect(find.text('تغيّر الحساب'),findsOneWidget);
      expect(t.takeException(),isNull);
    });
  }
  for(final kind in ['logout','same-id','permissions']){
    testWidgets('root popup stack is withdrawn after $kind authorization change',(t) async{
      final auth=_Auth(_user(1,changes:{'permissions':['users.view']}));
      await _mount(t,auth,Builder(builder:(context)=>Scaffold(body:TextButton(onPressed:(){
        showModalBottomSheet<void>(context:context,builder:(sheet)=>TextButton(onPressed:(){
          showDialog<void>(context:sheet,builder:(_)=>const AlertDialog(content:Text('Private old dialog A')));
        },child:const Text('Private old sheet A')));
      },child:const Text('Open private')))),observe:true);
      await t.tap(find.text('Open private'));await t.pumpAndSettle();
      await t.tap(find.text('Private old sheet A'));await t.pumpAndSettle();
      expect(find.text('Private old dialog A'),findsOneWidget);
      if(kind=='logout'){auth.change(null);}else if(kind=='same-id'){auth.change(null);auth.change(_user(1));}
      else{auth.change(_user(1,changes:{'permissions':<String>[]}));}
      await _frames(t);await t.pumpAndSettle();
      expect(find.text('Private old dialog A'),findsNothing);expect(find.text('Private old sheet A'),findsNothing);
      expect(find.text('Open private'),findsOneWidget);expect(t.takeException(),isNull);
    });
  }
}

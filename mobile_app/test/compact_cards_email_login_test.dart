import 'dart:io';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/core/widgets/app_components.dart';
import 'package:real_estate_mobile/core/widgets/property_card_gallery.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/account/presentation/auth_screen.dart';
import 'package:real_estate_mobile/features/account/presentation/phone_verification_screen.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_compare_actions.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_summary_card.dart';

const _name = 'أحمد علي محمد صالح';
AuthUser _user() => AuthUser.fromJson({'id':9,'name':_name,'email':'person@example.test','phone':null,
  'email_verified_at':'2026-10-20T00:00:00Z','profile_completed_at':'2026-10-20T00:00:00Z',
  'account_status':'pending_verification','roles':['registered_user'],'permissions':[]});
class _Auth extends AuthController {
  String? channel, name, destination;
  @override
  Future<AuthUser?> build() async => null;
  @override
  Future<WhatsAppAuthPending> startEmail({required String email, String? name}) async {
    channel='email'; this.name=name; destination=email;
    final pending=WhatsAppAuthPending(phone:'',email:email,name:name,isNewAccount:true);
    ref.read(whatsAppAuthPendingProvider.notifier).state=pending; return pending;
  }
  @override
  Future<WhatsAppAuthPending> startWhatsApp({required String phone, String? name}) async {
    channel='whatsapp'; this.name=name; destination=phone;
    final pending=WhatsAppAuthPending(phone:phone,name:name,isNewAccount:true);
    ref.read(whatsAppAuthPendingProvider.notifier).state=pending; return pending;
  }
}
PropertySummary _property(int id) => PropertySummary.fromJson({'id':id,'title':'منزل واسع بإطلالة هادئة',
  'type':'house','purpose':'sale','status':'published','price':125000000,'currency':'YER',
  'address':'إب، شارع السبل','bedrooms':3,'bathrooms':2,'area_value':180,'area_unit':'sqm',
  'has_parking':true,'price_display_note':'السعي YER 2500000'});

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final picture=await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio:2);
    final bytes=await picture.toByteData(format:ui.ImageByteFormat.png);
    final file=File('build/compact-cards-preview/$name.png');
    await file.parent.create(recursive:true); await file.writeAsBytes(bytes!.buffer.asUint8List()); picture.dispose();
  });
}
Future<void> _pump(WidgetTester tester, Widget child,{double width=412,double scale=1,GlobalKey? boundary}) async {
  tester.view.physicalSize=Size(width,915); tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(overrides:[authControllerProvider.overrideWith(_Auth.new)],
    child:MaterialApp(theme:AppTheme.light,builder:(context,child)=>MediaQuery(
      data:MediaQuery.of(context).copyWith(textScaler:TextScaler.linear(scale)),
      child:RepaintBoundary(key:boundary,child:child!)),home:Directionality(textDirection:TextDirection.rtl,child:child))));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for(final family in ['sans-serif','NotoSansArabic']) {
      await (FontLoader(family)..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'))).load();
    }
    final font=FontLoader('PrimaryFont');
    for(final weight in ['Regular','Medium','SemiBold','Bold','ExtraBold']) { font.addFont(rootBundle.load('assets/ebroker/fonts/Manrope-$weight.ttf')); }
    await font.load();
  });
  test('verified email does not satisfy the phone or publishing gates',() {
    final user=_user(); expect(user.isEmailVerified,isTrue); expect(user.isActive,isFalse);
    expect(user.needsPhoneVerification,isTrue); expect(user.canCreateListing,isFalse);
  });
  test('repository preserves the name and email channel, stores a token only after OTP verification',() async {
    final calls=<RequestOptions>[], writes=<String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('real_estate/secure_store'),(call) async { if(call.method=='writeToken')writes.add((call.arguments as Map)['token'] as String); return null; });
    addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('real_estate/secure_store'),null));
    final dio=Dio()..interceptors.add(InterceptorsWrapper(onRequest:(options,handler) {
      calls.add(options);
      handler.resolve(Response(requestOptions:options,statusCode:200,data:{'data':options.path.endsWith('/start')
        ? {'email':'person@example.test'} : {'token':'synthetic-session-token','user':{'id':9,'name':_name,'email':'person@example.test','email_verified_at':'2026-10-20T00:00:00Z','account_status':'pending_verification'}}}));
    }));
    final repo=AuthRepository(dio), pending=await repoStart(dio);
    expect(pending.isEmail,isTrue); expect(pending.name,_name); expect(writes,isEmpty);
    await repo.verifyWhatsApp(pending,'123456');
    expect(calls.map((c)=>c.path),['/auth/email/start','/auth/email/login']);
    expect(calls.last.data,{'email':'person@example.test','code':'123456','name':_name});
    expect(writes,['synthetic-session-token']);
  });
  for(final scale in [1.0,2.4]) {
    testWidgets('compact RTL cards keep inline facts, price and two-property actions at $scale',(tester) async {
      final key=GlobalKey();
      await _pump(tester,Scaffold(body:ListView(padding:const EdgeInsets.all(16),children:[
        for(final id in [1,2,3]) Padding(padding:const EdgeInsets.only(bottom:10),child:PropertySummaryCard(property:_property(id))),
      ]),bottomNavigationBar:const Padding(padding:EdgeInsets.all(12),child:PropertyCompareTray())),scale:scale,boundary:key);
      expect(find.textContaining('السعي'),findsNothing);
      if(scale==1)expect(tester.getSize(find.byType(PropertySummaryCard).first).height,lessThan(260));
      final action=find.byKey(const ValueKey('compare-property-1'));
      expect(tester.getRect(find.byType(PropertyCardGallery).first).contains(tester.getCenter(action)),isFalse);
      await tester.ensureVisible(action);await tester.tap(action);await tester.pumpAndSettle();
      expect(find.text('اختر العقار الثاني (١/٢)'),findsOneWidget);
      final second=find.byKey(const ValueKey('compare-property-2'));
      await tester.ensureVisible(second);await tester.tap(second);await tester.pumpAndSettle();
      expect(find.text('قارن العقارين (٢/٢)'),findsOneWidget);
      final third=find.byKey(const ValueKey('compare-property-3'));
      await tester.ensureVisible(third);await tester.tap(third);await tester.pumpAndSettle();
      final container=ProviderScope.containerOf(tester.element(third));
      expect(container.read(propertyCompareSelectionProvider),{1,2});
      await _capture(tester,key,'cards-selected-$scale'); expect(tester.takeException(),isNull);
    });
    testWidgets('featured price stays on the photo and compact icons remain visible at $scale',(tester) async {
      final key=GlobalKey(); await _pump(tester,Scaffold(body:ListView(padding:const EdgeInsets.all(16),children:[PropertySummaryCard(property:_property(1),imageFirst:true)]),
        bottomNavigationBar:AppNavigationBar(destinations:const [AppNavDestination(label:'الرئيسية',icon:Icons.home_outlined),
          AppNavDestination(label:'عملي',icon:Icons.work_outline),AppNavDestination(label:'العملاء',icon:Icons.people_outline),
          AppNavDestination(label:'حسابي',icon:Icons.account_circle_outlined)],selectedIndex:0,onSelected:(_) {},onCreate:() {})),scale:scale,boundary:key);
      final badge=find.byKey(const ValueKey('property-photo-price'));
      expect(tester.getRect(find.byType(PropertyCardGallery)).contains(tester.getCenter(badge)),isTrue);
      expect(find.byIcon(Icons.work_outline),findsOneWidget); expect(find.byIcon(Icons.people_outline),findsOneWidget);
      expect(find.byIcon(Icons.account_circle_outlined),findsOneWidget);
      await _capture(tester,key,'featured-and-navigation-$scale'); expect(tester.takeException(),isNull);
    });
    testWidgets('login collects the name and sends the chosen channel at $scale',(tester) async {
      final auth=_Auth(), key=GlobalKey();
      tester.view.physicalSize=const Size(412,915);tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
      final router=GoRouter(routes:[GoRoute(path:'/',builder:(_,__)=>const AuthScreen()),GoRoute(path:'/verify-phone',builder:(_,__)=>const PhoneVerificationScreen())]);
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(overrides:[authControllerProvider.overrideWith(()=>auth)],child:MaterialApp.router(theme:AppTheme.light,routerConfig:router,
        builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:TextScaler.linear(scale)),child:RepaintBoundary(key:key,child:child!)))));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('auth-name')));await tester.enterText(find.byKey(const ValueKey('auth-name')),_name);
      await tester.ensureVisible(find.byKey(const ValueKey('auth-channel-email')));await tester.tap(find.byKey(const ValueKey('auth-channel-email')));await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('auth-email')));await tester.enterText(find.byKey(const ValueKey('auth-email')),'person@example.test');
      await tester.ensureVisible(find.byKey(const ValueKey('auth-submit')));await tester.pumpAndSettle();await _capture(tester,key,'email-login-$scale');
      await tester.tap(find.byKey(const ValueKey('auth-submit')));await tester.pumpAndSettle();
      expect(auth.channel,'email');expect(auth.name,_name);expect(auth.destination,'person@example.test');
      expect(find.text('رمز التحقق عبر البريد'),findsOneWidget);expect(tester.takeException(),isNull);
    });
  }
  testWidgets('320-wide card has readable controls and no overflow',(tester) async {
    await _pump(tester,Scaffold(body:ListView(children:[PropertySummaryCard(property:_property(1))])),width:320);
    expect(find.text('أضف للمقارنة'),findsOneWidget);expect(tester.takeException(),isNull);
  });
}
Future<WhatsAppAuthPending> repoStart(Dio dio) => AuthRepository(dio).startEmail(email:'person@example.test',name:_name);

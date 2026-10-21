import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/features/account/data/account_safety_repository.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/account/presentation/account_safety_screen.dart';
import 'package:real_estate_mobile/features/community/data/community_repository.dart';
import 'package:real_estate_mobile/features/community/domain/community_models.dart';
import 'package:real_estate_mobile/features/messages/domain/message_models.dart';
import 'package:real_estate_mobile/features/messages/data/message_repository.dart';
import 'package:real_estate_mobile/features/reviews/data/listing_review_repository.dart';
import 'package:real_estate_mobile/features/reviews/domain/listing_review_models.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/data/favorites_repository.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_summary_card.dart';
import 'package:real_estate_mobile/features/discovery/presentation/marketplace_section_screen.dart';
import 'package:real_estate_mobile/features/discovery/presentation/smart_search_assistant.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_draft_photo.dart';

AuthUser _user(int id) => AuthUser.fromJson({'id':id,'name':'حساب اختبار $id','phone':'+967700000123',
  'phone_verified_at':'2026-10-21T00:00:00Z','account_status':'active','roles':['registered_user'],'permissions':[]});
class _Auth extends AuthController {
  @override
  Future<AuthUser?> build() async => _user(9);
  void change(int? id) { state=AsyncData(id == null ? null : _user(id)); }
}
class _Safety extends AccountSafetyRepository {
  _Safety({this.rows=const [BlockedAccount(21,'حساب محظور تجريبي')]}):super(Dio(),AuthRepository(Dio()),actorId:9,currentActor:()=>9);
  List<BlockedAccount> rows;
  int requests=0, unblocks=0;
  bool fail=false;
  Completer<DeletionRequestStatus>? gate;
  @override
  Future<BlockedAccountPage> blocked({int page=1}) async => BlockedAccountPage(rows,false);
  @override
  Future<DeletionRequestStatus> deletionStatus() async => const DeletionRequestStatus(status:'not_requested');
  @override
  Future<void> setBlocked(int userId,bool blocked) async { if(fail)throw StateError('offline');unblocks++;rows=[]; }
  @override
  Future<DeletionRequestStatus> requestDeletion() async {
    requests++; if(fail)throw StateError('offline');
    return gate?.future ?? Future.value(const DeletionRequestStatus(status:'open',reference:'SUP-SYNTHETIC-21',caseId:21));
  }
}
Future<void> _pump(WidgetTester tester,_Safety repo,{_Auth? auth,double scale=1,GlobalKey? boundary}) async {
  tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(overrides:[authControllerProvider.overrideWith(()=>auth??_Auth()),accountSafetyRepositoryProvider.overrideWithValue(repo)],
    child:MaterialApp(theme:AppTheme.light,builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:TextScaler.linear(scale)),
      child:RepaintBoundary(key:boundary,child:child!)),home:const AccountSafetyScreen())));
  await tester.pumpAndSettle();
}
Future<void> _show(WidgetTester tester,Finder finder) async {
  await tester.ensureVisible(finder);await tester.pumpAndSettle();
}
Future<void> _capture(WidgetTester tester,GlobalKey key,String name) async {
  await tester.runAsync(() async {
    final image=await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio:2);
    final data=await image.toByteData(format:ui.ImageByteFormat.png);
    final file=File('build/wave2-preview/$name.png');await file.parent.create(recursive:true);await file.writeAsBytes(data!.buffer.asUint8List());image.dispose();
  });
}
void main() {
  setUpAll(() async {
    final primary = FontLoader('PrimaryFont');
    for (final weight in ['Regular','Medium','SemiBold','Bold','ExtraBold']) { primary.addFont(rootBundle.load('assets/ebroker/fonts/Manrope-$weight.ttf')); }
    await primary.load();
    final icons=await File('${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytes();
    await (FontLoader('MaterialIcons')..addFont(Future.value(icons.buffer.asByteData()))).load();
    for(final family in ['sans-serif','NotoSansArabic']) {
      await (FontLoader(family)..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'))).load();
    }
  });
  test('thread flags preserve old responses and distinguish own block from unavailable sending',() {
    final old=MessageThreadSummary.fromJson({'id':1});expect(old.canSend,isTrue);expect(old.blockedByMe,isFalse);
    final blocked=MessageThreadSummary.fromJson({'id':1,'can_send':false,'blocked_by_me':true});expect(blocked.canSend,isFalse);expect(blocked.blockedByMe,isTrue);
  });
  test('report receipts require a real reference and never claim success from an empty body',() {
    expect(()=>ReportReceipt.fromJson({'id':2,'status':'open'}),throwsStateError);
    final receipt=ReportReceipt.fromJson({'id':2,'status':'open','reference':'SUP-2'},alreadyReceived:true);
    expect(receipt.message,contains('SUP-2'));expect(receipt.alreadyReceived,isTrue);
  });
  test('duplicate report response is the original own receipt; unrelated conflicts remain errors',() async {
    var known = true;
    final dio=Dio();dio.interceptors.add(InterceptorsWrapper(onRequest:(options,handler)=>handler.reject(DioException(requestOptions:options, type:DioExceptionType.badResponse,
      response:Response(requestOptions:options,statusCode:409, data:{'code':known ? 'report_already_received' : 'unrelated_conflict','data':{'id':7,'reference':'SUP-7','status':'open'}})))));
    final repo=CommunityRepository(dio,_AuthOptions(dio));
    final receipt=await repo.report(targetType:'listing',targetId:1,reason:'misleading',details:'تفاصيل للمراجعة');
    expect(receipt.reference,'SUP-7');expect(receipt.alreadyReceived,isTrue);
    known=false;await expectLater(repo.report(targetType:'listing',targetId:1,reason:'misleading',details:'تفاصيل للمراجعة'),throwsA(isA<DioException>()));dio.close();
  });
  test('session-bound account operations refuse a changed identity before sending HTTP',() async {
    var actor=9, calls=0;
    final dio=Dio()..interceptors.add(InterceptorsWrapper(onRequest:(r,h){calls++;h.resolve(Response(requestOptions:r,statusCode:200));}));
    final repo=AccountSafetyRepository(dio,_AuthOptions(dio),actorId:9,currentActor:()=>actor);
    actor=10;await expectLater(repo.requestDeletion(),throwsStateError);expect(calls,0);dio.close();
  });
  for (final name in ['messages','reports','media-review']) {
    test('delayed $name authentication cannot send the old operation as another account',() async {
      var actor=9, calls=0;
      final dio=Dio()..interceptors.add(InterceptorsWrapper(onRequest:(r,h){calls++;h.resolve(Response(requestOptions:r,statusCode:200));}));
      final auth=_DelayedOptions(dio);
      final Future<dynamic> request = switch(name) {
        'messages' => MessageRepository(dio,auth,actorId:9,currentActor:()=>actor).send(1,'رسالة الحساب السابق'),
        'reports' => CommunityRepository(dio,auth,actorId:9,currentActor:()=>actor).report(targetType:'listing',targetId:1,reason:'misleading',details:'تفاصيل الحساب السابق'),
        _ => ListingReviewRepository(dio,auth,actorId:9,currentActor:()=>actor).reviewMedia(1,2,'a'*64,'uncertain','تحتاج الصورة إلى مراجعة'),
      };
      final expectation=expectLater(request,throwsStateError);actor=10;auth.options.complete(Options(headers:{'Authorization':'Bearer synthetic-new-session'}));await expectation;expect(calls,0);dio.close();
    });
  }
  test('review image resolution stays on the API origin and uses one api path',() async {
    final dio=Dio(BaseOptions(baseUrl:'https://fixture.example/api'));final calls=<RequestOptions>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest:(r,h){calls.add(r);h.resolve(Response<List<int>>(requestOptions:r,statusCode:200,data:[1,2,3]));}));
    final repo=ListingReviewRepository(dio,_AuthOptions(dio));
    expect(await repo.protectedImage('/api/property-media/21?variant=detail'),[1,2,3]);expect(calls.single.uri.path,'/api/property-media/21');
    await expectLater(repo.protectedImage('https://foreign.example/api/property-media/21'),throwsStateError);
    await expectLater(repo.protectedImage('/api/admin/users'),throwsStateError);expect(calls.length,1);dio.close();
  });
  test('media review token and human assessment remain distinct from an automated verdict',() {
    final image=ReviewMediaItem.fromImageJson({'id':2,'url':'/api/property-media/2','relevance_token':'a'*64,
      'relevance_review':{'checker':'human_review','decision':'uncertain','reason':'تحتاج توضيحًا'}});
    expect(image.relevanceToken,'a'*64);expect(image.relevance,'uncertain');expect(image.reviewReason,'تحتاج توضيحًا');
  });
  test('image contexts select only their derived variant with compatible fallback',() {
    final image=PropertyImageItem.fromJson({'id':1,'url':'/display/detail','variants':{'card':'/display/card','detail':'/display/detail','gallery':'/display/gallery','zoom':'/display/zoom'}});
    expect([image.cardUrl,image.detailUrl,image.galleryUrl,image.zoomUrl],['/display/card','/display/detail','/display/gallery','/display/zoom']);
    final legacy=PropertyImageItem.fromJson({'id':2,'url':'/public-safe'});expect(legacy.zoomUrl,'/public-safe');
  });
  test('image cache coalesces a request, retries failure and clears across sessions',() async {
    final cache=ListingPhotoCache(maxEntries:2,maxBytes:8);var calls=0;
    final gate=Completer<Uint8List>();
    final one=cache.load('a',(){calls++;return gate.future;});final two=cache.load('a',(){calls++;return gate.future;});
    expect(identical(one,two),isTrue);expect(calls,1);
    gate.complete(Uint8List.fromList([1,2,3]));await one;
    await cache.load('a',(){calls++;return Future.value(Uint8List.fromList([4]));});expect(calls,1);
    await expectLater(cache.load('bad',() async {throw StateError('offline');}),throwsStateError);
    expect(await cache.load('bad',() async => Uint8List.fromList([6])),[6]);
    cache.clear();expect(await cache.load('a',() async => Uint8List.fromList([9])),[9]);
  });
  test('cache TTL, byte limit and late completion cannot resurrect old account bytes',() async {
    var now=DateTime.utc(2026,10,21),calls=0;
    final cache=ListingPhotoCache(maxBytes:4,clock:()=>now,ttl:const Duration(seconds:2));
    Future<Uint8List> load() async {calls++;return Uint8List.fromList([1,2,3]);}
    await cache.load('a',load);await cache.load('b',load);await cache.load('a',load);expect(calls,3);
    now=now.add(const Duration(seconds:3));await cache.load('a',load);expect(calls,4);
    final gate=Completer<Uint8List>();final stale=cache.load('private',()=>gate.future);cache.clear();gate.complete(Uint8List.fromList([7]));await stale;
    expect(await cache.load('private',() async=>Uint8List.fromList([8])),[8]);
  });
  testWidgets('a page builds nearby cards only and repeated more taps share one request',(tester) async {
    final repo=_Sections();tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(overrides:[authControllerProvider.overrideWith(_Auth.new),
      propertyRepositoryProvider.overrideWithValue(repo),favoritePropertyIdsProvider.overrideWith((ref) async => <int>{}),assistantHintStoreProvider.overrideWithValue(_NoHint())],
      child:MaterialApp(theme:AppTheme.light,home:const MarketplaceSectionScreen())));
    await tester.pumpAndSettle();expect(repo.calls,1);
    expect(find.byType(PropertySummaryCard).evaluate().length,lessThan(20));expect(find.text('عقار اختباري 20'),findsNothing);
    final more=find.text('المزيد من العقارات');await tester.scrollUntilVisible(more,550,scrollable:find.byType(Scrollable).first);await tester.pumpAndSettle();
    await tester.tap(more);await tester.tap(more);await tester.pump();expect(repo.calls,2);
    repo.next.complete((<PropertySummary>[],false));await tester.pumpAndSettle();expect(find.text('المزيد من العقارات'),findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());await tester.pumpAndSettle();
  });
  testWidgets('unblocking requires confirmation and a failed operation keeps the row',(tester) async {
    final repo=_Safety()..fail=true;await _pump(tester,repo);
    await tester.tap(find.text('إلغاء الحظر').first);await tester.pumpAndSettle();await tester.tap(find.text('إلغاء'));await tester.pumpAndSettle();expect(repo.unblocks,0);
    await tester.tap(find.text('إلغاء الحظر').first);await tester.pumpAndSettle();await tester.tap(find.widgetWithText(FilledButton,'إلغاء الحظر'));await tester.pumpAndSettle();
    expect(find.text('حساب محظور تجريبي'),findsOneWidget);
    repo.fail=false;await tester.tap(find.text('إلغاء الحظر').first);await tester.pumpAndSettle();await tester.tap(find.widgetWithText(FilledButton,'إلغاء الحظر'));await tester.pumpAndSettle();expect(repo.unblocks,1);expect(find.text('لا توجد حسابات محظورة.'),findsOneWidget);
  });
  testWidgets('deletion request has no success receipt before server confirmation and retries safely',(tester) async {
    final repo=_Safety(rows:[])..fail=true;await _pump(tester,repo);
    final button=find.byKey(const ValueKey('request-account-deletion'));await _show(tester,button);await tester.tap(button);await tester.pumpAndSettle();
    await tester.tap(find.text('إرسال الطلب للمراجعة'));await tester.pumpAndSettle();expect(repo.requests,1);expect(find.textContaining('SUP-SYNTHETIC'),findsNothing);
    repo.fail=false;repo.gate=Completer<DeletionRequestStatus>();await tester.tap(button);await tester.pumpAndSettle();await tester.tap(find.text('إرسال الطلب للمراجعة'));await tester.pump();await tester.pump(const Duration(milliseconds:500));
    expect(repo.requests,2);expect(find.textContaining('SUP-SYNTHETIC'),findsNothing);
    repo.gate!.complete(const DeletionRequestStatus(status:'open',reference:'SUP-SYNTHETIC-21',caseId:21));await tester.pumpAndSettle();expect(find.textContaining('SUP-SYNTHETIC-21'),findsOneWidget);
    expect(find.textContaining('تم حذف'),findsNothing);
  });
  testWidgets('logout removes prior account safety data and late receipts stay hidden',(tester) async {
    final repo=_Safety(),auth=_Auth();await _pump(tester,repo,auth:auth);expect(find.text('حساب محظور تجريبي'),findsOneWidget);
    auth.change(null);await tester.pumpAndSettle();expect(find.text('حساب محظور تجريبي'),findsNothing);expect(find.text('سجّل الدخول للمتابعة.'),findsOneWidget);
  });
  for(final scale in [1.0,2.4]) {
    testWidgets('Arabic safety page and request dialog remain scrollable at $scale',(tester) async {
      final key=GlobalKey();await _pump(tester,_Safety(),scale:scale,boundary:key);expect(tester.takeException(),isNull);
      await _capture(tester,key,'account-safety-$scale');final button=find.byKey(const ValueKey('request-account-deletion'));await _show(tester,button);await tester.tap(button);await tester.pumpAndSettle();
      expect(tester.takeException(),isNull);await _capture(tester,key,'deletion-confirm-$scale');
    });
  }
}
class _AuthOptions extends AuthRepository {
  _AuthOptions(Dio dio):super(dio);
  @override
  Future<Options> requiredAuthOptions() async => Options(headers:{'Authorization':'Bearer synthetic-fixture'});
}

class _DelayedOptions extends AuthRepository {
  _DelayedOptions(Dio dio):super(dio);
  final options=Completer<Options>();
  @override
  Future<Options> requiredAuthOptions() => options.future;
}

class _NoHint extends AssistantHintStore {
  @override
  Future<bool> take() async => false;
}
class _Sections extends PropertyRepository {
  _Sections():super(Dio(),AuthRepository(Dio()));
  int calls=0;
  final next=Completer<(List<PropertySummary>,bool)>();
  @override
  Future<(List<PropertySummary>,bool)> searchListings(Map<String,dynamic> filters,{int page=1}) async {
    calls++;if(page>1)return next.future;
    return (List.generate(20,(index)=>PropertySummary.fromJson({'id':index+1,'title':'عقار اختباري ${index+1}',
      'type':'house','purpose':'sale','price':1000000,'currency':'YER','latitude':15.3,'longitude':44.2,'status':'published'})),true);
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/local/listing_recovery_store.dart';
import 'package:real_estate_mobile/core/platform/app_permission_settings.dart';
import 'package:real_estate_mobile/core/platform/voice_capture_controller.dart';
import 'package:real_estate_mobile/core/platform/voice_input.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/properties/data/listing_account_draft_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/listing_account_draft.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_editor_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_draft_photo.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_location_picker_screen.dart';
import 'broker_experience_ui_test.dart' show BrokerTestAuth;
import 'support/wave3_fakes.dart';
import 'support/wave6_fakes.dart';
import 'wave6_product_ui_test.dart' show pumpWave6,editorSnapshot,finishWave6,textField,previewWave6;

const _png='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

DioException _offline([int? status]) => DioException(requestOptions:RequestOptions(path:'/fixture'),
  type:status==null ? DioExceptionType.connectionError:DioExceptionType.badResponse,
  response:status==null ? null:Response(requestOptions:RequestOptions(),statusCode:status,data:{'message':'الشبكة غير متاحة'}));

class _Drafts extends Wave6Drafts {
  bool failSave=false, failOneUpload=false,failTransport=false;
  int? failUploadNumber;
  Completer<void>? saveGate, uploadGate;
  final attempts=<String,int>{};
  int uploadCount=0;
  @override
  Future<ListingAccountDraft> save(String key,Map<String,dynamic> payload,int revision,{int? propertyId}) async {
    await saveGate?.future;
    if(failSave) { throw _offline(); }
    return super.save(key,payload,revision,propertyId:propertyId);
  }
  @override
  Future<ListingAccountDraft> upload(String key,String imageKey,String path,int revision,{CancelToken? cancelToken,ProgressCallback? onSendProgress}) async {
    attempts.update(imageKey,(n)=>n+1,ifAbsent:()=>1);uploadCount++;
    onSendProgress?.call(5,10);
    if(uploadGate!=null) {
      await Future.any([uploadGate!.future,if(cancelToken!=null)cancelToken.whenCancel.then((error)=>throw error)]);
    }
    if(cancelToken?.isCancelled==true) { throw _offline(); }
    if(failOneUpload && uploadCount==failUploadNumber) { failOneUpload=false;throw _offline(failTransport ? null:503); }
    onSendProgress?.call(10,10);
    return super.upload(key,imageKey,path,revision,cancelToken:cancelToken,onSendProgress:onSendProgress);
  }
  @override
  Future<ListingAccountDraft> get(String key) async {
    if(!drafts.containsKey(key)) { throw _offline(404); }
    return super.get(key);
  }
}
class _RecoveredProperties extends Wave6Properties {
  @override
  Future<PropertyDetails> details(int id) async=>PropertyDetails.fromJson({'id':id,'title':'إعلان محفوظ','type':'house','purpose':'sale','price':10000000,
    'currency':'YER','status':'draft','review_status':'draft','address':'صنعاء حدة','latitude':15.37,'longitude':44.19,
    'images':[{'id':501,'url':'https://fixture.example/api/property-media/501','sort_order':0,'is_primary':true}]});
}
class _RecoveryFailure extends Wave6Recovery {
  _RecoveryFailure(super.snapshot);
  @override
  Future<void> write(int userId,int? listingId,Map<String,dynamic> data,List<String> paths) async => throw FileSystemException('Device is full');
}
class _Auth implements AuthRepository {
  String token='account-a';
  @override
  Future<Options> requiredAuthOptions() async=>Options(headers:{'Authorization':'Bearer $token'});
  @override
  dynamic noSuchMethod(Invocation invocation)=>throw UnimplementedError();
}
class _SwitchAuth extends BrokerTestAuth {
  _SwitchAuth():super(1);
  void switchTo(int id) { state=AsyncData(AuthUser.fromJson({'id':id,'name':'حساب اختبار','phone':'+967771234567','account_status':'active',
    'phone_verified_at':'2026-10-21T00:00:00Z','profile_completed_at':'2026-10-21T00:00:00Z','verification_profile':{'type':'broker','status':'approved'}})); }
}

Map<String,dynamic> _photos(Directory dir,int count) {
  final data=editorSnapshot(),tokens=<String,String>{},paths=<String>[];
  for(var i=0;i<count;i++) {
    final file=File('${dir.path}/photo-$i.png')..writeAsBytesSync(base64Decode(_png));
    paths.add(file.path);tokens[file.path]=newListingDraftKey();
  }
  return {...data,'media_version':1,'image_paths':paths,'image_tokens':tokens,'image_order':tokens.values.toList()};
}

Widget _host({bool fresh=false}) => Builder(builder:(context)=>Scaffold(body:TextButton(
  onPressed:()=>Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>ListingEditorScreen(startFresh:fresh))),child:const Text('فتح المحرر'))));
Future<void> _open(WidgetTester tester) async { await tester.tap(find.text('فتح المحرر'));await tester.pumpAndSettle(); }
Future<void> _back(WidgetTester tester) async { await tester.binding.handlePopRoute();await tester.pumpAndSettle(); }

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fonts=[('PrimaryFont','assets/ebroker/fonts/Manrope-Regular.ttf'),('NotoSansArabic','assets/fonts/NotoSansArabic-Regular.ttf'),('sans-serif','assets/fonts/NotoSansArabic-Regular.ttf')];
    for(final (family,path) in fonts) { final loader=FontLoader(family)..addFont(rootBundle.load(path));await loader.load(); }
    final icons=await File('${Platform.environment['FLUTTER_ROOT']!}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytes();
    await (FontLoader('MaterialIcons')..addFont(Future.value(icons.buffer.asByteData()))).load();
  });

  test('device recovery keeps stable photo keys, order, point and private proof after source cache disappears',() async {
    final dir=await Directory.systemTemp.createTemp('listing-recovery-media-');addTearDown(()=>dir.delete(recursive:true));
    final support=Directory('${dir.path}/support'),store=ListingRecoveryStore(directory:()async=>support);
    final data=_photos(dir,3),originals=(data['image_paths'] as List).cast<String>();
    final proof=File('${dir.path}/proof.png')..writeAsBytesSync(base64Decode(_png));data['ownership_proof_path']=proof.path;
    final order=(data['image_order'] as List).cast<String>().reversed.toList();data['image_order']=order;
    await store.write(1,null,data,originals);
    for(final path in originals) { await File(path).delete(); }await proof.delete();
    final restored=(await store.read(1,null))!;
    expect(restored['image_order'],order);expect(restored['latitude'],data['latitude']);expect(restored['longitude'],data['longitude']);
    final paths=(restored['image_paths'] as List).cast<String>(),tokens=restored['image_tokens'] as Map;
    expect(paths,hasLength(3));expect(tokens.values.toSet(),order.toSet());
    for(final path in paths) { expect(await File(path).readAsBytes(),base64Decode(_png));expect(ListingRecoveryStore.isSavedMedia(path),true); }
    expect(await File(restored['ownership_proof_path'] as String).readAsBytes(),base64Decode(_png));
    expect(await store.read(2,null),isNull);
    await store.write(1,null,restored,paths);expect((await store.read(1,null))!['image_order'],order);
  });

  test('failed durable write preserves last valid snapshot and the queue accepts a later retry',() async {
    final dir=await Directory.systemTemp.createTemp('listing-atomic-');addTearDown(()=>dir.delete(recursive:true));
    final store=ListingRecoveryStore(directory:()async=>Directory('${dir.path}/support'));
    final data=_photos(dir,1),paths=(data['image_paths'] as List).cast<String>();
    await store.write(4,11,data,paths);
    await expectLater(store.write(4,11,{...data,'fields':{'title':'uncommitted'}},['${dir.path}/missing.png']),throwsA(isA<FileSystemException>()));
    expect(((await store.read(4,11))!['fields'] as Map)['title'],'عقار للاختبار');
    expect(await store.read(5,11),isNull);expect(await store.read(4,12),isNull);
    await store.write(4,11,{...data,'fields':{'title':'محاولة مؤكدة'}},paths);
    expect(((await store.read(4,11))!['fields'] as Map)['title'],'محاولة مؤكدة');
  });

  test('private photo reads never forward an account token to another origin or unrelated route',() async {
    final dio=Dio(BaseOptions(baseUrl:'https://fixture.example/api')),auth=_Auth(),repo=ListingAccountDraftRepository(dio,auth);
    var calls=0;dio.interceptors.add(InterceptorsWrapper(onRequest:(o,h){calls++;expect(o.headers['Authorization'],'Bearer account-a');h.resolve(Response(requestOptions:o,statusCode:200,data:base64Decode(_png)));}));
    await expectLater(repo.photo('https://foreign.example/api/listing-editor-drafts/key/images/image'),throwsStateError);
    await expectLater(repo.photo('https://fixture.example/api/admin/users'),throwsStateError);
    expect(calls,0);
    await repo.photo('https://fixture.example/api/property-media/11?variant=detail');expect(calls,1);dio.close();
  });

  test('draft repositories capture their originating account session',() async {
    final dio=Dio(BaseOptions(baseUrl:'https://fixture.example/api')),auth=_Auth(),first=ListingAccountDraftRepository(dio,auth),seen=<String>[];
    auth.token='account-b';final second=ListingAccountDraftRepository(dio,auth);
    dio.interceptors.add(InterceptorsWrapper(onRequest:(o,h){seen.add(o.headers['Authorization'] as String);h.resolve(Response(requestOptions:o,statusCode:200,data:{'data':[]}));}));
    await first.list();await second.list();expect(seen,['Bearer account-a','Bearer account-b']);dio.close();
  });

  test('image models select safe gallery and zoom derivatives and preserve legacy fallback',() {
    final item=PropertyImageItem.fromJson({'id':1,'url':'detail','sort_order':0,'is_primary':true,'variants':{'gallery':'gallery','zoom':'zoom'}});
    expect(item.galleryUrl,'gallery');expect(item.zoomUrl,'zoom');
    final legacy=PropertyImageItem.fromJson({'id':2,'url':'legacy'});expect(legacy.galleryUrl,'legacy');expect(legacy.zoomUrl,'legacy');
  });

  testWidgets('unchanged editor exits without an extra warning or an empty recovery draft',(tester) async {
    final recovery=Wave6Recovery(),drafts=_Drafts();
    await pumpWave6(tester,_host(fresh:true),recovery:recovery,drafts:drafts);await _open(tester);
    await _back(tester);expect(find.text('فتح المحرر'),findsOneWidget);expect(find.text('لديك تعديلات غير محفوظة'),findsNothing);
    expect(recovery.snapshot,isNull);expect(drafts.saves,isEmpty);await finishWave6(tester);
  },timeout:const Timeout(Duration(seconds:45)));

  testWidgets('offline edits keep text and confirmed point, and a failed exit save stays in the editor',(tester) async {
    final recovery=Wave6Recovery(editorSnapshot()),drafts=_Drafts()..failSave=true;
    await pumpWave6(tester,_host(),recovery:recovery,drafts:drafts);await _open(tester);
    final description=textField('وصف العقار');await tester.ensureVisible(description);await tester.enterText(description,'مجلس ومدخل مستقل — الشبكة انقطعت');
    await tester.pump(const Duration(seconds:1));await tester.pumpAndSettle();
    expect((recovery.snapshot!['fields'] as Map)['description'],'مجلس ومدخل مستقل — الشبكة انقطعت');
    expect(recovery.snapshot!['latitude'],15.37);expect(recovery.snapshot!['longitude'],44.19);
    await _back(tester);expect(find.byKey(const ValueKey('listing-exit-save')),findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('listing-exit-save')));await tester.pumpAndSettle();
    expect(find.byType(ListingEditorScreen),findsOneWidget);expect(find.textContaining('لم يكتمل حفظ المسودة'),findsOneWidget);
    expect(tester.widget<TextField>(description).controller!.text,'مجلس ومدخل مستقل — الشبكة انقطعت');
    expect(find.text('حُفظ تقدمك وصورك على حسابك'),findsNothing);
    drafts.failSave=false;await _back(tester);await tester.tap(find.byKey(const ValueKey('listing-exit-save')));await tester.pumpAndSettle();
    expect(find.text('فتح المحرر'),findsOneWidget);await finishWave6(tester);
  },timeout:const Timeout(Duration(seconds:45)));

  testWidgets('failed local save also prevents the exit save from closing the editor',(tester) async {
    final recovery=_RecoveryFailure(editorSnapshot());
    await pumpWave6(tester,_host(),recovery:recovery,drafts:_Drafts());await _open(tester);
    await tester.ensureVisible(textField('وصف العقار'));await tester.enterText(textField('وصف العقار'),'تغيير لم يحفظه الجهاز');
    await tester.pump(const Duration(seconds:1));await tester.pumpAndSettle();
    await _back(tester);await tester.tap(find.byKey(const ValueKey('listing-exit-save')));await tester.pumpAndSettle();
    expect(find.byType(ListingEditorScreen),findsOneWidget);expect(find.textContaining('لم يكتمل حفظ المسودة'),findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());await tester.pump();
  },timeout:const Timeout(Duration(seconds:45)));

  testWidgets('a late checkpoint response cannot announce that newer edits were saved',(tester) async {
    final gate=Completer<void>(),drafts=_Drafts()..saveGate=gate,recovery=Wave6Recovery(editorSnapshot());
    await pumpWave6(tester,const ListingEditorScreen(),recovery:recovery,drafts:drafts);
    final description=textField('وصف العقار');await tester.ensureVisible(description);await tester.enterText(description,'النسخة الأولى');await tester.pump(const Duration(seconds:1));
    await tester.enterText(description,'آخر تعديل لم يصل بعد');await tester.pump(const Duration(milliseconds:100));
    gate.complete();drafts.saveGate=Completer<void>();await tester.pump();await tester.pump();
    expect(tester.widget<TextField>(description).controller!.text,'آخر تعديل لم يصل بعد');
    expect(find.text('حُفظ تقدمك وصورك على حسابك'),findsNothing);
    drafts.saveGate!.complete();await tester.pump(const Duration(seconds:1));await tester.pumpAndSettle();await finishWave6(tester);
  },timeout:const Timeout(Duration(seconds:45)));

  for(final scale in [1.0,2.4]) {
    testWidgets('one failed photo keeps successful files and retries only that file at $scale',(tester) async {
      final dir=Directory.systemTemp.createTempSync('listing-partial-');addTearDown(()=>dir.deleteSync(recursive:true));
      final data=_photos(dir,3),recovery=Wave6Recovery(data),drafts=_Drafts()..failOneUpload=true..failUploadNumber=2;
      final boundary=GlobalKey();await pumpWave6(tester,const ListingEditorScreen(),recovery:recovery,drafts:drafts,scale:scale,boundary:boundary);
      final description=textField('وصف العقار');await tester.ensureVisible(description);await tester.enterText(description,'صور مستقلة للحفظ');
      await tester.pump(const Duration(seconds:1));await tester.pumpAndSettle();
      expect(drafts.uploadCount,3);expect(drafts.drafts.values.single.images.length,2);
      final tokens=(data['image_tokens'] as Map).values.cast<String>().toList(),failed=tokens[1];
      final retry=find.byKey(ValueKey('media-retry-$failed'));await tester.ensureVisible(retry);await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('صور الإعلان (3/12)'));await tester.pumpAndSettle();
      await previewWave6(tester,boundary,'batch1-photo-failure-$scale');
      await tester.ensureVisible(retry);await tester.tap(retry);await tester.pumpAndSettle();
      expect(drafts.attempts[tokens[0]],1);expect(drafts.attempts[failed],2);expect(drafts.attempts[tokens[2]],1);
      expect(drafts.drafts.values.single.images.length,3);
      expect(recovery.snapshot!['latitude'],15.37);expect(recovery.snapshot!['longitude'],44.19);
      expect(tester.takeException(),isNull);await finishWave6(tester);
    },timeout:const Timeout(Duration(seconds:45)));
  }

  testWidgets('connection loss pauses untouched photos until a deliberate retry',(tester) async {
    final dir=Directory.systemTemp.createTempSync('listing-offline-');addTearDown(()=>dir.deleteSync(recursive:true));
    final data=_photos(dir,3),drafts=_Drafts()..failOneUpload=true..failUploadNumber=1..failTransport=true;
    await pumpWave6(tester,const ListingEditorScreen(),recovery:Wave6Recovery(data),drafts:drafts);
    await tester.ensureVisible(textField('وصف العقار'));await tester.enterText(textField('وصف العقار'),'الصور باقية دون اتصال');
    await tester.pump(const Duration(seconds:1));await tester.pumpAndSettle();expect(drafts.uploadCount,1);
    final first=(data['image_order'] as List).first as String,retry=find.byKey(ValueKey('media-retry-$first'));
    await tester.ensureVisible(retry);await tester.tap(retry);await tester.pumpAndSettle();
    expect(drafts.uploadCount,4);expect(drafts.drafts.values.single.images,hasLength(3));await finishWave6(tester);
  },timeout:const Timeout(Duration(seconds:45)));

  testWidgets('a lost listing response recovers committed photo aliases without uploading them again',(tester) async {
    final dir=Directory.systemTemp.createTempSync('listing-promoted-');addTearDown(()=>dir.deleteSync(recursive:true));
    final data=_photos(dir,1),token=(data['image_order'] as List).single as String,key=newListingDraftKey(),checkpoint=newListingDraftKey();
    data.addAll({'draft_key':key,'server_revision':2,'account_checkpoint_key':checkpoint,'remote_images':{token:'https://fixture.invalid/$token'}});
    final recovery=Wave6Recovery(data),drafts=_Drafts();
    drafts.drafts[key]=ListingAccountDraft(key:key,revision:3,propertyId:55,images:const {},payload:{...data,
      'checkpoint_key':checkpoint,'image_order':['property-501'],'promoted_image_keys':{token:'property-501'}});
    await pumpWave6(tester,ProviderScope(overrides:[propertyRepositoryProvider.overrideWithValue(_RecoveredProperties())],child:const ListingEditorScreen()),recovery:recovery,drafts:drafts);
    final description=textField('وصف العقار');await tester.ensureVisible(description);await tester.enterText(description,'آخر تعديل بعد استعادة النتيجة');
    await tester.pump(const Duration(seconds:1));await tester.pumpAndSettle();
    expect(drafts.uploadCount,0);expect(drafts.saves.last['image_order'],['property-501']);
    expect(drafts.drafts[key]!.propertyId,55);expect(recovery.snapshot!['image_paths'],isEmpty);
    expect(recovery.snapshot!['latitude'],15.37);expect(recovery.snapshot!['longitude'],44.19);await finishWave6(tester);
  },timeout:const Timeout(Duration(seconds:45)));

  testWidgets('deleting a pending photo cancels its upload and cannot restore it from a late result',(tester) async {
    final dir=Directory.systemTemp.createTempSync('listing-cancel-');addTearDown(()=>dir.deleteSync(recursive:true));
    final data=_photos(dir,1),recovery=Wave6Recovery(data),gate=Completer<void>(),drafts=_Drafts()..uploadGate=gate;
    await pumpWave6(tester,const ListingEditorScreen(),recovery:recovery,drafts:drafts);
    await tester.ensureVisible(textField('وصف العقار'));await tester.enterText(textField('وصف العقار'),'ارفع هذه الصورة');await tester.pump(const Duration(seconds:1));await tester.pump();
    final remove=find.byTooltip('إزالة الصورة');await tester.ensureVisible(remove);await tester.tap(remove);await tester.pump();gate.complete();
    await tester.pump(const Duration(seconds:1));await tester.pumpAndSettle();
    expect(recovery.snapshot!['image_order'],isEmpty);expect(find.byTooltip('إزالة الصورة'),findsNothing);expect(drafts.drafts.values.single.images,isEmpty);
    await finishWave6(tester);
  },timeout:const Timeout(Duration(seconds:45)));

  testWidgets('permanent location denial offers settings and the manual map action remains available',(tester) async {
    var opened=0;
    await pumpWave6(tester,ProviderScope(overrides:[
      propertyCurrentLocationProvider.overrideWithValue(()async=>throw PlatformException(code:'LOCATION_DENIED_FOREVER',message:'إذن الموقع مرفوض نهائيًا')),
      appPermissionSettingsProvider.overrideWithValue(()async{opened++;return true;}),
    ],child:const ListingEditorScreen()),recovery:Wave6Recovery({...editorSnapshot(),'step':1}));
    await tester.tap(find.byKey(const ValueKey('listing-current-location')));await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('listing-select-location')).hitTestable(),findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('listing-location-settings')));expect(opened,1);await finishWave6(tester);
  },timeout:const Timeout(Duration(seconds:45)));

  test('microphone denial stays explicit and text input remains available',() async {
    final voice=Wave3VoiceFake(autoComplete:false),capture=VoiceCaptureController(voice);
    final pending=capture.start();voice.latest.emit(const VoiceEvent('error',code:'SPEECH_PERMISSION_PERMANENT'));
    expect(await pending,isNull);expect(capture.permissionDenied,true);expect(capture.error,contains('اكتب'));
    capture.dispose();await voice.dispose();
  },timeout:const Timeout(Duration(seconds:45)));

  testWidgets('account switching hides the former account editor while keeping its recovery scoped',(tester) async {
    final recovery=Wave6Recovery(editorSnapshot());
    await pumpWave6(tester,ProviderScope(overrides:[authControllerProvider.overrideWith(()=>_SwitchAuth())],child:const ListingEditorScreen()),recovery:recovery);
    final scope=ProviderScope.containerOf(tester.element(find.byType(ListingEditorScreen)));
    (scope.read(authControllerProvider.notifier) as _SwitchAuth).switchTo(2);await tester.pumpAndSettle();
    expect(find.byType(TextField),findsNothing);expect(find.textContaining('تغيّر الحساب'),findsOneWidget);
    await finishWave6(tester);
  },timeout:const Timeout(Duration(seconds:45)));

  testWidgets('private photo loading failure has a retry action instead of an endless placeholder',(tester) async {
    final drafts=_PhotoFailure();await pumpWave6(tester,const SizedBox(width:170,height:120,child:ListingDraftPhoto(url:'https://fixture.invalid/private')),drafts:drafts);
    expect(find.text('إعادة تحميل الصورة'),findsOneWidget);final before=drafts.calls;expect(before,greaterThanOrEqualTo(1));
    await tester.tap(find.text('إعادة تحميل الصورة'));await tester.pumpAndSettle();expect(drafts.calls,before+1);await finishWave6(tester);
  },timeout:const Timeout(Duration(seconds:45)));
}

class _PhotoFailure extends Wave6Drafts {
  int calls=0;
  @override
  Future<Uint8List> photo(String url) async { calls++;throw _offline(); }
}

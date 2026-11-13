import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:real_estate_mobile/core/local/stage6_secure_session_store.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/discovery/data/ai_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_search_session.dart';
import 'package:real_estate_mobile/features/discovery/data/smart_search_session.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/property_schema.dart';
import 'package:real_estate_mobile/phase23_native_callback_main.dart';

class _Auth extends AuthController {
  @override
  Future<AuthUser?> build() async => AuthUser.fromJson({'id':66,'name':'Synthetic A','account_status':'active'});
  void replace() {
    Stage6SecureSessionStore.instance.beginSessionChange();
    state=AsyncData(AuthUser.fromJson({'id':26,'name':'Synthetic B','account_status':'active'}));
  }
}
void main() {
  test('alternate callback target rejects every non-pinned environment', () {
    expect(callbackHarnessAllowed(enabled:true,environment:'uat',api:callbackApi),isTrue);
    for(final environment in ['production','local','UAT','']) {
      expect(callbackHarnessAllowed(enabled:true,environment:environment,api:callbackApi),isFalse);
    }
    expect(callbackHarnessAllowed(enabled:false,environment:'uat',api:callbackApi),isFalse);
    expect(callbackHarnessAllowed(enabled:true,environment:'uat',api:'https://other.invalid/api'),isFalse);
  });
  test('all provider endpoints fail before a transport adapter is called', () async {
    final dio=Dio(BaseOptions(baseUrl:callbackApi))..interceptors.add(CallbackReadOnlyTransport());
    var sent=0;
    dio.interceptors.add(InterceptorsWrapper(onRequest:(r,h){sent++;h.resolve(Response(requestOptions:r,statusCode:200));}));
    for(final path in ['/ai/search','/ai/listing-description','/properties/106/ask', '$callbackApi/ai/search']) {
      await expectLater(dio.post<dynamic>(path),throwsA(isA<DioException>()));
    }
    expect(sent,0);
    await dio.get<dynamic>('/auth/me');expect(sent,1);
    dio.close();
  });
  test('business writes cannot reach transport; only pinned normal phone login/logout are permitted', () async {
    final dio=Dio(BaseOptions(baseUrl:callbackApi))..interceptors.add(CallbackReadOnlyTransport());
    var sent=0;
    dio.interceptors.add(InterceptorsWrapper(onRequest:(r,h){sent++;h.resolve(Response(requestOptions:r,statusCode:200));}));
    for(final path in ['/account/erase','/listing-editor-drafts','/notifications/read-all','/properties','/auth/profile']) {
      await expectLater(dio.post<dynamic>(path),throwsA(isA<DioException>()));
      await expectLater(dio.delete<dynamic>(path),throwsA(isA<DioException>()));
      await expectLater(dio.put<dynamic>(path),throwsA(isA<DioException>()));
    }
    await expectLater(dio.post<dynamic>('https://other.invalid/api/auth/logout'),throwsA(isA<DioException>()));
    expect(sent,0);
    for(final path in ['/auth/whatsapp/start','/auth/whatsapp/verify','/auth/logout']) {
      await dio.post<dynamic>(path);
    }
    expect(sent,3);dio.close();
  });
  test('ordinary push cleanup remains blocked and is distinguished from unexpected writes', () async {
    var writes=0,cleanup=0,sent=0;
    final dio=Dio(BaseOptions(baseUrl:callbackApi))..interceptors.add(CallbackReadOnlyTransport(
      onForbiddenWrite:()=>writes++,onBlockedPushCleanup:()=>cleanup++));
    dio.interceptors.add(InterceptorsWrapper(onRequest:(r,h){sent++;h.resolve(Response(requestOptions:r,statusCode:200));}));
    await expectLater(dio.delete<dynamic>('/push/devices'),throwsA(isA<DioException>()));
    expect(cleanup,1);expect(writes,0);expect(sent,0);
    await expectLater(dio.post<dynamic>('/listing-editor-drafts'),throwsA(isA<DioException>()));
    expect(writes,1);expect(cleanup,1);expect(sent,0);dio.close();
  });
  test('held completions ignore cancellation but actual account-bound controllers reject both after B', () async {
    final auth=_Auth(),gate=CallbackGate(),dio=Dio();final repo=AuthRepository(dio);
    final scope=ProviderContainer(overrides:[authControllerProvider.overrideWith(()=>auth),
      aiRepositoryProvider.overrideWithValue(CallbackAiRepository(dio,repo,gate)),
      propertyRepositoryProvider.overrideWithValue(CallbackPropertyRepository(dio,repo,gate))]);
    addTearDown(scope.dispose);addTearDown(dio.close);
    await scope.read(authControllerProvider.future);
    gate.actor=()=>scope.read(authControllerProvider).asData?.value?.id;
    gate.aiSession=()=>scope.read(smartSearchSessionProvider.notifier);
    gate.resultsSession=()=>scope.read(homeSearchResultsProvider.notifier);
    gate.startAi();gate.startResults();final gps=gate.captureGps();
    expect(gate.aiStatus,'CB AI held');expect(gate.resultsStatus,'CB results held');
    expect(()=>gate.seedB(),throwsStateError);
    expect(gate.aiReply!.isCompleted,isFalse);expect(gate.resultsReply!.isCompleted,isFalse);
    auth.replace();gate.recordActor(26);gate.seedB();
    final beforeAI=callbackState(scope.read(smartSearchSessionProvider)),beforeResults=callbackState(scope.read(homeSearchResultsProvider));
    await gate.releaseAi();await gate.releaseResults();
    expect(gate.aiStatus,'CB AI PASS');expect(gate.resultsStatus,'CB results PASS');
    expect(gate.aiComplete,greaterThan(gate.bSeedOrder));expect(gate.resultsComplete,greaterThan(gate.bLoginOrder));
    expect(gate.oldResultsTransfer!.isCancelled,isTrue);expect(gate.forbiddenOldSearches,0);expect(gate.errors,0);
    expect(callbackState(scope.read(smartSearchSessionProvider)),beforeAI);
    expect(callbackState(scope.read(homeSearchResultsProvider)),beforeResults);
    // Settle the separately held GPS transport; real widget GPS fencing is also
    // covered in branch2_location_test and exercised by the native editor.
    gate.gpsReply!.completeError(StateError('unit cleanup'));
    await expectLater(gps,throwsStateError);
  });
  testWidgets('Android evidence has distinct visible semantic nodes with the complete numeric schema', (tester) async {
    final gate=CallbackGate()..actor=()=>66;
    final semantics=tester.ensureSemantics();addTearDown(semantics.dispose);
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:CallbackReadout(gate:gate))));
    expect(find.bySemanticsLabel(callbackHarnessMarker),findsOneWidget);
    final label='CB-META:${jsonEncode(gate.metadata)}';
    expect(find.bySemanticsLabel(label),findsOneWidget);
    final node=tester.getSemantics(find.bySemanticsLabel(label));
    expect(node.getSemanticsData().label,label);expect(node.rect.height,greaterThan(20));
    expect(jsonDecode(node.getSemanticsData().label.substring(8))['actor'],1);
  });
  test('partial editor fixture cannot begin automatic account saving', () {
    final progress=DynamicPropertySchema.draftProgress({'editor_version':11,'draft_kind':'recovery',
      'type':'apartment','purpose':'rent','type_confirmed':true,'purpose_confirmed':true,'fields':{'title':editorTitleB}});
    expect(progress,lessThan(50));expect(DynamicPropertySchema.canBeginAutomaticSave(progress),isFalse);
  });
}

import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/local/stage6_secure_session_store.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/properties/data/listing_account_draft_repository.dart';

class _Auth implements AuthRepository {
  @override
  Future<Options> requiredAuthOptions() async => Options(headers:{'Authorization':'Bearer synthetic-original'});
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an old draft repository cannot start a request after logout begins', () async {
    final dio=Dio(BaseOptions(baseUrl:'https://fixture.example/api'));
    addTearDown(dio.close);
    var requests=0;
    dio.interceptors.add(InterceptorsWrapper(onRequest:(o,h) {
      requests++;h.resolve(Response(requestOptions:o,data:{'data':[]},statusCode:200));
    }));
    final repository=ListingAccountDraftRepository(dio,_Auth(),actorId:41);
    Stage6SecureSessionStore.instance.beginSessionChange();
    await expectLater(repository.list(),throwsStateError);
    expect(requests,0);
  });

  test('a late draft response is discarded when the account changes in flight', () async {
    final dio=Dio(BaseOptions(baseUrl:'https://fixture.example/api'));
    addTearDown(dio.close);
    final started=Completer<void>(), release=Completer<void>();
    dio.interceptors.add(InterceptorsWrapper(onRequest:(o,h) async {
      expect(o.headers['Authorization'],'Bearer synthetic-original');
      started.complete();await release.future;
      h.resolve(Response(requestOptions:o,statusCode:200,data:{'data':[]}));
    }));
    final repository=ListingAccountDraftRepository(dio,_Auth(),actorId:41);
    final pending=repository.list();
    final assertion=expectLater(pending,throwsStateError);
    await started.future;
    Stage6SecureSessionStore.instance.beginSessionChange();release.complete();
    await assertion;
  });
}

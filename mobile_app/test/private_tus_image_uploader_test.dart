import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/local/stage6_secure_session_store.dart';
import 'package:real_estate_mobile/features/properties/data/private_tus_image_uploader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('resumes a partial private upload after interrupted PATCH without replaying the first chunk', () async {
    final folder = await Directory.systemTemp.createTemp('aqer-tus-test-');
    addTearDown(() async { if(await folder.exists()) await folder.delete(recursive:true); });
    final source = File('${folder.path}/image.png');
    await source.writeAsBytes(List<int>.filled(PrivateTusImageUploader.chunkSize+3,42));
    final dio=Dio();
    var remoteOffset=0, creations=0, failed=false;
    final patchOffsets=<int>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest:(request,handler) {
      final method=request.method;
      if(method=='POST') {
        creations++;
        handler.resolve(Response(requestOptions:request,statusCode:201,
          headers:Headers.fromMap({'location':['/storage/v1/upload/resumable/session-1']})));
      } else if(method=='HEAD') {
        handler.resolve(Response(requestOptions:request,statusCode:200,
          headers:Headers.fromMap({'upload-offset':['$remoteOffset']})));
      } else if(method=='PATCH') {
        final offset=int.parse(request.headers['Upload-Offset'].toString());
        patchOffsets.add(offset);
        if(offset==PrivateTusImageUploader.chunkSize && !failed) {
          failed=true;
          handler.reject(DioException(requestOptions:request,type:DioExceptionType.connectionError));
          return;
        }
        final bytes=request.data as List<int>;
        remoteOffset+=bytes.length;
        handler.resolve(Response(requestOptions:request,statusCode:204,
          headers:Headers.fromMap({'upload-offset':['$remoteOffset']})));
      } else { handler.reject(DioException(requestOptions:request)); }
    }));
    final uploader=PrivateTusImageUploader(dio,directory:()async=>folder);
    Future<void> perform()=>uploader.upload(source:source.path,scope:'account-A/draft/image',
      endpoint:'https://store.example/storage/v1/upload/resumable/sign',bucket:'private',
      objectName:'private/editor-drafts/test.png',signature:'signed-only',publishableKey:'sb_publishable_demo',mime:'image/png',
      cancelToken:CancelToken());
    await expectLater(perform(),throwsA(isA<DioException>()));
    expect(remoteOffset,PrivateTusImageUploader.chunkSize);
    await perform();
    expect(creations,1);
    expect(patchOffsets,[0,PrivateTusImageUploader.chunkSize,PrivateTusImageUploader.chunkSize]);
    expect(remoteOffset,PrivateTusImageUploader.chunkSize+3);
    // Simulate a lost Laravel finalize reply: completed HEAD reuses the
    // session and sends zero additional bytes before finalization is retried.
    await perform();
    expect(creations,1);
    expect(patchOffsets.length,3);
    await uploader.forget('account-A/draft/image');
    expect(Directory('${folder.path}/aqer_tus').listSync(),isEmpty);
  });

  test('rejects cross-origin upload location', () async {
    final folder=await Directory.systemTemp.createTemp('aqer-tus-origin-');
    addTearDown(() async { if(await folder.exists()) await folder.delete(recursive:true); });
    final source=File('${folder.path}/image.png')..writeAsBytesSync([1,2,3]);
    final dio=Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest:(o,h)=>h.resolve(
      Response(requestOptions:o,statusCode:201,
        headers:Headers.fromMap({'location':['https://attacker.example/upload']})))));
    final uploader=PrivateTusImageUploader(dio,directory:()async=>folder);
    await expectLater(uploader.upload(source:source.path,scope:'account-A',
      endpoint:'https://store.example/storage/v1/upload/resumable/sign',bucket:'private',
      objectName:'photo',signature:'token',publishableKey:'sb_publishable_demo',mime:'image/png',cancelToken:CancelToken()),throwsStateError);
  });

  for (final stage in ['POST', 'HEAD', 'PATCH']) {
    test('account change during $stage cannot continue or acknowledge an old upload', () async {
      final folder = await Directory.systemTemp.createTemp('aqer-tus-session-');
      addTearDown(() => folder.delete(recursive:true));
      final source = File('${folder.path}/photo.png')..writeAsBytesSync([1,2,3]);
      final dio = Dio();
      final methods = <String>[];
      var change = false;
      dio.interceptors.add(InterceptorsWrapper(onRequest:(o,h) {
        methods.add(o.method);
        if (change && o.method == stage) {
          Stage6SecureSessionStore.instance.beginSessionChange();
        }
        h.resolve(Response(requestOptions:o,statusCode:o.method=='POST'?201:204,
          headers:Headers.fromMap({'location':['/storage/v1/upload/resumable/session-safe'],
            'upload-offset':['3']})));
      }));
      Future<void> perform(PrivateTusImageUploader uploader) => uploader.upload(
        source:source.path,scope:'session-$stage',
        endpoint:'https://store.example/storage/v1/upload/resumable/sign',bucket:'private',
        objectName:'photo',signature:'synthetic',publishableKey:'sb_publishable_demo',
        mime:'image/png',cancelToken:CancelToken());
      if (stage == 'HEAD') {
        await perform(PrivateTusImageUploader(dio,directory:()async=>folder));
        methods.clear();
      }
      var acknowledged = 0;
      final uploader=PrivateTusImageUploader(dio,directory:()async=>folder);
      change = true;
      await expectLater(uploader.upload(source:source.path,scope:'session-$stage',
        endpoint:'https://store.example/storage/v1/upload/resumable/sign',bucket:'private',
        objectName:'photo',signature:'synthetic',publishableKey:'sb_publishable_demo',
        mime:'image/png',cancelToken:CancelToken(),progress:(_,__)=>acknowledged++),throwsStateError);
      expect(acknowledged,0);
      expect(methods,stage=='PATCH'?['POST','PATCH']:[stage]);
      expect(Directory('${folder.path}/aqer_tus').listSync().whereType<File>()
        .where((file)=>file.path.endsWith('.tmp')),isEmpty);
      dio.close();
    });
  }

  test('concurrent calls for the same scope do not create competing uploads and can retry', () async {
    final folder=await Directory.systemTemp.createTemp('aqer-tus-concurrent-');
    addTearDown(()=>folder.delete(recursive:true));
    final source=File('${folder.path}/photo.png')..writeAsBytesSync([1,2,3]);
    final entered=Completer<void>(), release=Completer<void>();
    final dio=Dio(); var creations=0;
    dio.interceptors.add(InterceptorsWrapper(onRequest:(o,h) async {
      if(o.method=='POST') {
        creations++; if(!entered.isCompleted) entered.complete();
        await release.future;
      }
      h.resolve(Response(requestOptions:o,statusCode:o.method=='POST'?201:204,
        headers:Headers.fromMap({'location':['/storage/v1/upload/resumable/single'],
          'upload-offset':['3']})));
    }));
    final uploader=PrivateTusImageUploader(dio,directory:()async=>folder);
    Future<void> perform()=>uploader.upload(source:source.path,scope:'one-scope',
      endpoint:'https://store.example/storage/v1/upload/resumable/sign',bucket:'private',
      objectName:'photo',signature:'synthetic',publishableKey:'sb_publishable_demo',
      mime:'image/png',cancelToken:CancelToken());
    final first=perform(); await entered.future;
    await expectLater(perform(),throwsStateError);
    release.complete(); await first; await perform();
    expect(creations,1); dio.close();
  });

  test('storage never receives an API bearer or a privileged JWT key', () async {
    final folder=await Directory.systemTemp.createTemp('aqer-tus-credentials-');
    addTearDown(()=>folder.delete(recursive:true));
    final source=File('${folder.path}/photo.png')..writeAsBytesSync([1,2,3]);
    var calls=0;
    final dio=Dio(BaseOptions(headers:{'Authorization':'Bearer synthetic-api-only'}));
    dio.interceptors.add(InterceptorsWrapper(onRequest:(o,h){calls++;h.reject(DioException(requestOptions:o));}));
    Future<void> perform(String key)=>PrivateTusImageUploader(dio,directory:()async=>folder).upload(
      source:source.path,scope:'credential-test',endpoint:'https://store.example/storage/v1/upload/resumable/sign',
      bucket:'private',objectName:'photo',signature:'synthetic',publishableKey:key,mime:'image/png',cancelToken:CancelToken());
    await expectLater(perform('sb_publishable_demo'),throwsStateError);
    dio.options.headers.clear();
    final claims=base64Url.encode(utf8.encode(jsonEncode({'role':'service_role'}))).replaceAll('=','');
    await expectLater(perform('eyJhbGciOiJIUzI1NiJ9.$claims.synthetic'),throwsStateError);
    await expectLater(perform('eyJmalformed'),throwsStateError);
    expect(calls,0); dio.close();
  });
}

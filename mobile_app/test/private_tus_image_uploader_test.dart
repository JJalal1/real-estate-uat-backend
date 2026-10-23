import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
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
      endpoint:'https://store.example/storage/v1/upload/resumable',bucket:'private',
      objectName:'private/editor-drafts/test.png',signature:'signed-only',mime:'image/png',
      cancelToken:CancelToken());
    await expectLater(perform(),throwsA(isA<DioException>()));
    expect(remoteOffset,PrivateTusImageUploader.chunkSize);
    await perform();
    expect(creations,1);
    expect(patchOffsets,[0,PrivateTusImageUploader.chunkSize,PrivateTusImageUploader.chunkSize]);
    expect(remoteOffset,PrivateTusImageUploader.chunkSize+3);
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
      endpoint:'https://store.example/storage/v1/upload/resumable',bucket:'private',
      objectName:'photo',signature:'token',mime:'image/png',cancelToken:CancelToken()),throwsStateError);
  });
}

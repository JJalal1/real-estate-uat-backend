import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/network/adaptive_image_policy.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_draft_photo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const enabled=bool.fromEnvironment('AQER_LIVE_IMAGE_PROBE',defaultValue:false);
  test('real UAT Flutter policy and shared cache fetch fewer bytes and reuse on return', () async {
    HttpOverrides.global=null;
    final dio=Dio(BaseOptions(baseUrl:'https://real-estate-uat-api-frankfurt.onrender.com/api',
      connectTimeout:const Duration(seconds:80),receiveTimeout:const Duration(seconds:80)));
    addTearDown(()=>dio.close(force:true));
    final data=(await dio.get<dynamic>('/properties/60')).data['data'] as Map;
    expect(data['status'],'published');
    final url=(data['images'] as List).first['url'] as String;
    final policy=AdaptiveImagePolicy();
    final selected=policy.choose(use:PropertyImageUse.detail,logicalEdge:390,pixelRatio:3,
      network:const ImageNetworkConditions(metered:true,transport:'cellular',networkKey:'uat-fixture'));
    expect(selected,'card');
    final before=await dio.get<List<int>>(AdaptiveImagePolicy.variantUrl(url,'gallery'),options:Options(responseType:ResponseType.bytes));
    final cache=ListingPhotoCache();var calls=0, transferred=0;
    Future<Uint8List> fetch(CancelToken token) async {
      calls++;final response=await dio.get<List<int>>(AdaptiveImagePolicy.variantUrl(url,selected),
        options:Options(responseType:ResponseType.bytes,followRedirects:false),cancelToken:token);
      final bytes=Uint8List.fromList(response.data!);transferred+=bytes.length;return bytes;
    }
    final one=cache.acquire('public:fixture60:card',fetch),two=cache.acquire('public:fixture60:card',fetch);
    final results=await Future.wait([one.future,two.future]);one.close();two.close();
    final returned=cache.acquire('public:fixture60:card',fetch);await returned.future;returned.close();
    expect(calls,1);expect(transferred,results.first.length);expect(transferred,lessThan(before.data!.length));
    // Only aggregate synthetic byte counts, never URLs, tokens or photo data.
    stdout.writeln('AQER_FLUTTER_UAT_BYTES before=${before.data!.length} after=$transferred requests=$calls return_bytes=0');
    cache.clear();
  },skip:!enabled,timeout:const Timeout(Duration(minutes:4)));
}

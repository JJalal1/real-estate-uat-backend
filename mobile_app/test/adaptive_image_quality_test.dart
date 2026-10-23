import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/network/adaptive_image_policy.dart';
import 'package:real_estate_mobile/core/platform/media_network_monitor.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_draft_photo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const wifi = ImageNetworkConditions(metered:false,networkKey:'wifi-1',transport:'wifi');
  const cellular = ImageNetworkConditions(metered:true,networkKey:'cell-1',transport:'cellular');
  String pick(AdaptiveImagePolicy p, PropertyImageUse use, ImageNetworkConditions n, {double width=390,double dpr=3}) =>
    p.choose(use:use,logicalEdge:width,pixelRatio:dpr,network:n);
  test('cost policy, screen and explicit zoom select bounded server files', () {
    final p=AdaptiveImagePolicy();
    expect(pick(p,PropertyImageUse.thumbnail,wifi),'thumb');
    expect(pick(p,PropertyImageUse.card,wifi,width:100),'thumb');
    expect(pick(p,PropertyImageUse.card,wifi),'card');
    expect(pick(p,PropertyImageUse.card,cellular),'thumb');
    expect(pick(p,PropertyImageUse.detail,wifi),'detail');
    expect(pick(p,PropertyImageUse.detail,wifi,width:300),'preview');
    expect(pick(p,PropertyImageUse.detail,cellular),'card');
    expect(pick(p,PropertyImageUse.zoom,cellular),'zoom');
  });
  test('unknown links, metered Wi-Fi and OS Data Saver conserve data', () {
    final p=AdaptiveImagePolicy();
    for (final n in [const ImageNetworkConditions(),
      const ImageNetworkConditions(metered:true,transport:'wifi'),
      const ImageNetworkConditions(metered:false,dataSaver:true)]) {
      expect(pick(p,PropertyImageUse.detail,n),'card');
      expect(pick(p,PropertyImageUse.card,n),'thumb');
    }
    // Transport alone is never an assertion of cost or speed.
    expect(pick(p,PropertyImageUse.detail,const ImageNetworkConditions(metered:false,transport:'cellular')),'detail');
  });
  test('observed slow Wi-Fi downgrades; samples expire and never cross networks', () {
    var now=DateTime.utc(2026,10,24);
    final p=AdaptiveImagePolicy(clock:()=>now);
    p.recordTransfer(wifi,65536,const Duration(seconds:2));
    expect(pick(p,PropertyImageUse.detail,wifi),'card');
    expect(pick(p,PropertyImageUse.detail,const ImageNetworkConditions(metered:false,networkKey:'wifi-2')),'detail');
    now=now.add(const Duration(seconds:61));
    expect(pick(p,PropertyImageUse.detail,wifi),'detail');
    p.recordTransfer(wifi,200,const Duration(seconds:2));
    expect(p.isSlow(wifi),isFalse);
  });
  test('only canonical derivative routes are rewritten, preserving version', () {
    expect(AdaptiveImagePolicy.variantUrl('https://api.example/api/property-media/4?variant=zoom&v=approved','thumb'),
      'https://api.example/api/property-media/4?variant=thumb&v=approved');
    for(final url in ['https://cdn.example/source.jpg?token=legacy','https://api.example/api/private-documents/4',
      'https://user:pass@api.example/api/property-media/4']) {
      expect(AdaptiveImagePolicy.variantUrl(url,'thumb'),url);
    }
  });
  test('native state requests are deduplicated and missing bridge is conservative', () async {
    var calls=0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      MediaNetworkMonitor.channel,(call) async { calls++;return {'metered':false,'dataSaver':true,'networkKey':'fixture','transport':'wifi'}; });
    addTearDown(()=>TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MediaNetworkMonitor.channel,null));
    final monitor=MediaNetworkMonitor();
    final states=await Future.wait([monitor.snapshot(),monitor.snapshot()]);
    expect(calls,1); expect(states.first.metered,isFalse);expect(states.first.dataSaver,isTrue);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      MediaNetworkMonitor.channel,(_) async => throw PlatformException(code:'unavailable'));
    expect((await MediaNetworkMonitor().snapshot()).metered,isNull);
  });
  test('shared leases transfer once and cancel only after the last viewer leaves', () async {
    final cache=ListingPhotoCache();final done=Completer<Uint8List>();
    CancelToken? token;var calls=0;
    Future<Uint8List> loader(CancelToken t) {calls++;token=t;return done.future;}
    final first=cache.acquire('public:image',loader),second=cache.acquire('public:image',loader);
    expect(calls,1);first.close();expect(token!.isCancelled,isFalse);
    second.close();expect(token!.isCancelled,isTrue);
    done.complete(Uint8List.fromList([1,2,3]));await first.future;
    var fresh=0;await cache.load('public:image',()async {fresh++;return Uint8List.fromList([4]);});
    expect(fresh,1);cache.clear();
  });
  test('returning to a completed image uses zero extra bytes; account clear forces a new request', () async {
    final cache=ListingPhotoCache();var calls=0;
    Future<Uint8List> load(CancelToken _)async {calls++;return Uint8List.fromList([1,2,3]);}
    final first=cache.acquire('private:image',load);await first.future;first.close();
    final returned=cache.acquire('private:image',load);await returned.future;returned.close();expect(calls,1);
    cache.clear();final other=cache.acquire('private:image',load);await other.future;other.close();expect(calls,2);
  });
  test('bounded cache does not evict a visible in-flight lease', () async {
    final cache=ListingPhotoCache(maxEntries:1);final a=Completer<Uint8List>(),b=Completer<Uint8List>();
    final one=cache.acquire('one',(_) => a.future),two=cache.acquire('two',(_) => b.future);
    a.complete(Uint8List.fromList([1]));b.complete(Uint8List.fromList([2]));
    await Future.wait([one.future,two.future]);one.close();two.close();cache.clear();
  });
}

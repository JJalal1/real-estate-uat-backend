import 'dart:io';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:real_estate_mobile/core/network/api_client.dart';
import 'package:real_estate_mobile/core/network/adaptive_image_policy.dart';
import 'package:real_estate_mobile/core/platform/media_network_monitor.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/broker/data/broker_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_repository.dart';
import 'package:real_estate_mobile/features/properties/data/favorites_repository.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/data/recent_properties_store.dart';
import '../broker_experience_ui_test.dart' show BrokerTestRepository;
import 'wave3_fakes.dart';
import 'wave6_fakes.dart';

// Every account, response and painted image in these tests is synthetic.
AuthUser uxUser({int id = 1, String? type, String status = 'approved', List<String> roles = const []}) => AuthUser.fromJson({
  'id': id, 'name': 'حساب اختبار الواجهة', 'account_type': type == 'broker' ? 'broker' : 'regular',
  'account_status': 'active', 'phone_verified_at': '2026-10-27T00:00:00Z',
  'profile_completed_at': '2026-10-27T00:00:00Z', 'roles': roles,
  if (type != null) 'verification_profile': {'type': type, 'status': status,
    if (status == 'approved') 'reviewed_at': '2026-10-27T00:00:00Z'},
});

class UxAuth extends AuthController {
  UxAuth(this.user);
  AuthUser? user;
  @override
  Future<AuthUser?> build() async => user;
  void change(AuthUser? next) { user = next; state = AsyncData(next); }
}
class _Credentials implements AuthRepository {
  @override
  Future<Options> requiredAuthOptions() async => Options(headers: {'Authorization': 'Bearer synthetic-ux-only'});
  @override
  Future<Options?> optionalAuthOptions() async => requiredAuthOptions();
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}
class _Network extends MediaNetworkMonitor {
  @override
  Future<ImageNetworkConditions> snapshot({bool refresh = false}) async => const ImageNetworkConditions(metered: false, transport: 'wifi');
}

late Uint8List uxImage;
Future<void> loadUxFixtures() async {
  await (FontLoader('NotoSansArabic')
    ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf'))).load();
  await (FontLoader('PrimaryFont')
    ..addFont(rootBundle.load('assets/ebroker/fonts/Manrope-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'))).load();
  final icons = await File('${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytes();
  await (FontLoader('MaterialIcons')..addFont(Future.value(icons.buffer.asByteData()))).load();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 900, 1200), Paint()..color = const Color(0xffa8d6f0));
  canvas.drawRect(const Rect.fromLTWH(0, 1000, 900, 200), Paint()..color = const Color(0xff8c969b));
  canvas.drawRect(const Rect.fromLTWH(130, 150, 640, 850), Paint()..color = const Color(0xffecd9ba));
  for (var row = 0; row < 4; row++) {
    for (var column = 0; column < 3; column++) {
      canvas.drawRect(Rect.fromLTWH(180 + column * 180.0, 210 + row * 180.0, 100, 125), Paint()..color = const Color(0xff234b63));
    }
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(900, 1200);
  uxImage = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  image.dispose(); picture.dispose();
}

ProviderContainer uxContainer({AuthUser? user, UxAuth? auth, BrokerRepository? broker, List<Override> extra = const []}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://real-estate-uat-api-frankfurt.onrender.com/api'));
  dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
    handler.resolve(Response(requestOptions: options, statusCode: 200,
      data: options.responseType == ResponseType.bytes ? uxImage : {'data': <Object>[], 'meta': {'total': 0}}));
  }));
  final container = ProviderContainer(overrides: [
    authControllerProvider.overrideWith(() => auth ?? UxAuth(user)),
    authRepositoryProvider.overrideWithValue(_Credentials()),
    dioProvider.overrideWithValue(dio),
    mediaNetworkMonitorProvider.overrideWithValue(_Network()),
    propertyRepositoryProvider.overrideWithValue(Wave6Properties()),
    brokerRepositoryProvider.overrideWithValue(broker ?? BrokerTestRepository()),
    favoritePropertyIdsProvider.overrideWith((ref) async => <int>{}),
    recentPropertiesStoreProvider.overrideWithValue(RecentPropertiesStore(enabled: false)),
    homeLocationAttemptedProvider.overrideWith((ref) => true),
    marketplaceRepositoryProvider.overrideWithValue(Wave3MarketplaceFake(onFeed: (query) async => MarketplaceFeed(
      label: 'إب', governorate: 'إب', sectionOrder: const ['latest'], sections: {'latest': [wave3Property(11)]}))),
    ...extra,
  ]);
  addTearDown(container.dispose); addTearDown(() => dio.close(force: true));
  return container;
}

Future<void> uxFrames(WidgetTester tester, [int frames = 10]) async {
  for (var index = 0; index < frames; index++) { await tester.pump(const Duration(milliseconds: 40)); }
}
Future<void> pumpUx(WidgetTester tester, ProviderContainer container, Widget child, {
  Size size = const Size(412, 820), double scale = 1, bool dark = false, GlobalKey? boundary, GoRouter? router,
}) async {
  tester.view.devicePixelRatio = 1; tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio); addTearDown(tester.view.resetPhysicalSize);
  await container.read(authControllerProvider.future);
  Widget builder(BuildContext context, Widget? child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: Directionality(textDirection: TextDirection.rtl, child: child!));
  final theme = dark ? AppTheme.dark : AppTheme.light;
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: RepaintBoundary(key: boundary,
    child: router == null ? MaterialApp(theme: theme, builder: builder, home: child)
      : MaterialApp.router(theme: theme, builder: builder, routerConfig: router))));
  await uxFrames(tester);
}
Future<void> closeUx(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink()); await tester.pump(const Duration(seconds: 1));
}
Future<void> uxPreview(WidgetTester tester, GlobalKey key, String name) async {
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/owner-ux-preview/$name.png');
    await file.parent.create(recursive: true); await file.writeAsBytes(bytes!.buffer.asUint8List()); image.dispose();
  });
}

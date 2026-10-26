import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/network/api_client.dart';
import 'package:real_estate_mobile/core/release/release_gate.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/core/widgets/app_components.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/properties/data/recent_properties_store.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_details_screen.dart';

class _Guest extends AuthController {
  @override
  Future<AuthUser?> build() async => null;
}

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;
  for (final forced in [false, true]) {
    testWidgets('${forced ? 'mandatory' : 'optional'} release gate is accessible and retries or dismisses', (tester) async {
      tester.view.physicalSize = const Size(320, 500); tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      var minimum = forced ? 2 : 1;
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) => handler.resolve(
        Response<Map<String, dynamic>>(requestOptions: request, statusCode: 200, data: {'data': {
          'minimum_supported_build': minimum, 'latest_build': 2,
          if (!forced) 'store_url': 'https://play.google.com/store/apps/details?id=com.aqer.yemen.uat',
        }}))));
      addTearDown(() => dio.close(force: true));
      await tester.pumpWidget(ProviderScope(overrides: [dioProvider.overrideWithValue(dio)],
        child: MaterialApp(theme: AppTheme.dark, builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2.4), padding: const EdgeInsets.only(top:24,bottom:34)),
          child: child!), home: const ReleaseGate(child: Scaffold(body: Text('Synthetic current app'))))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (forced) {
        expect(find.text('Synthetic current app'), findsNothing);
        expect(find.text('يلزم تحديث عقار'), findsOneWidget);
        minimum = 1;
        await tester.ensureVisible(find.text('إعادة التحقق')); await tester.tap(find.text('إعادة التحقق'));
      } else {
        expect(find.text('Synthetic current app'), findsOneWidget);
        expect(find.byType(MaterialBanner), findsOneWidget);
        await tester.ensureVisible(find.text('لاحقًا')); await tester.tap(find.text('لاحقًا'));
      }
      await tester.pumpAndSettle();
      expect(find.text('Synthetic current app'), findsOneWidget);
      expect(find.byType(MaterialBanner), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('share bridge follows the current property and refuses a private draft', (tester) async {
    final calls = <MethodCall>[];
    const channel = MethodChannel('real_estate/share');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async { calls.add(call); return null; });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    final id = ValueNotifier(42); addTearDown(id.dispose);
    var status = 'published';
    final container = ProviderContainer(overrides: [
      authControllerProvider.overrideWith(_Guest.new),
      recentPropertiesStoreProvider.overrideWithValue(RecentPropertiesStore(enabled: false)),
      propertyDetailsProvider.overrideWith((ref, propertyId) async => PropertyDetails.fromJson({
        'id': propertyId, 'title': 'Synthetic $propertyId', 'status': status, 'availability_status': 'available',
        'is_owner': true, 'type': 'office', 'purpose': 'rent', 'price': 75000, 'currency': 'YER',
        'latitude': 15.1, 'longitude': 44.6, 'images': <Object>[],
      })),
    ]);
    addTearDown(container.dispose); await container.read(authControllerProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp(theme: AppTheme.light,
      home: ValueListenableBuilder<int>(valueListenable: id, builder: (_, value, __) => PropertyDetailsScreen(propertyId: value)))));
    await tester.pumpAndSettle(); await tester.tap(find.byTooltip('مشاركة العقار')); await tester.pump();
    expect(calls.single.method, 'shareText');
    expect((calls.single.arguments as Map)['text'], contains('/l/properties/42'));
    id.value = 84; await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('مشاركة العقار')); await tester.pump();
    expect((calls.last.arguments as Map)['text'], contains('/l/properties/84'));
    expect((calls.last.arguments as Map)['text'], isNot(contains('/l/properties/42')));
    status = 'draft'; container.invalidate(propertyDetailsProvider(84)); await tester.pumpAndSettle();
    final action = tester.widget<AppIconButton>(find.ancestor(of: find.byTooltip('مشاركة العقار'), matching: find.byType(AppIconButton)));
    expect(action.onPressed, isNull);
    expect(calls, hasLength(2));
    expect(tester.takeException(), isNull);
  });
}

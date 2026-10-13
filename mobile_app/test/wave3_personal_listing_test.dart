import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/properties/presentation/my_listings_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/personal_listing_creation_gate.dart';

class _OwnerAuth extends AuthController {
  @override
  Future<AuthUser?> build() async => AuthUser.fromJson({'id': 1, 'name': 'عبدالله محمد علي القاضي',
    'account_status': 'active', 'phone_verified_at': '2026-10-13T10:00:00Z', 'profile_completed_at': '2026-10-13T10:00:00Z',
    'verification_profile': {'type': 'owner', 'status': 'approved', 'reviewed_at': '2026-10-13T10:00:00Z'}});
}

class _UploadAuth implements AuthRepository {
  @override
  Future<Options> requiredAuthOptions() async => Options(headers: {'Authorization': 'Bearer fixture'});
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<GoRouter> _gate(WidgetTester tester, {List<PropertyDetails> listings = const [], int? recovered}) async {
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => const PersonalListingCreationGate(child: Scaffold(body: Text('editor ready')))),
    GoRoute(path: '/account-verification', builder: (_, state) => Scaffold(body: Text('upgrade ${state.uri.queryParameters['upgrade']}'))),
    GoRoute(path: '/my-listings', builder: (_, __) => const Scaffold(body: Text('current property'))),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(overrides: [
    authControllerProvider.overrideWith(_OwnerAuth.new),
    myListingsProvider.overrideWith((_) async => listings),
    personalRecoveredListingIdProvider.overrideWith((_, __) async => recovered),
  ], child: MaterialApp.router(theme: AppTheme.light, routerConfig: router)));
  await tester.pumpAndSettle();
  return router;
}

PropertyDetails _listing(String status) => PropertyDetails.fromJson({'id': 22, 'title': 'عقاري الشخصي', 'type': 'house',
  'purpose': 'sale', 'price': 50000000, 'latitude': 15.3, 'longitude': 44.2, 'status': status, 'review_status': status == 'draft' ? 'draft' : 'approved'});

void main() {
  testWidgets('first personal listing opens the editor', (tester) async {
    await _gate(tester);
    expect(find.text('editor ready'), findsOneWidget);
  });

  testWidgets('second property offers broker review before opening an editor', (tester) async {
    final router = await _gate(tester, listings: [_listing('published')]);
    expect(find.text('editor ready'), findsNothing);
    await tester.tap(find.text('فعّل حساب دلال'));
    await tester.pumpAndSettle();
    expect(router.state.uri.queryParameters['upgrade'], 'broker');
    expect(find.text('upgrade broker'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('interrupted saved personal draft can resume without a second creation', (tester) async {
    await _gate(tester, listings: [_listing('draft')], recovered: 22);
    expect(find.text('editor ready'), findsOneWidget);
    expect(find.text('فعّل حساب دلال'), findsNothing);
  });

  testWidgets('recovery for a different server draft cannot bypass the personal limit', (tester) async {
    await _gate(tester, listings: [_listing('draft')], recovered: 99);
    expect(find.text('editor ready'), findsNothing);
    expect(find.text('فعّل حساب دلال'), findsOneWidget);
  });

  test('whole-floor state survives models and multipart boolean encoding', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://fixture.example.test/api'));
    final forms = <FormData>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      forms.add(options.data as FormData);
      handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 201,
        data: {'data': {'id': 22, 'title': 'شقة', 'type': 'apartment', 'purpose': 'sale', 'price': 1000, 'latitude': 15.3, 'longitude': 44.2}}));
    }));
    final repository = PropertyRepository(dio, _UploadAuth());
    for (final wholeFloor in [true, false]) {
      await repository.createListing(PropertyListingInput(title: 'شقة', purpose: 'sale', type: 'apartment', price: 1000,
        latitude: 15.3, longitude: 44.2, floorNumber: '3', unitNumber: wholeFloor ? null : 'جنوبية', unitOccupiesEntireFloor: wholeFloor));
      final fields = Map.fromEntries(forms.last.fields);
      expect(fields['listing_input_version'], '5');
      expect(fields['unit_occupies_entire_floor'], wholeFloor ? '1' : '0');
      expect(fields['floor_number'], '3');
    }
    expect(PropertyDetails.fromJson({'id': 1, 'type': 'floor'}).unitOccupiesEntireFloor, isTrue);
  });
}

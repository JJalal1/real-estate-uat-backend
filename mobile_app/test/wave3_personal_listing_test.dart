import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/properties/presentation/publish_listing.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/properties/presentation/add_property_wizard_screen.dart';

class _PublicationAuth extends AuthController {
  _PublicationAuth(this.historicalOwner);
  final bool historicalOwner;
  int refreshes = 0;
  @override
  Future<void> refresh() async {
    refreshes++;
  }

  @override
  Future<AuthUser?> build() async => AuthUser.fromJson({
        'id': 1,
        'name': 'عبدالله محمد علي القاضي',
        'account_status': 'active',
        'phone_verified_at': '2026-10-13T10:00:00Z',
        'profile_completed_at': '2026-10-13T10:00:00Z',
        if (historicalOwner) 'verification_profile': {
          'type': 'owner',
          'status': 'approved',
          'reviewed_at': '2026-10-13T10:00:00Z'
        }
      });
}

class _UploadAuth implements AuthRepository {
  @override
  Future<Options> requiredAuthOptions() async =>
      Options(headers: {'Authorization': 'Bearer fixture'});
  @override
  Future<AuthUser> acceptSubmissionUser(Map<String, dynamic> raw, {required int expectedUserId, required int epoch}) async {
    expect(raw['id'], expectedUserId);
    return AuthUser.fromJson(raw);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<_PublicationAuth> _mountPublisher(
  WidgetTester tester, {
  required bool needsUpgrade,
  required bool historicalOwner,
  required List<Map<String, dynamic>> calls,
  required List<PropertyDetails?> results,
}) async {
  final auth = _PublicationAuth(historicalOwner);
  final dio = Dio(BaseOptions(baseUrl: 'https://fixture.example.test/api'));
  dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
    final body = Map<String, dynamic>.from(request.data as Map);
    calls.add(body);
    if (needsUpgrade && body['upgrade_to_broker'] != true) {
      handler.reject(DioException(
        requestOptions: request,
        type: DioExceptionType.badResponse,
        response: Response(
            requestOptions: request,
            statusCode: 409,
            data: {'code': 'broker_upgrade_required'}),
      ));
    } else {
      handler.resolve(Response<Map<String, dynamic>>(
        requestOptions: request,
        statusCode: 200,
        data: {
          'data': {'id': 22, 'title': 'شقة', 'status': 'pending', 'review_status': 'submitted'},
          if (body['upgrade_to_broker'] == true) 'session': {'user': {
            'id': 1, 'account_type': 'broker', 'broker_enrolled': true,
          }},
        },
      ));
    }
  }));
  await tester.pumpWidget(ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => auth),
        propertyRepositoryProvider
            .overrideWithValue(PropertyRepository(dio, _UploadAuth())),
      ],
      child: MaterialApp(
          theme: AppTheme.light,
          home: Consumer(builder: (context, ref, _) {
            final actor = ref.watch(authControllerProvider).asData?.value;
            return Scaffold(
                body: Column(children: [
              Text(actor?.hasMarketplaceProfessionalProfile == true ? 'إعلاناتي' : 'الأقسام'),
              TextButton(
              onPressed: actor == null
                  ? null
                  : () async {
                      results.add(await publishListing(context, ref, 22));
                    },
              child: const Text('نشر الإعلان'),
            )]));
          }))));
  await tester.pumpAndSettle();
  return auth;
}

void main() {
  testWidgets('choosing a creation method never requests an upgrade',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AddPropertyWizardScreen())));
    expect(find.byKey(const ValueKey('listing-method-manual')), findsOneWidget);
    expect(find.byKey(const ValueKey('listing-method-ai')), findsOneWidget);
    expect(find.text('ترقية وإرسال للمراجعة'), findsNothing);
  });

  for (final historicalOwner in [false, true]) {
    testWidgets('first listing is sent for review, historicalOwner=$historicalOwner', (tester) async {
      final calls = <Map<String, dynamic>>[], results = <PropertyDetails?>[];
      final auth = await _mountPublisher(tester,
          needsUpgrade: false, historicalOwner: historicalOwner, calls: calls, results: results);
      await tester.tap(find.text('نشر الإعلان'));
      await tester.pumpAndSettle();
      expect(calls, [
        {'publish_now': true}
      ]);
      expect(results.single!.status, 'pending');
      expect(publicationMessage(results.single!), contains('للمراجعة'));
      expect(auth.refreshes, 0);
      expect(find.text('ترقية وإرسال للمراجعة'), findsNothing);
    });

    for (final accept in [false, true]) {
      testWidgets('second publication waits for consent, historicalOwner=$historicalOwner accept=$accept',
          (tester) async {
        final calls = <Map<String, dynamic>>[], results = <PropertyDetails?>[];
        final auth = await _mountPublisher(tester,
            needsUpgrade: true, historicalOwner: historicalOwner, calls: calls, results: results);
        await tester.tap(find.text('نشر الإعلان'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(calls, [
          {'publish_now': true}
        ]);
        expect(results, isEmpty);
        await tester.tap(find.text(accept ? 'ترقية وإرسال للمراجعة' : 'ليس الآن'));
        await tester.pumpAndSettle();
        expect(calls, [
          {'publish_now': true},
          if (accept) {'publish_now': true, 'upgrade_to_broker': true},
        ]);
        expect(results.single?.status, accept ? 'pending' : null);
        expect(find.text(accept ? 'إعلاناتي' : 'الأقسام'), findsOneWidget);
        expect(auth.refreshes, 0);
      });
    }
  }

  test('whole-floor state survives models and multipart boolean encoding',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://fixture.example.test/api'));
    final forms = <FormData>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      forms.add(options.data as FormData);
      handler.resolve(Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 201,
          data: {
            'data': {
              'id': 22,
              'title': 'شقة',
              'type': 'apartment',
              'purpose': 'sale',
              'price': 1000,
              'latitude': 15.3,
              'longitude': 44.2
            }
          }));
    }));
    final repository = PropertyRepository(dio, _UploadAuth());
    for (final wholeFloor in [true, false]) {
      await repository.createListing(PropertyListingInput(
          title: 'شقة',
          purpose: 'sale',
          type: 'apartment',
          price: 1000,
          latitude: 15.3,
          longitude: 44.2,
          floorNumber: '3',
          unitNumber: wholeFloor ? null : 'جنوبية',
          unitOccupiesEntireFloor: wholeFloor));
      final fields = Map.fromEntries(forms.last.fields);
      expect(fields['listing_input_version'], '8');
      expect(fields['unit_occupies_entire_floor'], wholeFloor ? '1' : '0');
      expect(fields['floor_number'], '3');
    }
    expect(
        PropertyDetails.fromJson({'id': 1, 'type': 'floor'})
            .unitOccupiesEntireFloor,
        isTrue);
  });
}

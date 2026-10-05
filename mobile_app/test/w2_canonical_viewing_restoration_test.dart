import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/bookings/data/booking_repository.dart';
import 'package:real_estate_mobile/features/bookings/domain/booking_models.dart';
import 'package:real_estate_mobile/features/bookings/presentation/booking_request_sheet.dart';
import 'package:real_estate_mobile/features/messages/data/message_repository.dart';
import 'package:real_estate_mobile/features/properties/data/favorites_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_details_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_market_context_card.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_sai_public_line.dart';

void main() {
  testWidgets('published non-owner retains current UX and viewing action',
      (tester) async {
    await _pumpDetails(tester);
    expect(find.text('طلب موعد معاينة'), findsOneWidget);
    expect(find.byTooltip('حفظ في المفضلة'), findsOneWidget);
    expect(find.byType(PropertyMarketContextCard), findsOneWidget);
    expect(find.text('تواصل مع المعلن'), findsOneWidget);
  });

  for (final condition in ['unpublished', 'owner']) {
    testWidgets('viewing action is hidden for $condition', (tester) async {
      await _pumpDetails(
        tester,
        status: condition == 'unpublished' ? 'archived' : 'published',
        isOwner: condition == 'owner',
      );
      expect(find.text('طلب موعد معاينة'), findsNothing);
      expect(find.byType(BookingRequestSheet), findsNothing);
    });
  }

  for (final active in [null, false]) {
    testWidgets(
        active == null
            ? 'anonymous viewing request goes to authentication'
            : 'inactive viewing request goes to phone verification',
        (tester) async {
      final fixture = await _pumpDetails(tester, active: active);
      await tester.tap(find.text('طلب موعد معاينة'));
      await tester.pumpAndSettle();
      final page = find.text(
        active == null ? 'authentication' : 'phone-verification',
      );
      expect(page, findsOneWidget);
      expect(
        GoRouterState.of(tester.element(page)).uri.path,
        active == null ? '/auth' : '/verify-phone',
      );
      expect(find.byType(BookingRequestSheet), findsNothing);
      expect(fixture.bookings.requests, 0);
    });
  }

  testWidgets('real request sheet opens returned linked conversation',
      (tester) async {
    final fixture = await _pumpDetails(tester, threadId: 91);
    await tester.tap(find.text('طلب موعد معاينة'));
    await tester.pumpAndSettle();
    expect(find.byType(BookingRequestSheet), findsOneWidget);
    await tester.tap(find.text('إرسال الطلب'));
    await tester.pumpAndSettle();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(fixture.bookings.requests, 1);
    expect(fixture.bookings.propertyId, 42);
    expect(fixture.bookings.payload, containsPair('timezone', 'UTC'));
    final start = DateTime.parse(fixture.bookings.payload!['starts_at'] as String);
    final end = DateTime.parse(fixture.bookings.payload!['ends_at'] as String);
    expect(end.difference(start), const Duration(minutes: 60));
    expect(fixture.container.read(messageDataRevisionProvider), 1);
    final page = find.text('linked-conversation 91');
    expect(page, findsOneWidget);
    expect(GoRouterState.of(tester.element(page)).uri.path, '/messages/91');
    expect(find.byType(BookingRequestSheet), findsNothing);
  });

  testWidgets('request without linked thread retains canonical fallback',
      (tester) async {
    final fixture = await _pumpDetails(tester, threadId: null);
    await tester.tap(find.text('طلب موعد معاينة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إرسال الطلب'));
    await tester.pumpAndSettle();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(fixture.bookings.requests, 1);
    expect(fixture.router.routeInformationProvider.value.uri.path, '/');
    expect(fixture.container.read(messageDataRevisionProvider), 0);
    // The existing sheet's success snackbar is queued before the details
    // fallback. Advance its duration before asserting the next message.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(
      find.text('تم إرسال طلب المعاينة ويمكن متابعته من صفحة المعاينات.'),
      findsOneWidget,
    );
  });

  testWidgets('dismissing request sheet creates no request or conversation',
      (tester) async {
    final fixture = await _pumpDetails(tester);
    await tester.tap(find.text('طلب موعد معاينة'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(BookingRequestSheet))).pop();
    await tester.pumpAndSettle();

    expect(fixture.bookings.requests, 0);
    expect(fixture.container.read(messageDataRevisionProvider), 0);
    expect(fixture.router.routeInformationProvider.value.uri.path, '/');
    expect(find.byType(BookingRequestSheet), findsNothing);
  });
}

Future<({
  GoRouter router,
  ProviderContainer container,
  _FixtureBookings bookings,
})> _pumpDetails(
  WidgetTester tester, {
  bool? active = true,
  String status = 'published',
  bool isOwner = false,
  int? threadId = 91,
}) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final user = active == null
      ? null
      : AuthUser.fromJson({
          'id': 7,
          'account_status': active ? 'active' : 'pending_verification',
          'phone_verified_at': active ? '2026-01-01T00:00:00Z' : null,
        });
  final bookings = _FixtureBookings(threadId);
  final container = ProviderContainer(overrides: [
    authControllerProvider.overrideWith(() => _FixtureAuth(user)),
    propertyDetailsProvider(42).overrideWith((ref) async => PropertyDetails(
          id: 42,
          title: 'عقار المعاينة',
          purpose: 'sale',
          type: 'apartment',
          price: 100000,
          currency: 'YER',
          latitude: 15,
          longitude: 44,
          images: const [],
          status: status,
          isOwner: isOwner,
        )),
    favoritePropertyIdsProvider.overrideWith((ref) async => <int>{}),
    // Isolate unrelated cards from all network access, using their existing
    // handled error states. No finance/market implementation is changed.
    propertySaiPublicProvider(42).overrideWith(
      (ref) async => throw StateError('Isolated viewing test fixture'),
    ),
    propertyMarketContextProvider(42).overrideWith(
      (ref) async => throw StateError('Isolated viewing test fixture'),
    ),
    bookingRepositoryProvider.overrideWithValue(bookings),
  ]);
  final router = GoRouter(routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => const PropertyDetailsScreen(propertyId: 42),
    ),
    GoRoute(
      path: '/auth',
      builder: (_, __) => const Scaffold(body: Text('authentication')),
    ),
    GoRoute(
      path: '/verify-phone',
      builder: (_, __) => const Scaffold(body: Text('phone-verification')),
    ),
    GoRoute(
      path: '/messages/:threadId',
      builder: (_, state) => Scaffold(
        body: Text("linked-conversation ${state.pathParameters['threadId']}"),
      ),
    ),
  ]);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    container.dispose();
  });
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return (router: router, container: container, bookings: bookings);
}

class _FixtureAuth extends AuthController {
  _FixtureAuth(this.user);
  final AuthUser? user;
  @override
  Future<AuthUser?> build() async => user;
}

class _FixtureBookings implements BookingRepository {
  _FixtureBookings(this.threadId);
  final int? threadId;
  int requests = 0;
  int? propertyId;
  Map<String, dynamic>? payload;

  @override
  Future<ViewingBooking> requestProperty(
      int propertyId, Map<String, dynamic> payload) async {
    requests++;
    this.propertyId = propertyId;
    this.payload = Map<String, dynamic>.from(payload);
    return ViewingBooking.fromJson({
      'id': 63,
      'message_thread_id': threadId,
      'target_id': propertyId,
      'starts_at': payload['starts_at'],
      'ends_at': payload['ends_at'],
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

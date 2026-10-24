import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/widgets/app_components.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/agreements/data/agreement_repository.dart';
import 'package:real_estate_mobile/features/agreements/domain/agreement_models.dart';
import 'package:real_estate_mobile/features/agreements/presentation/agreements_screen.dart';
import 'package:real_estate_mobile/features/agreements/presentation/agreement_detail_screen.dart';
import 'package:real_estate_mobile/features/agreements/presentation/rental_contract_detail_screen.dart';
import 'package:real_estate_mobile/features/bookings/data/booking_repository.dart';
import 'package:real_estate_mobile/features/bookings/domain/booking_models.dart';
import 'package:real_estate_mobile/features/bookings/presentation/bookings_screen.dart';

DioException _failure([int status = 503]) {
  final request = RequestOptions(path: '/synthetic-buyer-read');
  return DioException(requestOptions: request, type: DioExceptionType.badResponse,
    response: Response(requestOptions: request, statusCode: status));
}
class _Account extends AuthController {
  @override
  Future<AuthUser?> build() async => AuthUser.fromJson({'id': 1, 'name': 'Synthetic', 'account_status': 'active'});
  void change(int? id) { state = AsyncData(id == null ? null : AuthUser.fromJson({'id': id, 'name': 'Synthetic', 'account_status': 'active'})); }
}
PropertyAgreement _agreement() => PropertyAgreement.fromJson({'id': 11, 'reference': 'AGR-SYNTHETIC',
  'property_id': 7, 'message_thread_id': 1, 'requester_user_id': 1, 'advertiser_user_id': 2,
  'transaction_type': 'sale', 'status': 'draft', 'can_accept': true,
  'current_revision': {'id': 110, 'revision_number': 1, 'agreed_amount': 100, 'currency': 'YER',
    'created_by_user_id': 2, 'created_by_name': 'Synthetic'}});
RentalContract _contract() => RentalContract.fromJson({'id': 12, 'reference': 'RNT-SYNTHETIC',
  'property_agreement_id': 11, 'property_id': 7, 'message_thread_id': 1,
  'tenant_user_id': 1, 'advertiser_user_id': 2, 'property_title': 'Synthetic', 'status': 'draft', 'can_accept': true,
  'current_revision': {'id': 120, 'revision_number': 1, 'rent_amount': 100, 'currency': 'YER',
    'rent_cadence': 'monthly', 'start_date': '2026-10-01', 'end_date': '2027-10-01',
    'created_by_user_id': 2, 'created_by_name': 'Synthetic'}});
ViewingBooking _booking() => ViewingBooking.fromJson({'id': 13, 'reference': 'BOOK-SYNTHETIC',
  'requester_user_id': 1, 'requester_name': 'Synthetic', 'target_type': 'property', 'target_id': 7,
  'target_title': 'معاينة اصطناعية', 'starts_at': '2026-10-25T10:00:00Z',
  'ends_at': '2026-10-25T11:00:00Z', 'status': 'requested'});
class _Agreements implements AgreementRepository {
  Future<List<PropertyAgreement>> Function() onMine = () async => [_agreement()];
  Future<PropertyAgreement> Function() onAgreement = () async => _agreement();
  Future<RentalContract> Function() onContract = () async => _contract();
  int acceptCalls = 0;
  @override
  Future<List<PropertyAgreement>> mine() => onMine();
  @override
  Future<List<RentalContract>> contractsMine() async => [];
  @override
  Future<PropertyAgreement> agreement(int id) => onAgreement();
  @override
  Future<RentalContract> contract(int id) => onContract();
  @override
  Future<PropertyAgreement> acceptAgreement(int id, int revision) async { acceptCalls++; return _agreement(); }
  @override
  Future<RentalContract> acceptRentalContract(int id, int revision) async { acceptCalls++; return _contract(); }
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}
class _Bookings implements BookingRepository {
  Future<List<ViewingBooking>> Function() onMine = () async => [_booking()];
  @override
  Future<List<ViewingBooking>> mine({DateTime? from, DateTime? before}) => onMine();
  @override
  Future<List<ViewingBooking>> managed({DateTime? from, DateTime? before}) => onMine();
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}
Future<void> _mount(WidgetTester tester, Widget page, _Account account, _Agreements agreements, _Bookings bookings) async {
  tester.view.physicalSize = const Size(390, 800); tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(overrides: [authControllerProvider.overrideWith(() => account),
    agreementRepositoryProvider.overrideWithValue(agreements), bookingRepositoryProvider.overrideWithValue(bookings)],
    child: MaterialApp(home: page)));
  for (var i = 0; i < 6; i++) { await tester.pump(const Duration(milliseconds: 20)); }
}
Future<void> _retry(WidgetTester tester) async {
  final button = find.text('إعادة المحاولة');
  await tester.ensureVisible(button); await tester.pumpAndSettle();
  await tester.tap(button); await tester.pumpAndSettle();
}

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;
  testWidgets('agreement list retains a transient refresh but hides denied and cross-account data', (tester) async {
    final account = _Account(), repo = _Agreements();
    await _mount(tester, const AgreementsScreen(), account, repo, _Bookings());
    expect(find.textContaining('AGR-SYNTHETIC'), findsOneWidget);
    repo.onMine = () async => throw _failure();
    await tester.tap(find.byTooltip('تحديث')); await tester.pumpAndSettle();
    expect(find.textContaining('AGR-SYNTHETIC'), findsOneWidget);
    expect(find.byType(AppRefreshStatus), findsOneWidget);
    repo.onMine = () async => throw _failure(403); await _retry(tester);
    expect(find.textContaining('AGR-SYNTHETIC'), findsNothing);
    expect(find.byType(AppErrorState), findsOneWidget);
    account.change(null); await tester.pumpAndSettle();
    expect(find.text('سجّل الدخول للمتابعة.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets('a late agreement list response belongs only to its original account', (tester) async {
    final account = _Account(), repo = _Agreements();
    final late = Completer<List<PropertyAgreement>>(); repo.onMine = () => late.future;
    await _mount(tester, const AgreementsScreen(), account, repo, _Bookings());
    repo.onMine = () async => []; account.change(2); await tester.pumpAndSettle();
    late.complete([_agreement()]); await tester.pumpAndSettle();
    expect(find.textContaining('AGR-SYNTHETIC'), findsNothing);
    expect(find.textContaining('لا توجد اتفاقات بعد.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 45)));

  for (final rental in [false, true]) {
    testWidgets('private detail rental=$rental retries first failure and never authorizes from an uncertain refresh', (tester) async {
      final account = _Account(), repo = _Agreements();
      repo.onAgreement = () async => throw _failure(); repo.onContract = () async => throw _failure();
      await _mount(tester, rental ? const RentalContractDetailScreen(contractId: 12) : const AgreementDetailScreen(agreementId: 11),
        account, repo, _Bookings());
      expect(find.byType(AppErrorState), findsOneWidget);
      repo.onAgreement = () async => _agreement(); repo.onContract = () async => _contract();
      await _retry(tester);
      final reference = rental ? 'RNT-SYNTHETIC' : 'AGR-SYNTHETIC';
      expect(find.textContaining(reference), findsOneWidget);
      repo.onAgreement = () async => throw _failure(); repo.onContract = () async => throw _failure();
      await tester.tap(find.byTooltip('تحديث')); await tester.pumpAndSettle();
      expect(find.textContaining(reference), findsOneWidget);
      final accept = find.textContaining('أوافق على النسخة');
      await tester.ensureVisible(accept); await tester.pumpAndSettle(); await tester.tap(accept); await tester.pumpAndSettle();
      expect(repo.acceptCalls, 0);
      repo.onAgreement = () async => throw _failure(403); repo.onContract = () async => throw _failure(403);
      await _retry(tester);
      expect(find.textContaining(reference), findsNothing);
      account.change(null); await tester.pumpAndSettle();
      expect(find.text('سجّل الدخول للمتابعة.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, timeout: const Timeout(Duration(seconds: 45)));
  }

  testWidgets('bookings retain 503 rows but a new account never sees their previous values', (tester) async {
    final account = _Account(), repo = _Bookings();
    await _mount(tester, const BookingsScreen(), account, _Agreements(), repo);
    expect(find.text('معاينة اصطناعية'), findsOneWidget);
    repo.onMine = () async => throw _failure();
    await tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh(); await tester.pumpAndSettle();
    expect(find.text('معاينة اصطناعية'), findsOneWidget);
    account.change(2); await tester.pumpAndSettle();
    expect(find.text('معاينة اصطناعية'), findsNothing);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets('a late booking receipt cannot reappear after logout', (tester) async {
    final account = _Account(), repo = _Bookings();
    final late = Completer<List<ViewingBooking>>(); repo.onMine = () => late.future;
    await _mount(tester, const BookingsScreen(), account, _Agreements(), repo);
    account.change(null); await tester.pumpAndSettle();
    late.complete([_booking()]); await tester.pumpAndSettle();
    expect(find.text('معاينة اصطناعية'), findsNothing);
    expect(find.textContaining('سجّل الدخول لطلب مواعيد المعاينة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 45)));
}

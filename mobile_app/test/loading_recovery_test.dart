import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/network/api_error_message.dart';
import 'package:real_estate_mobile/core/network/api_client.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/features/broker/data/broker_repository.dart';
import 'package:real_estate_mobile/features/broker/domain/broker_models.dart';
import 'package:real_estate_mobile/features/broker/presentation/broker_workspaces.dart';
import 'package:real_estate_mobile/core/widgets/app_components.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/account/data/account_verification_repository.dart';
import 'package:real_estate_mobile/features/account/domain/account_verification.dart';
import 'package:real_estate_mobile/features/account/presentation/account_verification_screen.dart';
import 'package:real_estate_mobile/features/properties/data/listing_account_draft_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/listing_account_draft.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_draft_entry_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/my_listings_screen.dart';
import 'package:real_estate_mobile/features/support/data/support_repository.dart';
import 'package:real_estate_mobile/features/support/domain/support_models.dart';
import 'package:real_estate_mobile/features/support/presentation/support_admin_screen.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/smart_search_session.dart';
import 'package:real_estate_mobile/features/discovery/domain/smart_search_filters.dart';
import 'package:real_estate_mobile/features/discovery/presentation/marketplace_section_screen.dart';
import 'package:real_estate_mobile/features/messages/data/message_repository.dart';
import 'package:real_estate_mobile/features/messages/domain/message_models.dart';
import 'package:real_estate_mobile/features/messages/presentation/messages_screen.dart';
import 'package:real_estate_mobile/features/messages/presentation/conversation_screen.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_details_screen.dart';
import 'package:real_estate_mobile/features/discovery/presentation/smart_search_assistant.dart';

import 'support/wave3_fakes.dart';
import 'support/wave6_fakes.dart';

DioException _failure([int code = 503]) {
  final request = RequestOptions(path: '/synthetic-only');
  return DioException(requestOptions: request, type: DioExceptionType.badResponse,
    response: Response(requestOptions: request, statusCode: code));
}

class _Auth extends AuthController {
  @override
  Future<AuthUser?> build() async => _user(1);
  void change(int? id) { state = AsyncData(id == null ? null : _user(id)); }
}
AuthUser _user(int id) => AuthUser.fromJson({'id': id, 'name': 'حساب اختباري', 'account_status': 'active', 'account_type': 'owner', 'roles': ['owner']});

class _Search extends Wave3PropertiesFake {
  final transfers = <CancelToken>[];
  @override
  Future<(List<PropertySummary>, bool)> searchListings(Map<String, dynamic> filters,
    {int page = 1, CancelToken? cancelToken, bool refresh = false}) {
    if (cancelToken != null) transfers.add(cancelToken);
    return super.searchListings(filters, page: page, cancelToken: cancelToken, refresh: refresh);
  }
}
class _NoHint extends AssistantHintStore {
  @override
  Future<bool> take() async => false;
}
class _Feed extends Wave3MarketplaceFake {
  final transfers = <CancelToken>[];
  _Feed({super.onFeed});
  @override
  Future<MarketplaceFeed> feed(HomeFeedQuery query, {CancelToken? cancelToken, int cacheRevision = 0}) {
    if (cancelToken != null) transfers.add(cancelToken);
    return super.feed(query, cancelToken: cancelToken, cacheRevision: cacheRevision);
  }
}
class _AuthOptions extends AuthRepository {
  _AuthOptions(super.dio);
  @override
  Future<Options> requiredAuthOptions() async => Options();
}
class _Messages implements MessageRepository {
  Future<List<MessageThreadSummary>> Function()? onThreads;
  Future<MessageThreadDetails> Function()? onDetails;
  int calls = 0;
  @override
  Future<List<MessageThreadSummary>> threads() { calls++; return onThreads!(); }
  @override
  Future<MessageThreadDetails> details(int id, {int? beforeId}) => onDetails!();
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}
const _thread = MessageThreadSummary(id: 1, otherUserId: 2, otherUserName: 'محادثة اصطناعية', unreadCount: 1);
final _detail = MessageThreadDetails(thread: _thread, messages: const [
  PrivateMessageItem(id: 1, senderUserId: 2, senderName: 'اختبار', body: 'رسالة اصطناعية محفوظة', isMine: false),
]);
class _Customers implements BrokerRepository {
  Future<BrokerPage<BrokerCustomer>> Function(int)? onCustomers;
  final pages = <int>[];
  @override
  Future<BrokerPage<BrokerCustomer>> customers({String? stage, int? propertyId, int page = 1, String? filter}) {
    pages.add(page); return onCustomers!(page);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}
const _customer = BrokerCustomer(threadId: 1, customerName: 'عميل اصطناعي', propertyId: 77, propertyTitle: 'عقار اصطناعي', stage: 'new');
class _Verification implements AccountVerificationRepository {
  Future<AccountVerificationApplication> Function()? onStatus;
  @override
  Future<AccountVerificationApplication> status() => onStatus!();
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}
AccountVerificationApplication _verification() => AccountVerificationApplication.fromJson({
  'user_id': 1, 'name': 'حساب اصطناعي', 'type': 'broker', 'status': 'needs_more_info',
  'details': {'governorate': 'أمانة العاصمة', 'district': 'السبعين', 'work_areas': ['قيمة من الخادم']},
});
class _Drafts extends Wave6Drafts {
  int calls = 0;
  final pending = Completer<ListingAccountDraft>();
  @override
  Future<ListingAccountDraft> get(String key) { calls++; return pending.future; }
}
class _Support implements SupportRepository {
  Future<List<SupportCaseSummary>> Function()? onCases;
  @override
  Future<SupportAdminSummary> adminSummary() async => SupportAdminSummary.fromJson({'new_tickets': 7});
  @override
  Future<List<SupportCaseSummary>> adminCases({String? kind, String? status, bool? escalated, bool assignedToMe = false, int? assignedToUserId}) => onCases!();
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}
class _Details extends Wave3PropertiesFake {
  Future<PropertyDetails> Function(int)? onDetails;
  @override
  Future<PropertyDetails> details(int id) => onDetails!(id);
  @override
  Future<List<PropertyDetails>> myListings() async => [_property(77)];
}
PropertyDetails _property(int id, {String title = 'تفاصيل اصطناعية'}) => PropertyDetails.fromJson({
  'id': id, 'title': title, 'type': 'house', 'purpose': 'sale', 'status': 'draft',
  'is_owner': true, 'latitude': 15.3, 'longitude': 44.2, 'images': [],
});

void main() {
  test('only transient network and server failures retain account content', () {
    for (final code in [429, 500, 503]) { expect(isTransientApiFailure(_failure(code)), isTrue); }
    for (final code in [400, 401, 403, 404, 409, 422]) { expect(isTransientApiFailure(_failure(code)), isFalse); }
    expect(isTransientApiFailure(StateError('AUTH_REQUIRED')), isFalse);
    expect(isTransientApiFailure(DioException(requestOptions: RequestOptions(), type: DioExceptionType.receiveTimeout)), isTrue);
  }, timeout: const Timeout(Duration(seconds: 45)));

  test('refresh and pagination retry the exact failed page without dropping or duplicating results', () async {
    final repo = _Search();
    final session = SmartSearchSession(Wave3AiFake(), repo);
    addTearDown(session.dispose);
    repo.onSearch = (_, page) async => ([wave3Property(page)], true);
    await session.search();
    final refresh = Completer<(List<PropertySummary>, bool)>();
    repo.onSearch = (_, __) => refresh.future;
    final pending = session.search();
    expect(session.state.rows.single.id, 1);
    expect(session.state.loading, isTrue);
    refresh.completeError(_failure()); await pending;
    expect(session.state.rows.single.id, 1);
    expect(session.state.resultsError, isNotNull);
    repo.onSearch = (_, __) async => ([wave3Property(10)], true);
    await session.retryResults();
    expect(repo.queries.last.page, 1);
    expect(session.state.rows.single.id, 10);
    repo.onSearch = (_, __) async => throw _failure();
    await session.search(more: true);
    expect(session.state.rows.single.id, 10);
    repo.onSearch = (_, __) async => ([wave3Property(10), wave3Property(11)], false);
    await session.retryResults();
    expect(repo.queries.last.page, 2);
    expect(session.state.rows.map((r) => r.id), [10, 11]);
    final count = repo.queries.length;
    await session.search(more: true);
    expect(repo.queries, hasLength(count));
  }, timeout: const Timeout(Duration(seconds: 45)));

  test('criteria changes cancel old transport and late responses never replace new criteria', () async {
    final repo = _Search();
    final old = Completer<(List<PropertySummary>, bool)>();
    repo.onSearch = (_, __) => old.future;
    final session = SmartSearchSession(Wave3AiFake(), repo);
    final pending = session.search();
    final transfer = repo.transfers.single;
    repo.onSearch = (_, __) async => ([wave3Property(22)], false);
    session.replaceManually(SmartSearchFilters.fromMap({'search': 'إب'}));
    await Future<void>.delayed(Duration.zero);
    expect(transfer.isCancelled, isTrue);
    old.complete(([wave3Property(11)], false)); await pending;
    expect(session.state.rows.single.id, 22);
    expect(session.state.filters.values['search'], 'إب');
    final last = repo.transfers.last;
    session.dispose();
    expect(last.isCancelled, isTrue);
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets('section refresh keeps visible rows, retries page one, and disposal cancels its transport', (tester) async {
    final repo = _Search()..onSearch = (_, __) async => ([wave3Property(11)], true);
    await tester.pumpWidget(ProviderScope(overrides: [
      propertyRepositoryProvider.overrideWithValue(repo),
      assistantHintStoreProvider.overrideWithValue(_NoHint()),
    ], child: const MaterialApp(home: MarketplaceSectionScreen())));
    await tester.pumpAndSettle();
    expect(find.text('عقار تجريبي 11'), findsOneWidget);
    final result = Completer<(List<PropertySummary>, bool)>();
    repo.onSearch = (_, __) => result.future;
    final refreshing = tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh();
    await tester.pump();
    expect(find.text('عقار تجريبي 11'), findsOneWidget);
    expect(find.byType(AppEmptyState), findsNothing);
    result.completeError(_failure()); await refreshing; await tester.pumpAndSettle();
    expect(find.text('عقار تجريبي 11'), findsOneWidget);
    repo.onSearch = (_, __) async => ([wave3Property(12)], false);
    await tester.tap(find.text('إعادة المحاولة')); await tester.pumpAndSettle();
    expect(repo.queries.last.page, 1);
    expect(find.text('عقار تجريبي 11'), findsNothing);
    expect(find.text('عقار تجريبي 12'), findsOneWidget);
    final token = repo.transfers.last;
    await tester.pumpWidget(const SizedBox()); await tester.pump();
    expect(token.isCancelled, isTrue);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 45)));

  test('completed public home feed survives a short return but expires and invalidates after a mutation', () async {
    var now = DateTime.utc(2026, 10, 24); var calls = 0;
    final dio = Dio()..interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      calls++; handler.resolve(Response(requestOptions: request, statusCode: 200,
        data: {'data': {'context': {'label': 'اصطناعي'}, 'sections': <String, dynamic>{}}}));
    }));
    addTearDown(() => dio.close(force: true));
    final repo = MarketplaceRepository(dio, now: () => now);
    final container = ProviderContainer(overrides: [marketplaceRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(container.dispose);
    const query = (latitude: 15.3, longitude: 44.2, governorate: null, type: null, device: false);
    final provider = marketplaceFeedProvider(query);
    var subscription = container.listen(provider, (_, __) {});
    await container.read(provider.future);
    subscription.close(); await Future<void>.delayed(Duration.zero);
    subscription = container.listen(provider, (_, __) {});
    await container.read(provider.future);
    expect(calls, 1);
    subscription.close(); await Future<void>.delayed(Duration.zero); now = now.add(const Duration(seconds: 21));
    subscription = container.listen(provider, (_, __) {});
    await container.read(provider.future);
    expect(calls, 2);
    container.read(propertyDataRevisionProvider.notifier).state++;
    await container.read(provider.future);
    expect(calls, 3);
    subscription.close();
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets('an abandoned pending home request cancels instead of becoming a retained cache entry', (tester) async {
    final pending = Completer<MarketplaceFeed>();
    final repo = _Feed(onFeed: (_) => pending.future);
    const query = (latitude: 15.3, longitude: 44.2, governorate: null, type: null, device: false);
    var visible = true;
    late StateSetter change;
    await tester.pumpWidget(ProviderScope(overrides: [marketplaceRepositoryProvider.overrideWithValue(repo)],
      child: StatefulBuilder(builder: (_, set) {
        change = set;
        return visible ? Consumer(builder: (_, ref, __) {
          ref.watch(marketplaceFeedProvider(query));
          return const SizedBox();
        }) : const SizedBox();
      })));
    await tester.pumpAndSettle();
    change(() => visible = false);
    await tester.pumpAndSettle();
    expect(repo.transfers.single.isCancelled, isTrue);
    pending.complete(const MarketplaceFeed(label: 'اصطناعي')); await tester.pump();
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 45)));

  test('public cache encodes query values and a pre-delete response cannot refill invalidated entries', () async {
    final dio = Dio(); addTearDown(() => dio.close(force: true));
    final pending = Completer<void>(); var delay = false, gets = 0;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) async {
      if (request.method == 'GET') { gets++; if (delay && gets == 3) await pending.future; }
      handler.resolve(Response(requestOptions: request, statusCode: 200,
        data: {'data': <dynamic>[], 'meta': {'current_page': 1, 'last_page': 1}}));
    }));
    final repo = PropertyRepository(dio, _AuthOptions(dio));
    await repo.searchListings({'purpose': 'sale&search=x'});
    await repo.searchListings({'purpose': 'sale', 'search': 'x'});
    expect(gets, 2);
    delay = true;
    final stale = repo.searchListings({'search': 'delayed'});
    await Future<void>.delayed(Duration.zero);
    await repo.deleteListing(77);
    pending.complete(); await stale;
    await repo.searchListings({'search': 'delayed'});
    expect(gets, 4);
    await repo.searchListings({'search': 'delayed'});
    expect(gets, 4);
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets('inbox preserves rows on 503 and removes them on 403 or account replacement', (tester) async {
    final auth = _Auth(), repo = _Messages()..onThreads = () async => [_thread];
    await tester.pumpWidget(ProviderScope(overrides: [authControllerProvider.overrideWith(() => auth),
      messageRepositoryProvider.overrideWithValue(repo)], child: const MaterialApp(home: MessagesScreen())));
    await tester.pumpAndSettle();
    expect(find.text('محادثة اصطناعية'), findsOneWidget);
    repo.onThreads = () async => throw _failure();
    await tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh(); await tester.pumpAndSettle();
    expect(find.text('محادثة اصطناعية'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    repo.onThreads = () async => throw _failure(403);
    await tester.tap(find.text('إعادة المحاولة')); await tester.pumpAndSettle();
    expect(find.text('محادثة اصطناعية'), findsNothing);
    final late = Completer<List<MessageThreadSummary>>();
    repo.onThreads = () => late.future;
    await tester.tap(find.text('إعادة المحاولة')); await tester.pump();
    auth.change(null); await tester.pumpAndSettle();
    late.complete([_thread]); await tester.pumpAndSettle();
    expect(find.text('محادثة اصطناعية'), findsNothing);
    expect(find.text('سجّل الدخول للمتابعة.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets('conversation retry retains typed text and messages on 503, and clears denied content', (tester) async {
    final repo = _Messages()..onDetails = () async => _detail;
    await tester.pumpWidget(ProviderScope(overrides: [authControllerProvider.overrideWith(_Auth.new),
      messageRepositoryProvider.overrideWithValue(repo)], child: const MaterialApp(home: ConversationScreen(threadId: 1))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'نص لم أرسله');
    repo.onDetails = () async => throw _failure();
    await tester.tap(find.byTooltip('تحديث')); await tester.pumpAndSettle();
    expect(find.text('رسالة اصطناعية محفوظة'), findsOneWidget);
    expect(find.text('نص لم أرسله'), findsOneWidget);
    repo.onDetails = () async => throw _failure(404);
    await tester.tap(find.text('إعادة المحاولة')); await tester.pumpAndSettle();
    expect(find.text('رسالة اصطناعية محفوظة'), findsNothing);
    expect(find.text('نص لم أرسله'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets('property refresh retains same-actor content but never retains it after actor change', (tester) async {
    final repo = _Details()..onDetails = (id) async => _property(id);
    final auth = _Auth();
    final container = ProviderContainer(overrides: [authControllerProvider.overrideWith(() => auth),
      propertyRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const MaterialApp(home: PropertyDetailsScreen(propertyId: 77))));
    await tester.pumpAndSettle();
    expect(find.text('تفاصيل اصطناعية'), findsOneWidget);
    repo.onDetails = (_) async => throw _failure();
    container.invalidate(propertyDetailsProvider(77)); await tester.pumpAndSettle();
    expect(find.text('تفاصيل اصطناعية'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    auth.change(2); await tester.pumpAndSettle();
    expect(find.text('تفاصيل اصطناعية'), findsNothing);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 45)));
  test('nearby mutation clears both cache layers and ignores a pre-mutation response', () async {
    final container = ProviderContainer(); addTearDown(container.dispose);
    final dio = container.read(dioProvider), first = Completer<void>(); var gets = 0;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) async {
      if (request.method == 'GET') { gets++; if (gets == 1) await first.future; }
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {'data': <dynamic>[]}));
    }));
    final repo = PropertyRepository(dio, _AuthOptions(dio));
    final stale = repo.nearby(latitude: 15.3, longitude: 44.2);
    await Future<void>.delayed(Duration.zero);
    await repo.deleteListing(77); first.complete(); await stale;
    await repo.nearby(latitude: 15.3, longitude: 44.2);
    expect(gets, 2);
    await repo.nearby(latitude: 15.3, longitude: 44.2);
    expect(gets, 2);
    await repo.deleteListing(77);
    await repo.nearby(latitude: 15.3, longitude: 44.2);
    expect(gets, 3);
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets('customer pagination retries page two and retains its previous rows through a temporary failure', (tester) async {
    final repo = _Customers()..onCustomers = (page) async => BrokerPage(items: [_customer], page: page, lastPage: 2);
    final auth = _Auth();
    await tester.pumpWidget(ProviderScope(overrides: [authControllerProvider.overrideWith(() => auth),
      brokerRepositoryProvider.overrideWithValue(repo)], child: const MaterialApp(home: BrokerCustomersScreen())));
    await tester.pumpAndSettle();
    expect(find.text('عميل اصطناعي'), findsOneWidget);
    repo.onCustomers = (_) async => throw _failure();
    await tester.ensureVisible(find.text('تحميل المزيد')); await tester.tap(find.text('تحميل المزيد')); await tester.pumpAndSettle();
    expect(find.text('عميل اصطناعي'), findsOneWidget);
    repo.onCustomers = (page) async => BrokerPage(items: [_customer], page: page, lastPage: 2);
    await tester.ensureVisible(find.text('إعادة المحاولة')); await tester.tap(find.text('إعادة المحاولة')); await tester.pumpAndSettle();
    expect(repo.pages, [1, 2, 2]);
    expect(find.text('عميل اصطناعي'), findsOneWidget);
    expect(find.text('تحميل المزيد'), findsNothing);
    auth.change(null); await tester.pumpAndSettle();
    expect(find.text('عميل اصطناعي'), findsNothing);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 45)));

  for (final dark in [false, true]) {
    testWidgets('refresh feedback remains readable with large Arabic text in dark=$dark', (tester) async {
      tester.view.physicalSize = const Size(360, 800); tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(theme: dark ? AppTheme.dark : AppTheme.light,
        home: MediaQuery(data: const MediaQueryData(size: Size(360, 800), textScaler: TextScaler.linear(2.4)),
          child: Scaffold(body: AppRefreshStatus(error: friendlyApiError(_failure()), onRetry: () {})))));
      await tester.pumpAndSettle();
      expect(find.text('إعادة المحاولة'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, timeout: const Timeout(Duration(seconds: 45)));
  }

  testWidgets('verification refresh preserves edited fields through failure and successful retry', (tester) async {
    tester.view.physicalSize = const Size(390, 900); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final auth = _Auth(), repo = _Verification()..onStatus = () async => _verification();
    await tester.pumpWidget(ProviderScope(overrides: [authControllerProvider.overrideWith(() => auth),
      accountVerificationRepositoryProvider.overrideWithValue(repo)], child: const MaterialApp(home: AccountVerificationScreen())));
    await tester.pumpAndSettle();
    final field = find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'المناطق التي تعمل فيها');
    await tester.ensureVisible(field); await tester.enterText(field, 'تعديل لم أرسله');
    repo.onStatus = () async => throw _failure();
    await tester.tap(find.byTooltip('تحديث الحالة')); await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, 'تعديل لم أرسله');
    expect(find.byType(AppRefreshStatus), findsOneWidget);
    repo.onStatus = () async => _verification();
    await tester.ensureVisible(find.text('إعادة المحاولة')); await tester.tap(find.text('إعادة المحاولة')); await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, 'تعديل لم أرسله');
    auth.change(null); await tester.pumpAndSettle();
    expect(field, findsNothing);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets('repeated draft resume starts one read and a late failure stays outside the next account', (tester) async {
    final drafts = _Drafts(), auth = _Auth();
    drafts.drafts['synthetic'] = const ListingAccountDraft(key: 'synthetic', revision: 1, payload: {}, title: 'مسودة اصطناعية', progress: 40);
    await tester.pumpWidget(ProviderScope(overrides: [authControllerProvider.overrideWith(() => auth),
      listingAccountDraftRepositoryProvider.overrideWithValue(drafts), propertyRepositoryProvider.overrideWithValue(Wave6Properties())],
      child: const MaterialApp(home: ListingDraftEntryScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('متابعة الإعلان')); await tester.tap(find.text('متابعة الإعلان')); await tester.pump();
    expect(drafts.calls, 1);
    auth.change(null); await tester.pumpAndSettle();
    drafts.pending.completeError(_failure()); await tester.pumpAndSettle();
    expect(find.text('مسودة اصطناعية'), findsNothing);
    expect(find.text('سجّل الدخول للمتابعة.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets('empty private listing filter renders without intrinsic-layout exceptions', (tester) async {
    final repo = _Details()..onDetails = (id) async => _property(id);
    await tester.pumpWidget(ProviderScope(overrides: [authControllerProvider.overrideWith(_Auth.new),
      propertyRepositoryProvider.overrideWithValue(repo)], child: const MaterialApp(home: MyListingsScreen())));
    await tester.pumpAndSettle();
    final filter = find.text('منشورة (0)');
    await tester.ensureVisible(filter); await tester.pumpAndSettle(); await tester.tap(filter); await tester.pumpAndSettle();
    expect(find.text('لا توجد إعلانات في هذه الحالة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets('staff case refresh retains current rows on 503 and clears them at logout', (tester) async {
    final repo = _Support()..onCases = () async => [SupportCaseSummary.fromJson({'id': 1,
      'subject': 'تذكرة اصطناعية', 'reference': 'SYNTHETIC-1', 'status': 'open'})];
    final auth = _Auth();
    await tester.pumpWidget(ProviderScope(overrides: [authControllerProvider.overrideWith(() => auth),
      supportRepositoryProvider.overrideWithValue(repo)], child: const MaterialApp(home: SupportAdminScreen())));
    await tester.pumpAndSettle();
    expect(find.text('تذكرة اصطناعية'), findsOneWidget);
    repo.onCases = () async => throw _failure();
    await tester.tap(find.byTooltip('تحديث طلبات الدعم')); await tester.pumpAndSettle();
    expect(find.text('تذكرة اصطناعية'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    auth.change(null); await tester.pumpAndSettle();
    expect(find.text('تذكرة اصطناعية'), findsNothing);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 45)));

  test('a broker availability revision invalidates repository discovery results', () async {
    var calls = 0;
    final dio = Dio()..interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      calls++; handler.resolve(Response(requestOptions: request, statusCode: 200,
        data: {'data': <dynamic>[], 'meta': {'current_page': 1, 'last_page': 1}}));
    }));
    addTearDown(() => dio.close(force: true));
    final container = ProviderContainer(overrides: [dioProvider.overrideWithValue(dio),
      authRepositoryProvider.overrideWithValue(_AuthOptions(dio))]);
    addTearDown(container.dispose);
    final repo = container.read(propertyRepositoryProvider);
    await repo.searchListings({'purpose': 'sale'}); await repo.searchListings({'purpose': 'sale'});
    expect(calls, 1);
    container.read(propertyDataRevisionProvider.notifier).state++;
    await repo.searchListings({'purpose': 'sale'});
    expect(calls, 2);
  }, timeout: const Timeout(Duration(seconds: 45)));

}

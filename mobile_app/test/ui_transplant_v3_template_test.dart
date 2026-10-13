import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/core/local/listing_recovery_store.dart';
import 'package:real_estate_mobile/core/widgets/app_components.dart';
import 'package:real_estate_mobile/core/widgets/ebroker_widgets.dart';
import 'package:real_estate_mobile/core/widgets/ebroker_step_button.dart';
import 'package:real_estate_mobile/core/widgets/ebroker_otp_field.dart';
import 'package:real_estate_mobile/core/widgets/ebroker_property_card.dart';
import 'package:real_estate_mobile/core/widgets/ebroker_screen_sections.dart';
import 'package:real_estate_mobile/features/account/presentation/phone_verification_screen.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/data/favorites_repository.dart';
import 'package:real_estate_mobile/features/properties/data/property_market_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/properties/domain/property_sai.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_details_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_market_context_card.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_sai_public_line.dart';
import 'package:real_estate_mobile/features/properties/presentation/favorites_screen.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/account/presentation/auth_gate.dart';
import 'package:real_estate_mobile/features/account/presentation/auth_screen.dart';
import 'package:real_estate_mobile/features/agreements/data/agreement_repository.dart';
import 'package:real_estate_mobile/features/agreements/domain/agreement_models.dart';
import 'package:real_estate_mobile/features/app_shell/presentation/app_shell_screen.dart';
import 'package:real_estate_mobile/features/broker/data/broker_repository.dart';
import 'package:real_estate_mobile/features/bookings/data/booking_repository.dart';
import 'package:real_estate_mobile/features/bookings/domain/booking_models.dart';
import 'package:real_estate_mobile/features/discovery/presentation/marketplace_home_screen.dart';
import 'package:real_estate_mobile/features/map/presentation/map_screen.dart';
import 'package:real_estate_mobile/features/messages/data/message_repository.dart';
import 'package:real_estate_mobile/features/messages/domain/message_models.dart';
import 'package:real_estate_mobile/features/messages/presentation/conversation_screen.dart';
import 'package:real_estate_mobile/features/properties/domain/property_marker.dart';
import 'package:real_estate_mobile/features/properties/presentation/my_listings_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_editor_screen.dart';

// Layout fixtures isolate device IO; broker_convenience_test covers actual recovery files.
class _EmptyRecovery extends ListingRecoveryStore {
  @override
  Future<Map<String, dynamic>?> read(int userId, int? listingId) async => null;
  @override
  Future<void> write(int userId, int? listingId, Map<String, dynamic> snapshot, List<String> paths) async {}
  @override
  Future<void> clear(int userId, int? listingId) async {}
}

class _AuthFixture extends AuthController {
  _AuthFixture(this.user);
  final AuthUser? user;
  @override
  Future<AuthUser?> build() async => user;
}

AuthUser _user({bool verified = false}) => AuthUser.fromJson({
  'id': 1, 'name': 'حساب عرض تجريبي', 'phone': '+967700000000',
  'account_status': 'active', 'phone_verified_at': '2026-10-11T00:00:00Z',
  'profile_completed_at': '2026-10-11T00:00:00Z',
  if (verified) 'verification_profile': {
    'type': 'owner', 'status': 'approved', 'reviewed_at': '2026-10-11T00:00:00Z',
  },
});

final _property = PropertyMarker.fromJson({
  'id': 37, 'title': 'منزل للعائلة في حدة', 'display_price': 102000000,
  'price': 100000000, 'currency': 'YER', 'address': 'صنعاء، حدة',
  'latitude': 15.3694, 'longitude': 44.1910, 'purpose': 'sale', 'type': 'house',
});

class _MessagesFixture implements MessageRepository {
  _MessagesFixture({this.canManageCustomer = false});
  final bool canManageCustomer;
  final sent = <String>[];
  final sentThreadIds = <int>[];
  @override
  Future<MessageThreadDetails> details(int threadId, {int? beforeId}) async =>
    MessageThreadDetails.fromJson({
      'thread': {'id': threadId, 'property_id': 37, 'property_status': 'published',
        'can_manage_customer': canManageCustomer, 'property_title': _property.title, 'other_user': {'id': 2, 'name': 'المعلن'}},
      'messages': [
        {'id': 1, 'sender_user_id': 2, 'sender_name': 'المعلن',
          'body': 'مرحباً، كيف أستطيع مساعدتك؟', 'is_mine': false},
        {'id': 2, 'sender_user_id': 1, 'sender_name': 'أنت',
          'body': 'أرغب بمعرفة تفاصيل العقار.', 'is_mine': true},
        for (var i = 0; i < sent.length; i++)
          {'id': i + 3, 'sender_user_id': 1, 'sender_name': 'أنت',
            'body': sent[i], 'is_mine': true},
      ],
    });
  @override
  Future<PrivateMessageItem> send(int threadId, String body, {String? clientMessageId}) async {
    sent.add(body);
    sentThreadIds.add(threadId);
    return PrivateMessageItem(id: 3, senderUserId: 1, senderName: 'أنت',
      body: body, isMine: true, clientMessageId: clientMessageId);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

PropertyDetails _details(int id, {int advertiserId = 2, String status = 'published'}) => PropertyDetails.fromJson({
  'id': id, 'title': 'منزل للعائلة في حدة', 'description': 'عقار عرض تجريبي لاختبار التصميم، ببيانات مصطنعة.',
  'purpose': 'sale', 'type': 'house', 'status': status, 'display_price': 102000000,
  'price': 100000000, 'currency': 'YER', 'address': 'صنعاء، حدة',
  'latitude': 15.3694, 'longitude': 44.1910, 'area_m2': 240,
  'bedrooms': 4, 'bathrooms': 3, 'has_parking': true,
  'advertiser': {'id': advertiserId, 'name': 'معلن تجريبي', 'rating_average': 4.5,
    'rating_count': 8, 'verification_type': 'owner', 'verification_label': 'مالك موثق',
    'verification_status': 'approved', 'verification_flags': {'identity_verified': true}},
});
class _PropertiesFixture implements PropertyRepository {
  _PropertiesFixture({this.values});
  final Map<int, PropertyDetails>? values;
  final requested = <int>[];
  @override
  Future<PropertyDetails> details(int id) async {
    requested.add(id);
    if (values != null) return values![id] ?? (throw StateError('fixture unavailable'));
    return _details(id);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
ViewingBooking _booking({int id = 42, int threadId = 19, bool canConfirm = true}) => ViewingBooking.fromJson({
  'id': id, 'reference': 'PREVIEW-$id', 'requester_user_id': 1, 'requester_name': 'طالب تجريبي',
  'host_user_id': 2, 'host_name': 'معلن تجريبي', 'message_thread_id': threadId,
  'target_type': 'property', 'target_id': 37, 'target_title': 'منزل تجريبي',
  'starts_at': '2026-10-20T10:00:00Z', 'ends_at': '2026-10-20T11:00:00Z',
  'timezone': 'Asia/Aden', 'status': 'requested', 'can_confirm': canConfirm,
});
class _BookingsFixture implements BookingRepository {
  _BookingsFixture({this.items = const []});
  final List<ViewingBooking> items;
  final confirmed = <int>[];
  @override
  Future<List<ViewingBooking>> mine({DateTime? from, DateTime? before}) async => items;
  @override
  Future<ViewingBooking> confirm(int bookingId, {String? note}) async {
    confirmed.add(bookingId);
    return items.firstWhere((item) => item.id == bookingId);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
class _AgreementsFixture implements AgreementRepository {
  @override
  Future<List<PropertyAgreement>> mine() async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<GoRouter> _pump(WidgetTester tester, {AuthUser? user, double scale = 1,
  GlobalKey? boundary, String initial = '/', _MessagesFixture? messages,
  _PropertiesFixture? properties, _BookingsFixture? bookings}) async {
  final router = GoRouter(initialLocation: initial, routes: [
    GoRoute(path: '/', builder: (_, __) => const AppShellScreen()),
    GoRoute(path: '/auth', builder: (_, __) => const AuthScreen()),
    GoRoute(path: '/favorites', builder: (_, __) => const Stage6AuthGate(
      child: FavoritesScreen())),
    GoRoute(path: '/my-listings', builder: (_, __) => const Stage6AuthGate(
      child: MyListingsScreen())),
    GoRoute(path: '/add-property', builder: (_, __) => const Stage6AuthGate(
      requireListingEligible: true, child: Scaffold(body: Text('listing destination')))),
    GoRoute(path: '/messages/:id', builder: (_, state) => ConversationScreen(
      threadId: int.parse(state.pathParameters['id']!))),
    GoRoute(path: '/listing-preview', builder: (_, __) => const ListingEditorScreen()),
    GoRoute(path: '/properties/:id', builder: (_, state) => PropertyDetailsScreen(
      propertyId: int.parse(state.pathParameters['id']!))),
    GoRoute(path: '/verify-phone', builder: (_, __) => const PhoneVerificationScreen()),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(overrides: [
    authControllerProvider.overrideWith(() => _AuthFixture(user)),
    listingRecoveryStoreProvider.overrideWithValue(_EmptyRecovery()),
    brokerDirectoryProvider.overrideWith((_) async => []),
    brokerThreadDealProvider.overrideWith((_, __) async => null),
    brokerWorkspaceProvider.overrideWith((_) async => {'broker_profile': {'id': 1, 'name': 'حساب عرض تجريبي', 'account_type': 'owner', 'verified': true}, 'listings': {'published': 1}, 'customer_activity': {}, 'needs_attention': {}, 'financial_summary': {}}),
    nearbyPropertiesProvider.overrideWith((ref, query) async => [_property]),
    myListingsProvider.overrideWith((ref) async => [_details(37)]),
    messageRepositoryProvider.overrideWithValue(messages ?? _MessagesFixture()),
    bookingRepositoryProvider.overrideWithValue(bookings ?? _BookingsFixture()),
    propertyRepositoryProvider.overrideWithValue(properties ?? _PropertiesFixture()),
    favoritePropertiesProvider.overrideWith((ref) async => [_property]),
    favoritePropertyIdsProvider.overrideWith((ref) async => <int>{37}),
    propertySaiPublicProvider.overrideWith((ref, id) async => const PropertySaiEnvelope()),
    propertyMarketContextProvider.overrideWith((ref, id) async => const PropertyMarketContext(
      sufficientData: false, sampleCount: 0)),
    agreementRepositoryProvider.overrideWithValue(_AgreementsFixture()),
  ], child: MaterialApp.router(theme: AppTheme.light, routerConfig: router,
    builder: (context, child) => RepaintBoundary(key: boundary,
      child: MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: Directionality(textDirection: TextDirection.rtl, child: child!))))));
  await tester.pumpAndSettle();
  return router;
}

void _viewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/v3-preview/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final entry in {'NotoSansArabic': 'assets/fonts/NotoSansArabic',
      'PrimaryFont': 'assets/ebroker/fonts/Manrope'}.entries) {
      final loader = FontLoader(entry.key);
      for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        loader.addFont(rootBundle.load('${entry.value}-$weight.ttf'));
      }
      await loader.load();
    }
    final dir = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
    for (final entry in {'MaterialIcons': 'MaterialIcons-Regular.otf',
      'Arial': 'Roboto-Regular.ttf', 'sans-serif': 'Roboto-Regular.ttf'}.entries) {
      final data = await File('$dir/${entry.value}').readAsBytes();
      final loader = FontLoader(entry.key)..addFont(Future.value(data.buffer.asByteData()));
      if (entry.key == 'sans-serif') loader.addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
      await loader.load();
    }
  });

  testWidgets('template button retains MaterialButton, 56 height, 4 corners and loading lock', (tester) async {
    _viewport(tester, const Size(412, 915));
    var taps = 0;
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: Scaffold(
      body: EbrokerButton(onPressed: () => taps++, child: const Text('متابعة')))));
    final material = tester.widget<MaterialButton>(find.byType(MaterialButton));
    expect(material.height, 56);
    expect(material.elevation, 0.5);
    expect((material.shape! as RoundedRectangleBorder).borderRadius, BorderRadius.circular(4));
    await tester.tap(find.text('متابعة'));
    expect(taps, 1);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: Scaffold(
      body: EbrokerButton(onPressed: () => taps++, loading: true, child: const Text('متابعة')))));
    expect(tester.widget<MaterialButton>(find.byType(MaterialButton)).onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(taps, 1);
  });

  testWidgets('profile favorites entry opens its existing account gate', (tester) async {
    final router = await _pump(tester);
    final nav = tester.getRect(find.byType(AppNavigationBar));
    expect(nav.height, lessThan(tester.view.physicalSize.height * 0.45));
    await tester.tap(find.text('حسابي'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('المفضلة').hitTestable());
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/favorites');
    expect(find.text('سجّل الدخول أولاً'), findsOneWidget);
    expect(find.text('favorites destination'), findsNothing);
  });

  testWidgets('wizard uses its template counter and keeps original field validation', (tester) async {
    await _pump(tester, user: _user(verified: true), initial: '/listing-preview');
    expect(find.text('1/4'), findsOneWidget);
    expect(find.byType(EbrokerWizardCategoryCard), findsNWidgets(9));
    final grid = tester.widget<GridView>(find.byType(GridView));
    expect((grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount).crossAxisCount, 3);
    expect(find.text('نوع الملكية *'), findsOneWidget);
    await tester.tap(find.text('للإيجار'));
    await tester.pumpAndSettle();
    expect(find.text('نوع الملكية *'), findsNothing);
    final purpose = tester.widget<EbrokerSegmentedButton<String>>(find.byType(EbrokerSegmentedButton<String>));
    expect(purpose.selected, {'rent'});
    final next = find.widgetWithText(EbrokerStepButton, 'التالي');
    expect(next, findsOneWidget);
    final button = tester.widget<ElevatedButton>(find.descendant(of: next, matching: find.byType(ElevatedButton)));
    expect((button.style!.shape!.resolve({})! as RoundedRectangleBorder).borderRadius, BorderRadius.circular(6));
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('1/4'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('template optional filter preserves clear selection and disabled chips', (tester) async {
    _viewport(tester, const Size(412, 915));
    final values = <Set<String>>[];
    var disabledTaps = 0;
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: Scaffold(
      body: Column(children: [
        EbrokerSegmentedButton<String>(
          segments: const [ButtonSegment(value: 'sale', label: Text('شراء'))],
          selected: const {'sale'}, emptySelectionAllowed: true,
          onSelectionChanged: values.add),
        const EbrokerFilterChip(label: Text('معطل'), selected: true, onSelected: null),
        EbrokerFilterChip(label: const Text('نشط'), selected: false,
          onSelected: (value) { if (value) disabledTaps++; }),
      ]))));
    await tester.tap(find.text('شراء'));
    expect(values, [<String>{}]);
    await tester.tap(find.text('معطل'));
    expect(disabledTaps, 0);
    await tester.tap(find.text('نشط'));
    expect(disabledTaps, 1);
    expect(tester.takeException(), isNull);
  });

  for (final verified in [false, true]) {
    testWidgets('center add button enforces publishing eligibility verified=$verified', (tester) async {
      final router = await _pump(tester, user: _user(verified: verified));
      final shape = find.byWidgetPredicate((w) => w is EbrokerImage && w.name == 'add_shape');
      expect(shape, verified ? findsNothing : findsOneWidget);
      await tester.tap(verified ? find.text('إضافة عقار') : find.byTooltip('إضافة عقار'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/add-property');
      expect(find.text(verified ? 'listing destination' : 'توثيق نوع الحساب مطلوب'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('consumer partitions use four template tabs and protect own listings', (tester) async {
    await _pump(tester, user: _user());
    expect(find.byType(MarketplaceHomeScreen), findsOneWidget);
    final nav = tester.widget<AppNavigationBar>(find.byType(AppNavigationBar));
    expect(nav.destinations.map((d) => d.label), ['العقارات', 'الرسائل', 'إعلاناتي', 'حسابي']);
    await tester.tap(find.text('إعلاناتي'));
    await tester.pumpAndSettle();
    expect(find.text('توثيق نوع الحساب مطلوب'), findsOneWidget);
    expect(find.byType(MyListingsScreen), findsNothing);
  });

  testWidgets('conversation keeps existing repository send and thread identity', (tester) async {
    final messages = _MessagesFixture();
    await _pump(tester, initial: '/messages/19', messages: messages);
    expect(find.text('مرحباً، كيف أستطيع مساعدتك؟'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'هل العقار متاح؟');
    await tester.tap(find.byWidgetPredicate((w) => w is EbrokerIcon && w.icon == Icons.send));
    await tester.pumpAndSettle();
    expect(messages.sent, ['هل العقار متاح؟']);
    expect(messages.sentThreadIds, [19]);
    expect(find.text('هل العقار متاح؟'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quick reply is editable and only sends after the original send button', (tester) async {
    final messages = _MessagesFixture(canManageCustomer: true);
    await _pump(tester, user: _user(verified: true), initial: '/messages/19', messages: messages);
    await tester.tap(find.byTooltip('ردود سريعة')); await tester.pumpAndSettle();
    await tester.tap(find.text('سأرد عليك')); await tester.pumpAndSettle();
    expect(messages.sent, isEmpty);
    final editor = tester.widget<TextField>(find.byType(TextField));
    expect(editor.controller!.text, isNotEmpty);
    await tester.enterText(find.byType(TextField), 'سأرد عليك بعد العصر.');
    expect(messages.sent, isEmpty);
    await tester.tap(find.byWidgetPredicate((w) => w is EbrokerIcon && w.icon == Icons.send));
    await tester.pumpAndSettle();
    expect(messages.sent, ['سأرد عليك بعد العصر.']); expect(messages.sentThreadIds, [19]);
    expect(tester.takeException(), isNull);
  });

  for (final page in ['/', '/auth', '/messages/19', '/listing-preview', '/properties/37', '/favorites', '/verify-phone']) {
    for (final scale in (page == '/properties/37' || page == '/favorites' || page == '/verify-phone') ? [1.0, 2.4] : [2.4]) {
    testWidgets('template screen $page supports 320 width and Arabic scale $scale', (tester) async {
      _viewport(tester, const Size(320, 640));
      await _pump(tester, initial: page, scale: scale, user: _user());
      expect(tester.takeException(), isNull);
      if (page == '/') {
        await tester.tap(find.text('حسابي'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }

    }

  testWidgets('own listing source card supports enlarged Arabic without losing review controls', (tester) async {
    _viewport(tester, const Size(320, 640));
    await _pump(tester, scale: 2.4, user: _user(verified: true));
    await tester.tap(find.text('عملي'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('عقارات نشطة'), 250, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('عقارات نشطة'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byType(EbrokerPropertyHorizontalCard), 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.byType(EbrokerPropertyHorizontalCard), findsOneWidget);
    final listingScroll = find.ancestor(of: find.byType(EbrokerPropertyHorizontalCard), matching: find.byType(Scrollable)).last;
    await tester.scrollUntilVisible(find.byTooltip('خيارات البطاقة').hitTestable(), 180, scrollable: listingScroll);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('خيارات البطاقة').hitTestable()); await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('تعديل').hitTestable(), 100, scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
    expect(find.text('تعديل').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('home advertisers are bounded, deduplicated and restricted to public results', () async {
    final properties = _PropertiesFixture(values: {
      37: _details(37), 38: _details(38), 39: _details(39, status: 'archived'),
      40: _details(40, advertiserId: 3), 42: _details(42, advertiserId: 4),
    });
    final container = ProviderContainer(overrides: [
      propertyRepositoryProvider.overrideWithValue(properties),
      nearbyPropertiesProvider.overrideWith((ref, query) async => [
        for (var id = 37; id <= 42; id++) PropertyMarker.fromJson({'id': id, 'title': 'تجريبي', 'type': 'house'}),
      ]),
    ]);
    addTearDown(container.dispose);
    final subscription = container.listen(homeAdvertisersProvider(homeDiscoveryQuery), (_, __) {});
    addTearDown(subscription.close);
    final entries = await container.read(homeAdvertisersProvider(homeDiscoveryQuery).future);
    expect(properties.requested, [37, 38, 39, 40, 41]);
    expect(entries.map((entry) => entry.propertyId), [37, 40]);
    expect(entries.map((entry) => entry.advertiser.id), [2, 3]);
  });

  testWidgets('underline OTP retains digit filtering, autofill and submission', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    String? submitted;
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: Scaffold(
      body: EbrokerOtpField(controller: controller, onSubmitted: (value) => submitted = value))));
    final field = find.byType(TextField);
    await tester.enterText(field, '12a34567');
    await tester.pump();
    expect(controller.text, '123456');
    expect(tester.widget<TextField>(field).autofillHints, [AutofillHints.oneTimeCode]);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(submitted, '123456');
    expect(tester.takeException(), isNull);
  });

  testWidgets('favorite source card opens its original property route', (tester) async {
    final router = await _pump(tester, initial: '/favorites', user: _user());
    expect(find.byType(EbrokerPropertyHorizontalCard), findsOneWidget);
    await tester.tap(find.text(_property.title));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/properties/37');
    expect(find.byType(EbrokerPropertyHeading), findsOneWidget);
    expect(find.text('تواصل مع المعلن'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final allowed in [false, true]) {
    testWidgets('linked viewing action follows server permission canConfirm=$allowed', (tester) async {
      final bookings = _BookingsFixture(items: [_booking(threadId: 20, id: 41), _booking(canConfirm: allowed)]);
      await _pump(tester, initial: '/messages/19', bookings: bookings);
      expect(find.text('طلب معاينة مرتبط بهذه المحادثة'), findsOneWidget);
      expect(find.text('تأكيد الموعد'), allowed ? findsOneWidget : findsNothing);
      if (allowed) {
        await tester.ensureVisible(find.text('تأكيد الموعد'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('تأكيد الموعد'));
        await tester.pumpAndSettle();
        expect(bookings.confirmed, [42]);
      } else {
        expect(bookings.confirmed, isEmpty);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('exports actual template screens using clearly synthetic fixtures', (tester) async {
    final previousShadows = debugDisableShadows;
    debugDisableShadows = false;
    try {
      _viewport(tester, const Size(412, 915));
      final key = GlobalKey();
      final router = await _pump(tester, boundary: key, user: _user(verified: true));
      await _capture(tester, key, 'template-home-navigation');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -260));
      await tester.pumpAndSettle();
      await _capture(tester, key, 'template-home-advertisers');
      await tester.tap(find.text('عملي'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('عقارات نشطة'), 250, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('عقارات نشطة'));
      await tester.pumpAndSettle();
      await _capture(tester, key, 'template-my-listings');
      router.pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('حسابي'));
      await tester.pumpAndSettle();
      await _capture(tester, key, 'template-account');
      router.push('/auth');
      await tester.pumpAndSettle();
      await _capture(tester, key, 'template-auth');
      router.pop();
      router.push('/listing-preview');
      await tester.pumpAndSettle();
      await _capture(tester, key, 'template-listing-editor');
      router.pop();
      router.push('/messages/19');
      await tester.pumpAndSettle();
      await _capture(tester, key, 'template-conversation');
      router.pop();
      router.push('/properties/37');
      await tester.pumpAndSettle();
      await _capture(tester, key, 'template-property-details');
      await tester.drag(find.byType(ListView).first, const Offset(0, -650));
      await tester.pumpAndSettle();
      await _capture(tester, key, 'template-property-advertiser');
      router.pop();
      router.push('/favorites');
      await tester.pumpAndSettle();
      await _capture(tester, key, 'template-favorites');
      router.pop();
      router.push('/verify-phone');
      await tester.pumpAndSettle();
      await _capture(tester, key, 'template-phone-verification');
      expect(tester.takeException(), isNull);
    } finally {
      debugDisableShadows = previousShadows;
    }
  });
}

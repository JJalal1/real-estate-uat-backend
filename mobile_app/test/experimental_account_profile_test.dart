import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:real_estate_mobile/core/design/app_design.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/account/data/auth_return_intent.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/account/presentation/account_screen.dart';
import 'package:real_estate_mobile/features/account/presentation/profile_screen.dart';
import 'package:real_estate_mobile/features/account/presentation/complete_profile_screen.dart';

import 'support/capture_design.dart';
import 'support/design_test_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadDesignTestFonts);

  for (final role in ['buyer', 'owner', 'broker', 'office', 'support_agent', 'support_manager', 'super_admin', 'platform_owner']) {
    testWidgets('account keeps role visibility for $role in enlarged Arabic', (tester) async {
      final repository = _Auth(_user(role: role));
      final key = GlobalKey();
      await _open(tester, repository, const AccountScreen(), size: const Size(320, 915), scale: 2.4, captureKey: key);
      await captureDesign(tester, key, 'account-$role-320-2.4');
      final labels = await _allLabels(tester);
      final admin = ['support_agent', 'support_manager', 'super_admin', 'platform_owner'].contains(role);
      for (final label in ['الملف الشخصي', 'الإشعارات', 'مدفوعاتي', 'تسجيل الخروج']) {
        expect(labels, contains(label));
      }
      for (final label in ['الخدمات والأدوات', 'المساعدة والدعم', 'نشاطي', 'المعاينات', 'اتفاقاتي وعقودي', 'المفضلة']) {
        expect(labels.contains(label), !admin, reason: '$role / $label');
      }
      for (final label in ['إدارة عقاراتي', 'إعلاناتي', 'إضافة عقار', 'الحساب المالي']) {
        expect(labels.contains(label), ['owner', 'broker', 'office'].contains(role), reason: '$role / $label');
      }
      expect(labels.contains('مساحة العمل منفصلة عن الحساب'), admin);
      await _tap(tester, find.text('الملف الشخصي'));
      expect(find.text('route:/profile'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('anonymous account opens existing auth route', (tester) async {
    await _open(tester, _Auth(null), const AccountScreen());
    expect(find.text('تصفح العقارات بحرية وسجّل الدخول عند الحاجة.'), findsOneWidget);
    expect(find.text('تسجيل الخروج'), findsNothing);
    await _tap(tester, find.text('تسجيل الدخول أو إنشاء حساب'));
    expect(find.text('route:/auth'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account loading error retry and logout retain session behavior', (tester) async {
    final initial = Completer<AuthUser?>();
    final repository = _Auth(_user())..pendingRestore = initial;
    await _open(tester, repository, const AccountScreen(), size: const Size(600, 280), scale: 2.4, settle: false);
    expect(find.byType(AppLoadingState), findsOneWidget);
    initial.completeError(StateError('fixture offline'));
    await tester.pumpAndSettle();
    expect(find.byType(AppErrorState), findsOneWidget);
    repository.pendingRestore = null;
    await _tap(tester, find.text('إعادة المحاولة'));
    expect(repository.restoreCalls, 2);
    await _tap(tester, find.text('تسجيل الخروج'));
    expect(repository.logoutCalls, 1);
    await _reveal(tester, find.text('تسجيل الدخول أو إنشاء حساب'));
    expect(find.text('تسجيل الخروج'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final viewport in [
    (const Size(320, 915), 1.0), (const Size(320, 915), 2.4),
    (const Size(412, 915), 2.4), (const Size(600, 280), 2.4),
  ]) {
    testWidgets('profile RTL $viewport keeps exact update payload and busy action', (tester) async {
      final repository = _Auth(_user());
      final key = GlobalKey();
      await _open(tester, repository, const ProfileScreen(), size: viewport.$1, scale: viewport.$2, captureKey: key);
      final name = find.widgetWithText(TextField, 'الاسم الرباعي');
      final phone = find.widgetWithText(TextField, 'رقم الهاتف');
      await _reveal(tester, name);
      expect(tester.widget<TextField>(name).enabled, isTrue);
      await tester.enterText(name, '  اسم عربي كامل جديد  ');
      await _reveal(tester, phone);
      await tester.enterText(phone, '+967712345678');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(phone).textDirection, TextDirection.ltr);
      await captureDesign(tester, key, 'profile-${viewport.$1.width.toInt()}-${viewport.$1.height.toInt()}-${viewport.$2}');
      await _reveal(tester, find.text('حفظ'));
      final pending = Completer<AuthUser>();
      repository.pendingUpdate = pending;
      await tester.tap(find.text('حفظ'));
      await tester.pump();
      expect(repository.updates, [('  اسم عربي كامل جديد  ', '+967712345678')]);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'حفظ')).onPressed, isNull);
      pending.complete(_user());
      await tester.pumpAndSettle();
      expect(find.text('تم حفظ الملف الشخصي.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('complete profile RTL $viewport retains four-part validation and return intent', (tester) async {
      final repository = _Auth(_user());
      final container = await _open(tester, repository, const CompleteProfileScreen(), size: viewport.$1, scale: viewport.$2);
      container.read(authReturnLocationProvider.notifier).state = '/return';
      for (final invalid in ['اسم من ثلاثة', 'اسم يتكون من خمسة أجزاء']) {
        await _reveal(tester, find.byType(TextField));
        await tester.enterText(find.byType(TextField), invalid);
        await _tap(tester, find.text('حفظ ومتابعة'));
        expect(repository.completedNames, isEmpty);
        expect(find.text('أدخل الاسم الرباعي كاملًا.'), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      }
      await _reveal(tester, find.byType(TextField));
      await tester.enterText(find.byType(TextField), '  أحمد  محمد علي سالم  ');
      await _tap(tester, find.text('حفظ ومتابعة'));
      expect(repository.completedNames, ['  أحمد  محمد علي سالم  ']);
      expect(find.text('route:/return'), findsOneWidget);
      expect(container.read(authReturnLocationProvider), isNull);
      expect(tester.takeException(), isNull);
    });
  }

  for (final status in ['pending', 'approved']) {
    testWidgets('profile $status keeps identity name locked', (tester) async {
      final repository = _Auth(_user(status: status));
      await _open(tester, repository, const ProfileScreen(), size: const Size(320, 915), scale: 2.4);
      final name = find.widgetWithText(TextField, 'الاسم الرباعي');
      await _reveal(tester, name);
      expect(tester.widget<TextField>(name).enabled, isFalse);
      expect(tester.widget<TextField>(name).controller!.text, repository.user!.name);
      await _reveal(tester, find.textContaining('الاسم مرتبط بمراجعة الهوية'));
      expect(repository.updates, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}

AuthUser _user({String role = 'buyer', String status = 'not_submitted'}) => AuthUser.fromJson({
  'id': 1, 'name': 'أحمد محمد علي سالم باسم عربي طويل', 'email': 'fixture@example.test',
  'phone': '+967700000001', 'account_status': 'active', 'phone_verified_at': '2026-01-01T00:00:00Z',
  'profile_completed_at': '2026-01-01T00:00:00Z',
  'is_platform_owner': role == 'platform_owner',
  'roles': ['support_agent', 'support_manager', 'super_admin'].contains(role) ? [role] : [],
  'verification_profile': {
    if (['owner', 'broker', 'office'].contains(role)) 'type': role,
    'status': ['owner', 'broker', 'office'].contains(role) ? 'approved' : status,
    if (['owner', 'broker', 'office'].contains(role)) 'reviewed_at': '2026-01-01T00:00:00Z',
  },
});

class _Auth extends AuthRepository {
  _Auth(this.user) : super(Dio());
  AuthUser? user;
  Completer<AuthUser?>? pendingRestore;
  Completer<AuthUser>? pendingUpdate;
  int restoreCalls = 0;
  int logoutCalls = 0;
  final updates = <(String, String)>[];
  final completedNames = <String>[];
  @override
  Future<AuthUser?> restoreSession() async {
    restoreCalls++;
    return pendingRestore == null ? user : pendingRestore!.future;
  }
  @override
  Future<AuthUser> updateProfile({required String name, required String phone}) async {
    updates.add((name, phone));
    return pendingUpdate == null ? user! : pendingUpdate!.future;
  }
  @override
  Future<AuthUser> completeProfile(String name) async {
    completedNames.add(name); return user!;
  }
  @override
  Future<void> logout() async { logoutCalls++; user = null; }
}

Future<Set<String>> _allLabels(WidgetTester tester) async {
  final labels = <String>{};
  final scroll = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
  final position = tester.state<ScrollableState>(scroll).position;
  for (var page = 0; page < 100; page++) {
    labels.addAll(tester.widgetList<Text>(find.byType(Text)).map((text) => text.data ?? ''));
    if (position.pixels >= position.maxScrollExtent) break;
    position.jumpTo((position.pixels + 180).clamp(0, position.maxScrollExtent).toDouble());
    await tester.pumpAndSettle();
  }
  expect(position.pixels, position.maxScrollExtent, reason: 'All account actions inspected.');
  return labels;
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  final lists = find.byType(ListView);
  if (lists.evaluate().isNotEmpty) {
    final scroll = find.descendant(of: lists.first, matching: find.byType(Scrollable)).first;
    if (target.evaluate().isEmpty) {
      tester.state<ScrollableState>(scroll).position.jumpTo(0);
      await tester.pumpAndSettle();
    }
    await tester.scrollUntilVisible(target, 160, scrollable: scroll, maxScrolls: 100);
  } else {
    await Scrollable.ensureVisible(tester.element(target), alignment: .5);
  }
  await tester.pumpAndSettle();
}
Future<void> _tap(WidgetTester tester, Finder target) async {
  await _reveal(tester, target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}
Future<ProviderContainer> _open(WidgetTester tester, _Auth repository, Widget screen, {
  Size size = const Size(412, 915), double scale = 1, bool settle = true, GlobalKey? captureKey,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(initialLocation: '/subject', routes: [
    GoRoute(path: '/subject', builder: (_, __) => screen),
    for (final path in ['/auth', '/profile', '/return'])
      GoRoute(path: path, builder: (_, __) => Scaffold(body: Text('route:$path'))),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(overrides: [authRepositoryProvider.overrideWithValue(repository)],
    child: RepaintBoundary(key: captureKey, child: MaterialApp.router(routerConfig: router,
      theme: AppTheme.light, debugShowCheckedModeBanner: false,
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
    )),
  ));
  if (settle) { await tester.pumpAndSettle(); } else { await tester.pump(); }
  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

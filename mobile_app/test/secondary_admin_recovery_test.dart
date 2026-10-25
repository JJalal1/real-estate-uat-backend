import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/core/widgets/app_components.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/admin/data/admin_workspace_repository.dart';
import 'package:real_estate_mobile/features/admin/domain/admin_workspace_models.dart';
import 'package:real_estate_mobile/features/admin/presentation/platform_settings_screen.dart';
import 'package:real_estate_mobile/features/developments/data/development_repository.dart';
import 'package:real_estate_mobile/features/developments/domain/development_models.dart';
import 'package:real_estate_mobile/features/developments/presentation/development_admin_screen.dart';

class _Auth extends AuthController {
  @override
  Future<AuthUser?> build() async => _user(1);
  void change(int id) => state = AsyncData(_user(id));
}

AuthUser _user(int id) => AuthUser.fromJson({
  'id': id, 'name': 'Synthetic administrator', 'account_status': 'active',
  'is_platform_owner': true, 'roles': ['super_admin'],
});

DioException _failure(int status) {
  final request = RequestOptions(path: '/synthetic-admin-only');
  return DioException(requestOptions: request, type: DioExceptionType.badResponse,
    response: Response<void>(requestOptions: request, statusCode: status));
}

class _Settings implements AdminWorkspaceRepository {
  late Future<List<PlatformSettingItem>> Function() onRead;
  int calls = 0;
  @override
  Future<List<PlatformSettingItem>> settings() { calls++; return onRead(); }
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}

class _Developments implements DevelopmentRepository {
  late Future<List<DeveloperSummary>> Function() onRead;
  int calls = 0;
  int projectCalls = 0;
  @override
  Future<List<DeveloperSummary>> adminDevelopers() { calls++; return onRead(); }
  @override
  Future<List<DevelopmentSummary>> adminProjects() async { projectCalls++; return []; }
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}

PlatformSettingItem _setting(String value) => PlatformSettingItem(
  key: 'contact', labelAr: 'قيمة اصطناعية', group: 'general', valueType: 'string', value: value);
DeveloperSummary _developer(String name) => DeveloperSummary(id: 1, name: name, slug: 'synthetic', status: 'active');

Future<ProviderContainer> _mount(WidgetTester tester, Widget page,
  {required _Settings settings, required _Developments developments, _Auth? auth, bool largeDark = false}) async {
  final container = ProviderContainer(overrides: [
    authControllerProvider.overrideWith(() => auth ?? _Auth()),
    adminWorkspaceRepositoryProvider.overrideWithValue(settings),
    developmentRepositoryProvider.overrideWithValue(developments),
  ]);
  addTearDown(container.dispose);
  await container.read(authControllerProvider.future);
  await tester.pumpWidget(UncontrolledProviderScope(container: container,
    child: MaterialApp(theme: largeDark ? AppTheme.dark : AppTheme.light,
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(largeDark ? 2.4 : 1)), child: child!), home: page)));
  await tester.pump();
  return container;
}

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;

  for (final settingsPage in [true, false]) {
    testWidgets('${settingsPage ? 'settings' : 'developments'} initial loading, friendly failure, retry and empty state', (tester) async {
      final pendingSettings = Completer<List<PlatformSettingItem>>();
      final pendingDevelopers = Completer<List<DeveloperSummary>>();
      final settings = _Settings()..onRead = () => pendingSettings.future;
      final developments = _Developments()..onRead = () => pendingDevelopers.future;
      await _mount(tester, settingsPage ? const PlatformSettingsScreen() : const DevelopmentAdminScreen(),
        settings: settings, developments: developments, largeDark: true);
      expect(find.byType(AppLoadingState), findsOneWidget);
      if (settingsPage) { pendingSettings.completeError(_failure(503)); }
      else { pendingDevelopers.completeError(_failure(503)); }
      await tester.pumpAndSettle();
      expect(find.byType(AppErrorState), findsOneWidget);
      expect(find.textContaining('DioException'), findsNothing);
      settings.onRead = () async => [];
      developments.onRead = () async => [];
      await tester.ensureVisible(find.text('إعادة المحاولة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إعادة المحاولة'));
      await tester.pumpAndSettle();
      expect(find.byType(AppEmptyState), findsOneWidget);
      expect(find.byType(AppErrorState), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('settings retains unsaved input on 503 but clears it after authorization rejection', (tester) async {
    final settings = _Settings()..onRead = () async => [_setting('confirmed')];
    await _mount(tester, const PlatformSettingsScreen(), settings: settings, developments: _Developments());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'unsaved local edit');
    settings.onRead = () async => throw _failure(503);
    await tester.tap(find.byTooltip('تحديث إعدادات المنصة'));
    await tester.pumpAndSettle();
    expect(find.text('unsaved local edit'), findsOneWidget);
    expect(find.byType(AppErrorState), findsNothing);
    settings.onRead = () async => throw _failure(403);
    await tester.tap(find.byTooltip('تحديث إعدادات المنصة'));
    await tester.pumpAndSettle();
    expect(find.text('unsaved local edit'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(AppErrorState), findsOneWidget);
  });

  testWidgets('developments retains rows on 503 but clears them on 403', (tester) async {
    final developments = _Developments()..onRead = () async => [_developer('صف مؤكد')];
    await _mount(tester, const DevelopmentAdminScreen(), settings: _Settings(), developments: developments);
    await tester.pumpAndSettle();
    developments.onRead = () async => throw _failure(503);
    await tester.tap(find.byTooltip('تحديث المطورين والمشاريع'));
    await tester.pumpAndSettle();
    expect(find.text('صف مؤكد'), findsOneWidget);
    developments.onRead = () async => throw _failure(403);
    await tester.tap(find.byTooltip('تحديث المطورين والمشاريع'));
    await tester.pumpAndSettle();
    expect(find.text('صف مؤكد'), findsNothing);
    expect(find.byType(AppErrorState), findsOneWidget);
  });

  testWidgets('settings ignores an old account receipt before allocating controllers', (tester) async {
    final pending = Completer<List<PlatformSettingItem>>();
    final settings = _Settings()..onRead = () => pending.future;
    final auth = _Auth();
    await _mount(tester, const PlatformSettingsScreen(),
      settings: settings, developments: _Developments(), auth: auth);
    settings.onRead = () async => [_setting('new account')];
    auth.change(2);
    await tester.pumpAndSettle();
    expect(find.text('new account'), findsOneWidget);
    pending.complete([_setting('old account')]);
    await tester.pumpAndSettle();
    expect(find.text('old account'), findsNothing);
    expect(find.text('new account'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('developments stops the old account request chain after account change', (tester) async {
    final pending = Completer<List<DeveloperSummary>>();
    final developments = _Developments()..onRead = () => pending.future;
    final auth = _Auth();
    await _mount(tester, const DevelopmentAdminScreen(), settings: _Settings(), developments: developments, auth: auth);
    developments.onRead = () async => [_developer('حساب جديد')];
    auth.change(2);
    await tester.pumpAndSettle();
    expect(developments.projectCalls, 1);
    pending.complete([_developer('حساب سابق')]);
    await tester.pumpAndSettle();
    expect(developments.projectCalls, 1);
    expect(find.text('حساب سابق'), findsNothing);
    expect(find.text('حساب جديد'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

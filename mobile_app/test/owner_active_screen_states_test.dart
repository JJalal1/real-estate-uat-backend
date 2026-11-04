import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/network/api_client.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/account/presentation/access_control_screen.dart';
import 'package:real_estate_mobile/features/account/presentation/account_verification_admin_screen.dart';
import 'package:real_estate_mobile/features/account/presentation/broker_verification_admin_screen.dart';
import 'package:real_estate_mobile/features/admin/presentation/admin_dashboard_screen.dart';
import 'package:real_estate_mobile/features/admin/presentation/audit_log_screen.dart';
import 'package:real_estate_mobile/features/admin/presentation/general_manager_accounts_screen.dart';
import 'package:real_estate_mobile/features/admin/presentation/general_manager_finance_screens.dart';
import 'package:real_estate_mobile/features/admin/presentation/general_manager_pages.dart';
import 'package:real_estate_mobile/features/admin/presentation/platform_settings_screen.dart';
import 'package:real_estate_mobile/features/broker/presentation/broker_activity.dart';
import 'package:real_estate_mobile/features/broker/presentation/broker_directory.dart';
import 'package:real_estate_mobile/features/broker/presentation/broker_workspaces.dart';
import 'package:real_estate_mobile/features/messages/presentation/notification_preferences_screen.dart';
import 'package:real_estate_mobile/features/messages/presentation/notifications_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/favorites_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/my_listings_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/saved_searches_screen.dart';
import 'package:real_estate_mobile/features/reviews/presentation/listing_review_workspace_screen.dart';
import 'package:real_estate_mobile/features/support/presentation/account_verification_support_screen.dart';
import 'package:real_estate_mobile/features/support/presentation/support_admin_screen.dart';
import 'package:real_estate_mobile/features/support/presentation/support_center_screen.dart';
import 'package:real_estate_mobile/features/support/presentation/support_tasks_screen.dart';
import 'package:real_estate_mobile/features/support/presentation/support_users_screen.dart';
import 'package:real_estate_mobile/features/support/presentation/support_work_log_screen.dart';
import 'package:real_estate_mobile/features/support/presentation/support_workspace_pages.dart';
import 'package:real_estate_mobile/features/support/presentation/support_workspace_screen.dart';

class _Auth extends AuthController {
  @override
  Future<AuthUser?> build() async => AuthUser.fromJson({
    'id':1,'name':'Synthetic administrator','account_status':'active',
    'phone_verified_at':'2026-10-26T00:00:00Z','profile_completed_at':'2026-10-26T00:00:00Z',
    'account_type':'broker','broker_verification_status':'approved','is_platform_owner':true,
    'roles':['super_admin'],
  });
}
class _Credentials implements AuthRepository {
  @override
  Future<Options> requiredAuthOptions() async => Options(headers:{'Authorization':'Bearer synthetic-only'});
  @override
  Future<Options?> optionalAuthOptions() async => requiredAuthOptions();
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}
Future<void> _frames(WidgetTester tester) async {
  for (var i=0;i<12;i++) { await tester.pump(const Duration(milliseconds:50)); }
}
Object _empty(String path) {
  if (path.contains('dashboard') || path.endsWith('/insights') || path.endsWith('/catalog') ||
      path.endsWith('/notification-preferences') || path.endsWith('/summary') || path.endsWith('/stats')) { return <String,dynamic>{}; }
  return <Object>[];
}
void main() {
  WidgetController.hitTestWarningShouldBeFatal=true;
  final screens=<String,Widget Function()>{
    'AdminDashboardScreen': () => const AdminDashboardScreen(),
    'AuditLogScreen': () => const AuditLogScreen(),
    'GeneralManagerAccountsScreen': () => const GeneralManagerAccountsScreen(),
    'GeneralManagerPaymentMethodsScreen': () => const GeneralManagerPaymentMethodsScreen(),
    'GeneralManagerFinanceWorkspaceScreen': () => const GeneralManagerFinanceWorkspaceScreen(),
    'GeneralManagerHomeScreen': () => const GeneralManagerHomeScreen(),
    'GeneralManagerMarketScreen': () => const GeneralManagerMarketScreen(),
    'GeneralManagerReportsScreen': () => const GeneralManagerReportsScreen(),
    'GeneralManagerTeamScreen': () => const GeneralManagerTeamScreen(),
    'SupportUsersScreen': () => const SupportUsersScreen(),
    'SupportWorkLogScreen': () => const SupportWorkLogScreen(),
    'SupportAgentHomeScreen': () => const SupportAgentHomeScreen(),
    'SupportManagerHomeScreen': () => const SupportManagerHomeScreen(),
    'SupportTeamScreen': () => const SupportTeamScreen(),
    'SupportWorkspaceScreen': () => const SupportWorkspaceScreen(),
    'SupportAdminScreen': () => const SupportAdminScreen(),
    'SupportCenterScreen': () => const SupportCenterScreen(),
    'SupportTasksScreen': () => const SupportTasksScreen(),
    'AccountVerificationSupportScreen': () => const AccountVerificationSupportScreen(),
    'AccessControlScreen': () => const AccessControlScreen(),
    'AccountVerificationAdminScreen': () => const AccountVerificationAdminScreen(),
    'BrokerVerificationAdminScreen': () => const BrokerVerificationAdminScreen(),
    'BrokerDashboardScreen': () => const BrokerDashboardScreen(),
    'BrokerCustomersScreen': () => const BrokerCustomersScreen(),
    'BrokerAvailabilityScreen': () => const BrokerAvailabilityScreen(),
    'BrokerActivityScreen': () => const BrokerActivityScreen(),
    'BrokerFinanceScreen': () => const BrokerFinanceScreen(),
    'BrokerDirectoryScreen': () => const BrokerDirectoryScreen(),
    'ListingReviewWorkspaceScreen': () => const ListingReviewWorkspaceScreen(),
    'NotificationsScreen': () => const NotificationsScreen(),
    'NotificationPreferencesScreen': () => const NotificationPreferencesScreen(),
    'MyListingsScreen': () => const MyListingsScreen(),
    'FavoritesScreen': () => const FavoritesScreen(),
    'SavedSearchesScreen': () => const SavedSearchesScreen(),
    'PlatformSettingsScreen': () => const PlatformSettingsScreen(),
  };
  for (final entry in screens.entries) {
    for (final dark in [false,true]) {
      testWidgets('${entry.key} loading 503 retry empty RTL ${dark ? 'dark large' : 'light'}', (tester) async {
        tester.view.physicalSize=const Size(360,740);tester.view.devicePixelRatio=1;
        addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
        final gate=Completer<void>();var status=503;var calls=0;
        final dio=Dio(BaseOptions(baseUrl:'https://synthetic.invalid/api'));
        dio.interceptors.add(InterceptorsWrapper(onRequest:(request,handler) async {
          calls++;await gate.future;
          if(status!=200) { handler.reject(DioException(requestOptions:request,type:DioExceptionType.badResponse,
            response:Response<Object>(requestOptions:request,statusCode:status,data:{'message':'Synthetic unavailable'})));return; }
          handler.resolve(Response<Map<String,dynamic>>(requestOptions:request,statusCode:200,
            data:{'data':_empty(request.path),'meta':{'current_page':1,'last_page':1,'total':0}}));
        }));
        final container=ProviderContainer(overrides:[
          authControllerProvider.overrideWith(_Auth.new),authRepositoryProvider.overrideWithValue(_Credentials()),
          dioProvider.overrideWithValue(dio),
        ]);
        addTearDown(() {container.dispose();dio.close(force:true);});
        addTearDown(() async { await tester.pumpWidget(const SizedBox.shrink()); await tester.pump(); });
        await container.read(authControllerProvider.future);
        await tester.pumpWidget(UncontrolledProviderScope(container:container,child:MaterialApp(
          theme:dark?AppTheme.dark:AppTheme.light,
          builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(
            textScaler:TextScaler.linear(dark?2.4:1),padding:const EdgeInsets.only(top:24,bottom:34)),
            child:Directionality(textDirection:TextDirection.rtl,child:child!)),home:entry.value())));
        await _frames(tester);
        expect(calls,greaterThan(0),reason:'An active data page must make its expected read');
        expect(tester.takeException(),isNull);
        gate.complete();await _frames(tester);
        if (find.textContaining('الخادم غير متاح مؤقتاً').evaluate().isEmpty) {
          final vertical = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
          if (vertical.evaluate().isNotEmpty) {
            await tester.scrollUntilVisible(find.textContaining('الخادم غير متاح مؤقتاً'), 300, scrollable: vertical.first, maxScrolls: 15);
          }
        }
        expect(find.textContaining('الخادم غير متاح مؤقتاً'),findsWidgets);
        expect(find.textContaining('DioException'),findsNothing);
        expect(tester.takeException(),isNull);
        status=200;final before=calls;
        final retry=find.text('إعادة المحاولة');
        expect(retry,findsWidgets,reason:'503 must expose a direct retry');
        await tester.ensureVisible(retry.first);await tester.pump();await tester.tap(retry.first);
        await _frames(tester);
        expect(calls,greaterThan(before));
        expect(find.textContaining('الخادم غير متاح مؤقتاً'),findsNothing);
        expect(tester.takeException(),isNull);
        expect(find.byType(Scaffold),findsWidgets);
        await tester.pumpWidget(const SizedBox.shrink());await tester.pump();
      });
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/account/presentation/access_control_screen.dart';
import '../features/account/presentation/account_verification_admin_screen.dart';
import '../features/account/presentation/account_verification_screen.dart';
import '../features/account/presentation/auth_gate.dart';
import '../features/account/presentation/auth_screen.dart';
import '../features/account/presentation/broker_account_verification_screen.dart';
import '../features/account/presentation/broker_verification_admin_screen.dart';
import '../features/account/presentation/complete_profile_screen.dart';
import '../features/account/presentation/forgot_password_screen.dart';
import '../features/account/presentation/phone_verification_screen.dart';
import '../features/account/presentation/profile_screen.dart';
import '../features/admin/presentation/admin_dashboard_screen.dart';
import '../features/admin/presentation/audit_log_screen.dart';
import '../features/admin/presentation/platform_settings_screen.dart';
import '../features/app_shell/presentation/app_shell_screen.dart';
import '../features/bookings/presentation/bookings_screen.dart';
import '../features/messages/presentation/conversation_reports_screen.dart';
import '../features/messages/presentation/conversation_screen.dart';
import '../features/messages/presentation/messages_screen.dart';
import '../features/messages/presentation/notifications_screen.dart';
import '../features/properties/presentation/add_property_wizard_screen.dart';
import '../features/properties/presentation/my_listings_screen.dart';
import '../features/properties/presentation/property_details_screen.dart';
import '../features/regions/presentation/regions_management_screen.dart';
import '../features/reviews/presentation/listing_review_screen.dart';
import '../features/support/presentation/support_admin_screen.dart';
import '../features/support/presentation/support_center_screen.dart';
import '../features/support/presentation/support_users_screen.dart';
import '../features/support/presentation/support_work_log_screen.dart';
import '../features/support/presentation/support_workspace_screen.dart';
import '../features/services/presentation/services_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    errorBuilder: (context, state) => const _RouteErrorScreen(),
    routes: [
      GoRoute(path: '/', builder: (context, state) => const AppShellScreen()),
      GoRoute(
        path: '/auth',
        builder: (context, state) => AuthScreen(
          startWithRegister: state.uri.queryParameters['register'] == '1',
        ),
      ),
      GoRoute(
        path: '/verify-phone',
        builder: (context, state) => const PhoneVerificationScreen(),
      ),
      GoRoute(
        path: '/complete-profile',
        builder: (context, state) => const Stage6AuthGate(
          requireActive: false,
          child: CompleteProfileScreen(),
        ),
      ),
      GoRoute(
        path: '/account-verification',
        builder: (context, state) => const Stage6AuthGate(
          child: AccountVerificationScreen(),
        ),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const Stage6AuthGate(
          requireActive: false,
          child: ProfileScreen(),
        ),
      ),
      GoRoute(
        path: '/admin/access',
        builder: (context, state) => const Stage6AuthGate(
          child: AccessControlScreen(),
        ),
      ),
      GoRoute(
        path: '/admin/dashboard',
        builder: (context, state) => const Stage6AuthGate(
          child: AdminDashboardScreen(),
        ),
      ),
      GoRoute(
        path: '/admin/settings',
        builder: (context, state) => const Stage6AuthGate(
          child: PlatformSettingsScreen(),
        ),
      ),
      GoRoute(
        path: '/admin/audit-log',
        builder: (context, state) => const Stage6AuthGate(
          child: AuditLogScreen(),
        ),
      ),
      GoRoute(
        path: '/admin/listing-review',
        builder: (context, state) => const Stage6AuthGate(
          child: ListingReviewScreen(),
        ),
      ),
      GoRoute(
        path: '/broker/account-verification',
        builder: (context, state) => const Stage6AuthGate(
          child: BrokerAccountVerificationScreen(),
        ),
      ),
      GoRoute(
        path: '/admin/broker-account-verifications',
        builder: (context, state) => const Stage6AuthGate(
          child: BrokerVerificationAdminScreen(),
        ),
      ),
      GoRoute(
        path: '/admin/account-verifications',
        builder: (context, state) => const Stage6AuthGate(
          child: AccountVerificationAdminScreen(),
        ),
      ),
      GoRoute(
        path: '/admin/regions',
        builder: (context, state) => const Stage6AuthGate(
          child: RegionsManagementScreen(),
        ),
      ),
      GoRoute(
        path: '/messages',
        builder: (context, state) =>
            const Stage6AuthGate(child: MessagesScreen()),
      ),
      GoRoute(
        path: '/messages/:id',
        builder: (context, state) {
          final threadId = int.tryParse(state.pathParameters['id'] ?? '');
          if (threadId == null || threadId <= 0) {
            return const _RouteErrorScreen();
          }
          return Stage6AuthGate(
            child: ConversationScreen(threadId: threadId),
          );
        },
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) =>
            const Stage6AuthGate(child: NotificationsScreen()),
      ),
      GoRoute(
        path: '/admin/message-reports',
        builder: (context, state) =>
            const Stage6AuthGate(child: ConversationReportsScreen()),
      ),
      GoRoute(
        path: '/bookings',
        builder: (context, state) =>
            const Stage6AuthGate(child: BookingsScreen()),
      ),
      GoRoute(
        path: '/services',
        builder: (context, state) =>
            const Stage6AuthGate(child: ServicesScreen()),
      ),
      GoRoute(
        path: '/support',
        builder: (context, state) => Stage6AuthGate(
          child: SupportCenterScreen(
            initialCaseId: int.tryParse(
              state.uri.queryParameters['case'] ?? '',
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/admin/support',
        builder: (context, state) => Stage6AuthGate(
          child: SupportAdminScreen(
            initialKind: state.uri.queryParameters['kind'],
            initialCaseId: int.tryParse(state.uri.queryParameters['case'] ?? ''),
          ),
        ),
      ),
      GoRoute(
        path: '/support/workspace',
        builder: (context, state) => const Stage6AuthGate(
          child: SupportWorkspaceScreen(),
        ),
      ),
      GoRoute(
        path: '/support/users',
        builder: (context, state) => const Stage6AuthGate(
          child: SupportUsersScreen(),
        ),
      ),
      GoRoute(
        path: '/support/worklog',
        builder: (context, state) => const Stage6AuthGate(
          child: SupportWorkLogScreen(),
        ),
      ),
      GoRoute(
        path: '/properties/:id',
        builder: (context, state) {
          final propertyId = int.tryParse(state.pathParameters['id'] ?? '');
          if (propertyId == null || propertyId <= 0) {
            return const _RouteErrorScreen();
          }
          return PropertyDetailsScreen(propertyId: propertyId);
        },
      ),
      GoRoute(
        path: '/add-property',
        builder: (context, state) => const Stage6AuthGate(
          requireListingEligible: true,
          child: AddPropertyWizardScreen(),
        ),
      ),
      GoRoute(
        path: '/my-listings',
        builder: (context, state) => const Stage6AuthGate(
          child: MyListingsScreen(),
        ),
      ),
    ],
  );
});

class _RouteErrorScreen extends StatelessWidget {
  const _RouteErrorScreen();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الرابط غير صالح')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.link_off_outlined, size: 52),
                const SizedBox(height: 16),
                const Text(
                  'تعذر فتح هذا الرابط. قد يكون قديمًا أو غير مكتمل.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => context.go('/'),
                  icon: const Icon(Icons.home_outlined),
                  label: const Text('العودة للرئيسية'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

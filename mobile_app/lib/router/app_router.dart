import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/account/presentation/access_control_screen.dart';
import '../features/account/presentation/auth_gate.dart';
import '../features/account/presentation/auth_screen.dart';
import '../features/account/presentation/broker_account_verification_screen.dart';
import '../features/account/presentation/broker_verification_admin_screen.dart';
import '../features/account/presentation/forgot_password_screen.dart';
import '../features/account/presentation/phone_verification_screen.dart';
import '../features/account/presentation/profile_screen.dart';
import '../features/admin/presentation/admin_dashboard_screen.dart';
import '../features/admin/presentation/audit_log_screen.dart';
import '../features/admin/presentation/platform_settings_screen.dart';
import '../features/app_shell/presentation/app_shell_screen.dart';
import '../features/chats/presentation/chats_screen.dart';
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
        builder: (context, state) => Stage6AuthGate(
          child: ConversationScreen(
              threadId: int.parse(state.pathParameters['id']!)),
        ),
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
        builder: (context, state) => const Stage6AuthGate(
          child: SupportCenterScreen(),
        ),
      ),
      GoRoute(
        path: '/admin/support',
        builder: (context, state) => Stage6AuthGate(
          child: SupportAdminScreen(
              initialKind: state.uri.queryParameters['kind']),
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
        builder: (context, state) => PropertyDetailsScreen(
          propertyId: int.parse(state.pathParameters['id']!),
        ),
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
      GoRoute(
        path: '/chats/:id',
        builder: (context, state) => ChatConversationScreen(
          threadId: state.pathParameters['id'] ?? 'chat',
        ),
      ),
    ],
  );
});

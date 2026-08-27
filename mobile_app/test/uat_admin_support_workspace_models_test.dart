import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/admin/domain/admin_workspace_models.dart';
import 'package:real_estate_mobile/features/support/domain/support_models.dart';

void main() {
  test('admin dashboard and support dashboard models parse current contract',
      () {
    final admin = AdminDashboardSummary.fromJson({
      'users': {'total': 14, 'active': 11},
      'listings': {'pending_review': 3, 'published': 25},
      'support': {'open': 4, 'reports_open': 2, 'overdue': 1},
      'bookings': {'requested': 2, 'active': 5},
      'broker_kyc_pending': 1,
      'payments_pending': 2,
      'alerts': [
        {
          'key': 'listing_review',
          'label': 'إعلانات تنتظر المراجعة',
          'count': 3,
          'route': '/admin/listing-review'
        },
      ],
    });
    expect(admin.usersTotal, 14);
    expect(admin.pendingListings, 3);
    expect(admin.alerts.single.route, '/admin/listing-review');

    final support = SupportAdminSummary.fromJson({
      'new_tickets': 2,
      'assigned_to_me': 1,
      'open': 4,
      'in_progress': 2,
      'waiting_requester': 1,
      'escalated': 1,
      'overdue_unescalated': 1,
      'new_reports': 3,
      'sla_warning': 2,
      'team': [
        {
          'id': 7,
          'name': 'موظف دعم',
          'roles': ['support_agent'],
          'assigned_active': 2,
          'actions_7d': 8
        },
      ],
    });
    expect(support.newReports, 3);
    expect(support.slaWarning, 2);
    expect(support.team.single.actions7d, 8);
  });

  test('workspace visibility is permission driven', () {
    final user = AuthUser(
      id: 10,
      name: 'موظف دعم تجريبي',
      email: 'support@example.test',
      phone: '+967700000000',
      accountType: 'regular',
      accountStatus: 'active',
      phoneVerifiedAt: DateTime(2026, 8, 25),
      brokerVerificationStatus: 'not_required',
      brokerVerificationSubmittedAt: null,
      brokerVerifiedAt: null,
      brokerVerificationNote: null,
      isPlatformOwner: false,
      roles: const ['support_agent'],
      permissions: const [
        'users.view',
        'support.handle_reports',
        'support.view_worklog'
      ],
    );
    expect(user.canAccessSupportWorkspace, isTrue);
    expect(user.canAccessSystemWorkspace, isFalse);
    expect(user.hasPermission('users.manage_roles'), isFalse);
    expect(user.hasPermission('conversations.review_private'), isFalse);
  });

  test('retired main broker region workflow is absent from active review UI',
      () async {
    final reviewSource = await File(
            'lib/features/reviews/presentation/listing_review_screen.dart')
        .readAsString();
    final regionSource = await File(
            'lib/features/regions/presentation/regions_management_screen.dart')
        .readAsString();
    final routes =
        await File('../backend-api-runtime/routes/api.php').readAsString();
    expect(reviewSource.contains('الدلال الرئيسي'), isFalse);
    expect(reviewSource.contains('brokerVerification'), isFalse);
    expect(regionSource.contains('لا يتم تعيين دلال لمنطقة أو مربع'), isTrue);
    expect(routes.contains('/cells/{cell}/broker'), isFalse);
    expect(routes.contains('broker-verification/request'), isFalse);
  });
}

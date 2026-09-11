import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_app/features/support/domain/support_workspace_models.dart';

void main() {
  test('support task parses team and escalation context', () {
    final task = SupportTaskItem.fromJson({
      'id': 7,
      'source_type': 'support_ticket',
      'source_id': 4,
      'subject': 'طلب دعم',
      'status': 'escalated',
      'priority': 'urgent',
      'support_team_id': 2,
      'support_team_name': 'دعم صنعاء',
      'governorate_id': 1,
      'governorate_name': 'صنعاء',
      'is_mine': true,
      'can_claim': false,
      'is_overdue': false,
      'escalation_reason': 'حالة غير اعتيادية',
    });
    expect(task.supportTeamName, 'دعم صنعاء');
    expect(task.governorateName, 'صنعاء');
    expect(task.escalationReason, 'حالة غير اعتيادية');
  });

  test('support team member parses capacity and workload', () {
    final member = SupportTeamMember.fromJson({
      'id': 6,
      'name': 'موظف دعم',
      'role': 'support_agent',
      'open_tasks': 4,
      'closed_tasks': 10,
      'overdue_tasks': 1,
      'urgent_tasks': 1,
      'tickets': 3,
      'verifications': 2,
      'listing_reviews': 5,
      'reports': 1,
      'is_available': true,
      'capacity': 8,
      'completed_today': 3,
      'workload_percent': 50,
      'team_id': 1,
      'team_name': 'فريق الدعم العام',
    });
    expect(member.capacity, 8);
    expect(member.workloadPercent, 50);
    expect(member.isAvailable, isTrue);
  });
}

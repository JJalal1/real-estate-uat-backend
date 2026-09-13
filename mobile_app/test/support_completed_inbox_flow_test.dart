import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/support/domain/support_workspace_models.dart';

void main() {
  test('completed task keeps resolution metadata', () {
    final item = SupportTaskItem.fromJson({
      'id': 1,
      'source_type': 'listing_review',
      'source_id': 2,
      'subject': 'تحقق نشر إعلان',
      'status': 'completed',
      'priority': 'normal',
      'is_mine': true,
      'can_claim': false,
      'is_overdue': false,
      'assigned_to_user_id': 7,
      'assigned_to_name': 'موظف الدعم',
      'metadata': {
        'resolution': 'returned_for_correction',
        'review_status': 'returned_for_correction',
      },
    });
    expect(item.isClosed, isTrue);
    expect(item.metadata['resolution'], 'returned_for_correction');
    expect(item.assignedToUserId, 7);
  });
}

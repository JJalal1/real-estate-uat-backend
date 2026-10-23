import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/bookings/domain/booking_models.dart';

void main() {
  test('Stage 13 booking model parses confirmed listing booking', () {
    final booking = ViewingBooking.fromJson({
      'id': 13,
      'reference': 'VABC123',
      'requester_user_id': 2,
      'requester_name': 'Requester',
      'host_user_id': 1,
      'host_name': 'Owner',
      'message_thread_id': 91,
      'target_type': 'property',
      'target_id': 7,
      'target_title': 'Apartment',
      'target_address': 'Sanaa',
      'starts_at': '2026-08-25T10:00:00Z',
      'ends_at': '2026-08-25T11:00:00Z',
      'timezone': 'UTC',
      'status': 'confirmed',
      'is_requester': true,
      'can_manage': false,
      'can_cancel': true,
      'can_reschedule': true,
    });
    expect(booking.id, 13);
    expect(booking.messageThreadId, 91);
    expect(booking.statusLabel, 'مؤكد');
    expect(booking.targetLabel, 'عقار');
    expect(booking.isActive, isTrue);
  });

  test('Stage 13 booking model labels development units and terminal states',
      () {
    final booking = ViewingBooking.fromJson({
      'id': 14,
      'reference': 'VXYZ789',
      'requester_user_id': 2,
      'requester_name': 'Requester',
      'target_type': 'development_unit',
      'target_id': 8,
      'target_title': 'Unit A',
      'starts_at': '2026-08-26T10:00:00Z',
      'ends_at': '2026-08-26T11:00:00Z',
      'status': 'cancelled',
      'is_requester': false,
      'can_manage': true,
      'can_cancel': false,
      'can_reschedule': false,
    });
    expect(booking.targetLabel, 'وحدة مشروع');
    expect(booking.statusLabel, 'ملغي');
    expect(booking.isActive, isFalse);
  });
}

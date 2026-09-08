import 'message_models.dart';

const _viewingNotificationTypes = <String>{
  'viewing_requested',
  'booking_confirmed',
  'booking_declined',
  'booking_cancelled',
  'booking_rescheduled',
  'booking_completed',
  'booking_reschedule_accepted',
};

String? notificationDestination(AppNotificationItem item) {
  final bookingId = item.bookingId ??
      (item.entityType == 'viewing_booking' ? item.entityId : null);
  if (bookingId != null && _viewingNotificationTypes.contains(item.type)) {
    return '/bookings?booking=$bookingId';
  }

  final threadId = item.messageThreadId ??
      (item.entityType == 'message_thread' ? item.entityId : null);
  if (threadId != null) {
    return '/messages/$threadId';
  }

  if (bookingId != null) {
    return '/bookings?booking=$bookingId';
  }
  if (item.entityType == 'account_verification_profile' ||
      item.entityType == 'account_verification') {
    return '/account-verification';
  }
  if (item.entityType == 'support_case' && item.entityId != null) {
    return '/support?case=${item.entityId}';
  }
  if (item.entityType == 'support_task') {
    return '/support/workspace';
  }
  if (item.entityType == 'property' && item.entityId != null) {
    return '/properties/${item.entityId}';
  }
  if (item.entityType == 'service_order') {
    return '/services';
  }
  return null;
}

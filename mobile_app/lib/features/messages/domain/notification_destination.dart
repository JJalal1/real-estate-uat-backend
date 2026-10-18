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
  if (item.entityType == 'broker_deal_outcome' && item.entityId != null) return '/broker/deals/${item.entityId}';
  if (item.type == 'broker_availability_due') return '/broker/availability?due=1';
  if (item.entityType == 'property_platform_receivable') return '/broker/finance';
  final agreementId = item.agreementId ??
      (item.entityType == 'property_agreement' ? item.entityId : null);
  if (agreementId != null &&
      (item.type.startsWith('agreement_') ||
          item.entityType == 'property_agreement')) {
    return '/agreements/$agreementId';
  }

  final contractId = item.rentalContractId ??
      (item.entityType == 'rental_contract' ? item.entityId : null);
  if (contractId != null &&
      (item.type.startsWith('rental_contract_') ||
          item.entityType == 'rental_contract')) {
    return '/rental-contracts/$contractId';
  }

  final retiredViewing = item.entityType == 'viewing_booking' || _viewingNotificationTypes.contains(item.type);
  final threadId = item.messageThreadId ??
      (item.entityType == 'message_thread' ? item.entityId : null);
  if (threadId != null) {
    return '/messages/$threadId';
  }

  if (agreementId != null) {
    return '/agreements/$agreementId';
  }
  if (contractId != null) {
    return '/rental-contracts/$contractId';
  }
  if (retiredViewing) return '/messages';
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

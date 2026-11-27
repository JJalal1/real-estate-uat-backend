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
  if (item.type == 'listing_duplicate_rejected') {
    final previousPropertyId = item.previousPropertyId;
    return previousPropertyId == null ? null : '/properties/$previousPropertyId';
  }
  if (item.entityType == 'broker_deal_outcome' && item.entityId != null) return '/broker/deals/${item.entityId}';
  if (item.type == 'broker_availability_due') return '/broker/availability?due=1';
  if (item.entityType == 'property_platform_receivable') return '/broker/finance';
  if (item.entityType == 'support_task') {
    final taskId = item.entityId ?? item.supportTaskId;
    return taskId != null && taskId > 0
        ? '/support/workspace/tasks/$taskId'
        : '/support/workspace';
  }
  final agreementId = item.agreementId ??
      (item.entityType == 'property_agreement' ? item.entityId : null);
  final contractId = item.rentalContractId ??
      (item.entityType == 'rental_contract' ? item.entityId : null);
  final retiredViewing = item.entityType == 'viewing_booking' || _viewingNotificationTypes.contains(item.type);
  final threadId = item.messageThreadId ??
      (item.entityType == 'message_thread' ? item.entityId : null);
  if (threadId != null && threadId > 0) return '/messages/$threadId';

  // An old notice can lack its conversation. A named transaction can still be
  // opened by its parties without restoring the retired catalog.
  if (contractId != null && contractId > 0 &&
      (item.type.startsWith('rental_contract_') || item.entityType == 'rental_contract')) {
    return '/rental-contracts/$contractId';
  }
  if (agreementId != null && agreementId > 0) {
    return '/agreements/$agreementId';
  }
  if (contractId != null && contractId > 0) {
    return '/rental-contracts/$contractId';
  }
  if (retiredViewing || item.type.startsWith('agreement_') ||
      item.type.startsWith('rental_contract_') ||
      const {'property_agreement', 'rental_contract'}.contains(item.entityType)) {
    return '/messages';
  }
  if (item.entityType == 'account_verification_profile' ||
      item.entityType == 'account_verification') {
    return '/profile';
  }
  if (item.entityType == 'support_case' && item.entityId != null) {
    return '/support?case=${item.entityId}';
  }
  if (item.entityType == 'property' && item.entityId != null) {
    return '/properties/${item.entityId}';
  }
  if (item.type.startsWith('saved_search_')) {
    final propertyId = int.tryParse(item.data['property_id']?.toString() ?? '');
    return propertyId != null && propertyId > 0 ? '/properties/$propertyId' : '/marketplace-search';
  }
  if (item.entityType == 'service_order') {
    return '/services';
  }
  return null;
}

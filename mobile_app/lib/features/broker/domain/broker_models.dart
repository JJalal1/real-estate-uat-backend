int brokerInt(dynamic value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;
double brokerNumber(dynamic value) => value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
Map<String, dynamic> brokerMap(dynamic value) => value is Map ? Map<String, dynamic>.from(value) : const {};
List<Map<String, dynamic>> brokerRows(dynamic value) => value is List ? value.whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList() : const [];

class BrokerProfile {
  const BrokerProfile({required this.id, required this.name, required this.type, required this.verified,
    required this.rating, required this.ratingCount, required this.completedDeals, required this.activeListings,
    this.governorate, this.bio, this.photoUrl, this.joinedAt, this.soldListings=0, this.rentedListings=0, this.officeName});
  final int id;
  final String name, type;
  final bool verified;
  final double rating;
  final int ratingCount, completedDeals, activeListings, soldListings, rentedListings;
  final String? governorate, bio, photoUrl, joinedAt;
  final String? officeName;
  String get typeLabel => type == 'office' ? 'مكتب عقاري' : type == 'owner' ? 'مالك' : type == 'broker' ? 'دلال' : 'معلن';
  factory BrokerProfile.fromJson(Map<String, dynamic> j) => BrokerProfile(id: brokerInt(j['id']), name: '${j['name'] ?? 'معلن'}',
    type: '${j['account_type'] ?? 'individual'}', verified: j['verified'] == true, rating: brokerNumber(j['rating_average']),
    soldListings:brokerInt(j['sold_listings']),rentedListings:brokerInt(j['rented_listings']),
    ratingCount: brokerInt(j['rating_count']), completedDeals: brokerInt(j['completed_deals']), activeListings: brokerInt(j['active_listings']),
    governorate: j['governorate']?.toString(), bio: j['bio']?.toString(), photoUrl: j['photo_url']?.toString(), joinedAt: j['joined_at']?.toString(),
    officeName: j['office_name']?.toString());
}

class BrokerDeal {
  const BrokerDeal({required this.id, required this.threadId, required this.propertyId, required this.advertiserId,
    required this.propertyTitle, required this.customerName, required this.advertiserName, required this.status,
    required this.amount, required this.currency, required this.canConfirm, required this.canRate, this.canViewSupportCase = false, this.supportCaseId,
    this.advertiserViewRevision, this.listingPrice, this.listingCurrency, this.saiAmount, this.saiCurrency,
    this.saiRatePercent, this.saiPaymentStatus, this.confirmedAt, this.platformDueStatus, this.transactionType,
    this.priceConfirmationRequired = false});
  final int id, threadId, propertyId, advertiserId;
  final String propertyTitle, customerName, advertiserName, status, currency;
  final double amount;
  final double? listingPrice, saiAmount, saiRatePercent;
  final String? listingCurrency, saiCurrency, saiPaymentStatus, platformDueStatus, transactionType;
  final DateTime? confirmedAt;
  final bool canConfirm, canRate, priceConfirmationRequired;
  final bool canViewSupportCase;
  final int? supportCaseId;
  final int? advertiserViewRevision;
  String otherPartyName(int? viewerId) => viewerId == advertiserId ? customerName : advertiserName;
  String get resultActionLabel => switch ((canConfirm, priceConfirmationRequired)) {
    (true, true) => 'تأكيد مبلغ الصفقة',
    (true, false) => 'تأكيد نتيجة الصفقة',
    _ => 'عرض نتيجة الصفقة',
  };
  String get statusLabel => switch ((status, platformDueStatus)) {
    ('confirmed', 'pending_payment') => 'بانتظار سداد مستحق المنصة',
    ('confirmed', 'pending_review') => 'إثبات السداد قيد التحقق',
    ('confirmed', _) => 'صفقة مؤكدة',
    ('disputed', _) => 'تحتاج مراجعة',
    ('cancelled', _) => 'ملغاة',
    _ => priceConfirmationRequired ? 'بانتظار تأكيد المبلغ' : 'بانتظار تأكيد العميل',
  };
  factory BrokerDeal.fromJson(Map<String, dynamic> j) => BrokerDeal(id: brokerInt(j['id']), threadId: brokerInt(j['thread_id']),
    propertyId: brokerInt(j['property_id']), advertiserId: brokerInt(j['advertiser_id']), propertyTitle: '${j['property_title'] ?? 'العقار'}',
    customerName: '${j['customer_name'] ?? 'العميل'}', advertiserName: '${j['advertiser_name'] ?? 'المعلن'}', status: '${j['status'] ?? 'pending_customer'}',
    amount: brokerNumber(j['basis_amount']), currency: '${j['currency'] ?? 'YER'}', canConfirm: j['can_confirm'] == true,
    canRate: j['can_rate'] == true, canViewSupportCase: j['can_view_support_case'] == true, supportCaseId: j['support_case_id'] == null ? null : brokerInt(j['support_case_id']),
    advertiserViewRevision: int.tryParse('${j['advertiser_view_revision'] ?? ''}'),
    listingPrice: _recordedNumber(j['listing_price']), listingCurrency: j['listing_currency']?.toString(),
    saiAmount: _recordedNumber(j['sai_amount']), saiCurrency: j['sai_currency']?.toString(),
    saiRatePercent: _recordedNumber(j['sai_rate_percent']), saiPaymentStatus: j['sai_payment_status']?.toString(),
    platformDueStatus: j['platform_due_status']?.toString(), transactionType: j['transaction_type']?.toString(),
    priceConfirmationRequired: j['price_confirmation_required'] == true,
    confirmedAt: DateTime.tryParse('${j['confirmed_at'] ?? ''}'));

  static double? _recordedNumber(dynamic value) {
    final number = double.tryParse('$value');
    return number?.isFinite == true ? number : null;
  }
}

const brokerEditableLeadLabels = {
  'appointment_set': 'تم تحديد موعد',
  'not_interested': 'غير مهتم',
  'reserved': 'تم حجز القطع',
};
const brokerLeadLabels = {...brokerEditableLeadLabels, 'completed': 'تمت الصفقة'};

class BrokerCustomer {
  const BrokerCustomer({required this.threadId, required this.customerName, required this.propertyId, required this.propertyTitle, required this.stage, this.deal,
    this.unreadCount = 0, this.privateNote = '', this.remindAt, this.followupDue = false,
    this.lastMessageAt, this.lastMessagePreview, this.lastMessageIsMine = false});
  final int threadId, propertyId;
  final String customerName, propertyTitle, stage;
  final BrokerDeal? deal;
  final int unreadCount;
  final String privateNote;
  final DateTime? remindAt;
  final DateTime? lastMessageAt;
  final String? lastMessagePreview;
  final bool lastMessageIsMine;
  final bool followupDue;
  String get followupStage => deal?.status == 'confirmed' ? 'completed' : stage;
  String? get stageLabel => brokerLeadLabels[followupStage];
  factory BrokerCustomer.fromJson(Map<String, dynamic> j) => BrokerCustomer(threadId: brokerInt(j['thread_id']), customerName: '${j['customer_name'] ?? 'العميل'}',
    propertyId: brokerInt(j['property_id']), propertyTitle: '${j['property_title'] ?? 'العقار'}', stage: '${j['stage'] ?? 'new'}',
    deal: j['deal'] is Map ? BrokerDeal.fromJson(brokerMap(j['deal'])) : null,
    unreadCount: brokerInt(j['unread_count']), privateNote: '${brokerMap(j['followup'])['private_note'] ?? ''}',
    remindAt: DateTime.tryParse('${brokerMap(j['followup'])['remind_at'] ?? ''}'), followupDue: brokerMap(j['followup'])['is_due'] == true,
    lastMessageAt: DateTime.tryParse('${j['last_message_at'] ?? ''}'),
    lastMessagePreview: j['last_message_preview'] as String?,
    lastMessageIsMine: j['last_message_is_mine'] == true);
}

class BrokerAvailability {
  const BrokerAvailability({required this.id, required this.title, required this.purpose, required this.status, required this.needsConfirmation, this.confirmedAt, this.dueAt});
  final int id;
  final String title, purpose, status;
  final bool needsConfirmation;
  final DateTime? confirmedAt, dueAt;
  factory BrokerAvailability.fromJson(Map<String, dynamic> j) => BrokerAvailability(id: brokerInt(j['id']), title: '${j['title'] ?? 'العقار'}',
    purpose: '${j['purpose'] ?? 'sale'}', status: '${j['availability_status'] ?? 'available'}', needsConfirmation: j['needs_confirmation'] == true,
    confirmedAt: DateTime.tryParse('${j['confirmed_at'] ?? ''}'), dueAt: DateTime.tryParse('${j['due_at'] ?? ''}'));
  String get label => switch (status) {'confirmation_paused' => 'يحتاج تحديثًا', 'paused' => 'متوقف مؤقتًا',
    'sold' => 'تم البيع', 'rented' => 'تم التأجير', _ => needsConfirmation ? 'يحتاج تحديثًا' : 'متوفر'};
}

class BrokerPage<T> {
  const BrokerPage({required this.items, required this.page, required this.lastPage,
    this.customerStageClassificationV2 = false});
  final List<T> items;
  final int page, lastPage;
  final bool customerStageClassificationV2;
  bool get hasMore => page < lastPage;
}

int brokerInt(dynamic value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;
double brokerNumber(dynamic value) => value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
Map<String, dynamic> brokerMap(dynamic value) => value is Map ? Map<String, dynamic>.from(value) : const {};
List<Map<String, dynamic>> brokerRows(dynamic value) => value is List ? value.whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList() : const [];

class BrokerProfile {
  const BrokerProfile({required this.id, required this.name, required this.type, required this.verified,
    required this.rating, required this.ratingCount, required this.completedDeals, required this.activeListings,
    this.governorate, this.bio, this.photoUrl, this.joinedAt, this.workAreas = const [], this.specializations = const []});
  final int id;
  final String name, type;
  final bool verified;
  final double rating;
  final int ratingCount, completedDeals, activeListings;
  final String? governorate, bio, photoUrl, joinedAt;
  final List<String> workAreas, specializations;
  String get typeLabel => type == 'office' ? 'مكتب عقاري' : type == 'owner' ? 'مالك' : 'دلال';
  factory BrokerProfile.fromJson(Map<String, dynamic> j) => BrokerProfile(id: brokerInt(j['id']), name: '${j['name'] ?? 'معلن'}',
    type: '${j['account_type'] ?? 'broker'}', verified: j['verified'] == true, rating: brokerNumber(j['rating_average']),
    ratingCount: brokerInt(j['rating_count']), completedDeals: brokerInt(j['completed_deals']), activeListings: brokerInt(j['active_listings']),
    governorate: j['governorate']?.toString(), bio: j['bio']?.toString(), photoUrl: j['photo_url']?.toString(), joinedAt: j['joined_at']?.toString(),
    workAreas: (j['work_areas'] as List? ?? const []).map((v) => '$v').toList(),
    specializations: (j['specializations'] as List? ?? const []).map((v) => '$v').toList());
}

class BrokerDeal {
  const BrokerDeal({required this.id, required this.threadId, required this.propertyId, required this.advertiserId,
    required this.propertyTitle, required this.customerName, required this.advertiserName, required this.status,
    required this.amount, required this.currency, required this.canConfirm, required this.canRate, this.canViewSupportCase = false, this.supportCaseId});
  final int id, threadId, propertyId, advertiserId;
  final String propertyTitle, customerName, advertiserName, status, currency;
  final double amount;
  final bool canConfirm, canRate;
  final bool canViewSupportCase;
  final int? supportCaseId;
  String get statusLabel => switch (status) {'confirmed' => 'صفقة مؤكدة', 'disputed' => 'تحتاج مراجعة', 'cancelled' => 'ملغاة', _ => 'بانتظار تأكيد العميل'};
  factory BrokerDeal.fromJson(Map<String, dynamic> j) => BrokerDeal(id: brokerInt(j['id']), threadId: brokerInt(j['thread_id']),
    propertyId: brokerInt(j['property_id']), advertiserId: brokerInt(j['advertiser_id']), propertyTitle: '${j['property_title'] ?? 'العقار'}',
    customerName: '${j['customer_name'] ?? 'العميل'}', advertiserName: '${j['advertiser_name'] ?? 'المعلن'}', status: '${j['status'] ?? 'pending_customer'}',
    amount: brokerNumber(j['basis_amount']), currency: '${j['currency'] ?? 'YER'}', canConfirm: j['can_confirm'] == true,
    canRate: j['can_rate'] == true, canViewSupportCase: j['can_view_support_case'] == true, supportCaseId: j['support_case_id'] == null ? null : brokerInt(j['support_case_id']));
}

const brokerLeadLabels = {'new': 'عميل جديد', 'contacted': 'تم التواصل', 'viewing': 'طلب معاينة', 'not_interested': 'غير مهتم', 'completed': 'تمت الصفقة'};
class BrokerCustomer {
  const BrokerCustomer({required this.threadId, required this.customerName, required this.propertyId, required this.propertyTitle, required this.stage, this.deal});
  final int threadId, propertyId;
  final String customerName, propertyTitle, stage;
  final BrokerDeal? deal;
  String get stageLabel => brokerLeadLabels[stage] ?? 'عميل جديد';
  factory BrokerCustomer.fromJson(Map<String, dynamic> j) => BrokerCustomer(threadId: brokerInt(j['thread_id']), customerName: '${j['customer_name'] ?? 'العميل'}',
    propertyId: brokerInt(j['property_id']), propertyTitle: '${j['property_title'] ?? 'العقار'}', stage: '${j['stage'] ?? 'new'}',
    deal: j['deal'] is Map ? BrokerDeal.fromJson(brokerMap(j['deal'])) : null);
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
  String get label => switch (status) {'confirmation_paused' => 'متوقف مؤقتًا حتى تأكيد التوفر', 'paused' => 'متوقف مؤقتًا',
    'sold' => 'تم البيع', 'rented' => 'تم التأجير', _ => needsConfirmation ? 'يحتاج تأكيد التوفر' : 'متوفر'};
}

class BrokerPage<T> {
  const BrokerPage({required this.items, required this.page, required this.lastPage});
  final List<T> items;
  final int page, lastPage;
  bool get hasMore => page < lastPage;
}

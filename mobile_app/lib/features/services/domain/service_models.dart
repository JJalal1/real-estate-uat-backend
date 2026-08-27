class ServiceOfferingModel {
  const ServiceOfferingModel(
      {required this.id,
      required this.code,
      required this.name,
      required this.description,
      required this.targetType,
      required this.durationDays,
      required this.priceAmount,
      required this.currency,
      required this.isActive});
  factory ServiceOfferingModel.fromJson(Map<String, dynamic> json) =>
      ServiceOfferingModel(
        id: _int(json['id']),
        code: json['code']?.toString() ?? '',
        name: json['name_ar']?.toString() ?? json['name_en']?.toString() ?? '',
        description: json['description_ar']?.toString(),
        targetType: json['target_type']?.toString() ?? 'account',
        durationDays: _nullableInt(json['duration_days']),
        priceAmount: json['price_amount']?.toString() ?? '0.00',
        currency: json['currency']?.toString() ?? 'YER',
        isActive: json['is_active'] == true,
      );
  final int id;
  final String code;
  final String name;
  final String? description;
  final String targetType;
  final int? durationDays;
  final String priceAmount;
  final String currency;
  final bool isActive;
  String get targetLabel => targetType == 'property' ? 'إعلان' : 'الحساب';
}

class ServiceOrderModel {
  const ServiceOrderModel(
      {required this.id,
      required this.reference,
      required this.serviceName,
      required this.targetType,
      required this.targetTitle,
      required this.amount,
      required this.currency,
      required this.status,
      required this.paymentProvider,
      required this.paymentReference,
      required this.canCancel,
      required this.canSettle,
      required this.canRefund});
  factory ServiceOrderModel.fromJson(Map<String, dynamic> json) =>
      ServiceOrderModel(
        id: _int(json['id']),
        reference: json['reference']?.toString() ?? '',
        serviceName: json['service_name']?.toString() ?? '',
        targetType: json['target_type']?.toString() ?? 'account',
        targetTitle: json['target_title']?.toString(),
        amount: json['amount']?.toString() ?? '0.00',
        currency: json['currency']?.toString() ?? 'YER',
        status: json['status']?.toString() ?? 'pending',
        paymentProvider: json['payment_provider']?.toString(),
        paymentReference: json['payment_reference']?.toString(),
        canCancel: json['can_cancel'] == true,
        canSettle: json['can_settle'] == true,
        canRefund: json['can_refund'] == true,
      );
  final int id;
  final String reference;
  final String serviceName;
  final String targetType;
  final String? targetTitle;
  final String amount;
  final String currency;
  final String status;
  final String? paymentProvider;
  final String? paymentReference;
  final bool canCancel;
  final bool canSettle;
  final bool canRefund;
  String get statusLabel => switch (status) {
        'paid' => 'مدفوع ومفعّل',
        'cancelled' => 'ملغي',
        'refunded' => 'مسترد',
        _ => 'بانتظار الدفع'
      };
}

class ServiceEntitlementModel {
  const ServiceEntitlementModel(
      {required this.id,
      required this.serviceName,
      required this.targetType,
      required this.targetTitle,
      required this.startsAt,
      required this.endsAt,
      required this.status,
      required this.isActive});
  factory ServiceEntitlementModel.fromJson(Map<String, dynamic> json) =>
      ServiceEntitlementModel(
        id: _int(json['id']),
        serviceName: json['service_name']?.toString() ?? '',
        targetType: json['target_type']?.toString() ?? 'account',
        targetTitle: json['target_title']?.toString(),
        startsAt: _date(json['starts_at']),
        endsAt: _nullableDate(json['ends_at']),
        status: json['status']?.toString() ?? 'active',
        isActive: json['is_active'] == true,
      );
  final int id;
  final String serviceName;
  final String targetType;
  final String? targetTitle;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String status;
  final bool isActive;
}

class ServiceTargetListing {
  const ServiceTargetListing(
      {required this.id,
      required this.title,
      required this.status,
      required this.reviewStatus});
  factory ServiceTargetListing.fromJson(Map<String, dynamic> json) =>
      ServiceTargetListing(
          id: _int(json['id']),
          title: json['title']?.toString() ?? 'إعلان',
          status: json['status']?.toString() ?? '',
          reviewStatus: json['review_status']?.toString() ?? '');
  final int id;
  final String title;
  final String status;
  final String reviewStatus;
  bool get eligible => status == 'published' && reviewStatus == 'approved';
}

int _int(Object? value) =>
    value is num ? value.toInt() : int.parse(value.toString());
int? _nullableInt(Object? value) => value == null ? null : _int(value);
DateTime _date(Object? value) => DateTime.parse(value.toString());
DateTime? _nullableDate(Object? value) => value == null ? null : _date(value);

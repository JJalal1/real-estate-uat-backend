class FinancialPaymentMethod {
  const FinancialPaymentMethod({
    required this.id,
    required this.key,
    required this.name,
    required this.beneficiaryName,
    required this.destinationLabel,
    required this.destinationValue,
    required this.currency,
    required this.available,
    this.instructions,
    this.assetKey,
    this.unavailableReason,
    this.requiresSenderPhone = false,
    this.requiresProviderReference = false,
  });

  final int id;
  final String key;
  final String name;
  final String beneficiaryName;
  final String destinationLabel;
  final String destinationValue;
  final String currency;
  final bool available;
  final String? instructions;
  final String? assetKey;
  final String? unavailableReason;
  final bool requiresSenderPhone;
  final bool requiresProviderReference;

  factory FinancialPaymentMethod.fromJson(Map<String, dynamic> json) =>
      FinancialPaymentMethod(
        id: _int(json['id']),
        key: '${json['key'] ?? ''}',
        name: '${json['name_ar'] ?? 'طريقة دفع'}',
        beneficiaryName: '${json['beneficiary_name'] ?? ''}',
        destinationLabel: '${json['destination_label'] ?? ''}',
        destinationValue: '${json['destination_value'] ?? ''}',
        currency: '${json['currency'] ?? 'YER'}',
        available: json['available'] != false && json['available'] != 0,
        instructions: _text(json['instructions_ar']),
        assetKey: _text(json['asset_key']),
        unavailableReason: _text(json['unavailable_reason']),
        requiresSenderPhone: json['requires_sender_phone'] == true ||
            json['requires_sender_phone'] == 1,
        requiresProviderReference:
            json['requires_provider_reference'] == true ||
                json['requires_provider_reference'] == 1,
      );
}

class FinancialPayment {
  const FinancialPayment({
    required this.id,
    required this.reference,
    required this.status,
    required this.amount,
    required this.currency,
    this.agreementId,
    this.propertyId,
    this.propertyTitle,
    this.mode,
    this.paymentMethod,
    this.providerReference,
    this.senderName,
    this.senderPhone,
    this.hasProof = false,
    this.proofUrl,
    this.reviewNote,
    this.createdAt,
    this.submittedAt,
    this.confirmedAt,
  });

  final int id;
  final String reference;
  final String status;
  final double amount;
  final String currency;
  final int? agreementId;
  final int? propertyId;
  final String? propertyTitle;
  final String? mode;
  final String? paymentMethod;
  final String? providerReference;
  final String? senderName;
  final String? senderPhone;
  final bool hasProof;
  final String? proofUrl;
  final String? reviewNote;
  final DateTime? createdAt;
  final DateTime? submittedAt;
  final DateTime? confirmedAt;

  String get statusLabel => switch (status) {
        'waiting_payment' => 'بانتظار الدفع',
        'proof_submitted' => 'تم رفع الإثبات',
        'under_review' => 'قيد التحقق',
        'correction_required' => 'يحتاج تصحيح',
        'confirmed' => 'تم التأكيد',
        'rejected' => 'مرفوض',
        'cancelled' => 'ملغي',
        _ => status,
      };

  factory FinancialPayment.fromJson(Map<String, dynamic> json) =>
      FinancialPayment(
        id: _int(json['id']),
        reference: '${json['reference'] ?? ''}',
        status: '${json['status'] ?? ''}',
        amount: _double(json['required_amount'] ?? json['amount']),
        currency: '${json['currency'] ?? 'YER'}',
        agreementId: _nullableInt(json['agreement_id']),
        propertyId: _nullableInt(json['property_id']),
        propertyTitle: _text(json['property_title']),
        mode: _text(json['mode']),
        paymentMethod: json['payment_method'] is Map
            ? _text((json['payment_method'] as Map)['name_ar'])
            : _text(json['payment_method']),
        providerReference: _text(json['provider_reference']),
        senderName: _text(json['sender_name']),
        senderPhone: _text(json['sender_phone']),
        hasProof: json['has_proof'] == true || json['has_proof'] == 1,
        proofUrl: _text(json['proof_url']),
        reviewNote: _text(json['review_note']),
        createdAt: _date(json['created_at']),
        submittedAt: _date(json['submitted_at']),
        confirmedAt: _date(json['confirmed_at']),
      );
}

class FinancialDeal {
  const FinancialDeal({
    required this.id,
    required this.agreementId,
    required this.propertyId,
    required this.propertyTitle,
    required this.transactionType,
    required this.currency,
    required this.baseAmount,
    required this.saiPayer,
    required this.saiTotalAmount,
    required this.canPayFull,
    required this.canPaySaiOnly,
    required this.requiredFullPayment,
    required this.requiredSaiPayment,
    required this.paymentMethods,
    required this.payments,
    this.monthlyRent,
    this.rentalTermMonths,
    this.advanceMonths,
    this.receivable,
  });

  final int id;
  final int agreementId;
  final int propertyId;
  final String propertyTitle;
  final String transactionType;
  final String currency;
  final double baseAmount;
  final double? monthlyRent;
  final int? rentalTermMonths;
  final int? advanceMonths;
  final String saiPayer;
  final double saiTotalAmount;
  final bool canPayFull;
  final bool canPaySaiOnly;
  final double requiredFullPayment;
  final double requiredSaiPayment;
  final List<FinancialPaymentMethod> paymentMethods;
  final List<FinancialPayment> payments;
  final Map<String, dynamic>? receivable;

  bool get isRent => transactionType == 'rent';

  factory FinancialDeal.fromJson(Map<String, dynamic> json) => FinancialDeal(
        id: _int(json['id']),
        agreementId: _int(json['agreement_id']),
        propertyId: _int(json['property_id']),
        propertyTitle: '${json['property_title'] ?? 'العقار'}',
        transactionType: '${json['transaction_type'] ?? ''}',
        currency: '${json['currency'] ?? 'YER'}',
        baseAmount: _double(json['base_amount']),
        monthlyRent: _nullableDouble(json['monthly_rent']),
        rentalTermMonths: _nullableInt(json['rental_term_months']),
        advanceMonths: _nullableInt(json['advance_months']),
        saiPayer: '${json['sai_payer'] ?? ''}',
        saiTotalAmount: _double(json['sai_total_amount']),
        canPayFull: json['can_pay_full'] == true,
        canPaySaiOnly: json['can_pay_sai_only'] == true,
        requiredFullPayment: _double(json['required_full_payment']),
        requiredSaiPayment: _double(json['required_sai_payment']),
        paymentMethods: _maps(json['payment_methods'])
            .map(FinancialPaymentMethod.fromJson)
            .toList(growable: false),
        payments: _maps(json['payments'])
            .map(FinancialPayment.fromJson)
            .toList(growable: false),
        receivable: json['receivable'] is Map<String, dynamic>
            ? json['receivable'] as Map<String, dynamic>
            : null,
      );
}

class FinancialAccountSummary {
  const FinancialAccountSummary({
    required this.openPlatformDue,
    required this.overduePlatformDue,
    required this.pendingPayouts,
    required this.paidPayouts,
    required this.listingCreationBlocked,
    required this.publishedListingsHidden,
  });

  final double openPlatformDue;
  final double overduePlatformDue;
  final double pendingPayouts;
  final double paidPayouts;
  final bool listingCreationBlocked;
  final bool publishedListingsHidden;

  factory FinancialAccountSummary.fromJson(Map<String, dynamic> json) =>
      FinancialAccountSummary(
        openPlatformDue: _double(json['open_platform_due']),
        overduePlatformDue: _double(json['overdue_platform_due']),
        pendingPayouts: _double(json['pending_payouts']),
        paidPayouts: _double(json['paid_payouts']),
        listingCreationBlocked: json['listing_creation_blocked'] == true,
        publishedListingsHidden: json['published_listings_hidden'] == true,
      );
}

List<Map<String, dynamic>> _maps(dynamic value) => value is List
    ? value.whereType<Map<String, dynamic>>().toList(growable: false)
    : const <Map<String, dynamic>>[];
int _int(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
int? _nullableInt(dynamic value) => value == null ? null : _int(value);
double _double(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
double? _nullableDouble(dynamic value) => value == null ? null : _double(value);
String? _text(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

DateTime? _date(dynamic value) =>
    value == null ? null : DateTime.tryParse('$value');

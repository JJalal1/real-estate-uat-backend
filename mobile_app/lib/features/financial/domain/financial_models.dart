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
    this.isEnabled = true,
    this.allowsFullPayment = true,
    this.allowsSaiOnly = true,
    this.minAmount,
    this.maxAmount,
    this.sortOrder = 0,
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
  final bool isEnabled;
  final bool allowsFullPayment;
  final bool allowsSaiOnly;
  final double? minAmount;
  final double? maxAmount;
  final int sortOrder;

  factory FinancialPaymentMethod.fromJson(Map<String, dynamic> json) =>
      FinancialPaymentMethod(
        id: _int(json['id']),
        key: '${json['key'] ?? ''}',
        name: '${json['name_ar'] ?? 'طريقة دفع'}',
        beneficiaryName: '${json['beneficiary_name'] ?? ''}',
        destinationLabel: '${json['destination_label'] ?? ''}',
        destinationValue: '${json['destination_value'] ?? ''}',
        currency: '${json['currency'] ?? 'YER'}',
        available: json.containsKey('available')
            ? json['available'] != false && json['available'] != 0
            : json['is_enabled'] != false && json['is_enabled'] != 0,
        instructions: _text(json['instructions_ar']),
        assetKey: _text(json['asset_key']),
        unavailableReason: _text(json['unavailable_reason']),
        requiresSenderPhone: _bool(json['requires_sender_phone']),
        requiresProviderReference: _bool(json['requires_provider_reference']),
        isEnabled: json['is_enabled'] == null ? true : _bool(json['is_enabled']),
        allowsFullPayment: json['allows_full_payment'] == null
            ? true
            : _bool(json['allows_full_payment']),
        allowsSaiOnly: json['allows_sai_only'] == null
            ? true
            : _bool(json['allows_sai_only']),
        minAmount: _nullableDouble(json['min_amount']),
        maxAmount: _nullableDouble(json['max_amount']),
        sortOrder: _int(json['sort_order']),
      );

  String? get localAssetPath {
    if (key == 'jeeb') return 'assets/payments/jeeb.png';
    if (key == 'kuraimi') return 'assets/payments/kuraimi.png';
    if (key == 'jawali') return 'assets/payments/jawali.png';
    if (assetKey?.startsWith('assets/payments/') == true) return assetKey;
    return null;
  }
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
    this.method,
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
  final FinancialPaymentMethod? method;
  final String? providerReference;
  final String? senderName;
  final String? senderPhone;
  final bool hasProof;
  final String? proofUrl;
  final String? reviewNote;
  final DateTime? createdAt;
  final DateTime? submittedAt;
  final DateTime? confirmedAt;

  String? get paymentMethod => method?.name;

  String get statusLabel => switch (status) {
        'waiting_payment' => 'بانتظار الدفع',
        'proof_submitted' => 'تم رفع الإثبات',
        'under_review' => 'قيد التحقق',
        'correction_required' => 'يحتاج تصحيح',
        'confirmed' => 'تم تأكيد الدفع ✅',
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
        method: json['payment_method'] is Map
            ? FinancialPaymentMethod.fromJson(
                Map<String, dynamic>.from(json['payment_method'] as Map))
            : null,
        providerReference: _text(json['provider_reference']),
        senderName: _text(json['sender_name']),
        senderPhone: _text(json['sender_phone']),
        hasProof: _bool(json['has_proof']),
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
        receivable: json['receivable'] is Map
            ? Map<String, dynamic>.from(json['receivable'] as Map)
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
        listingCreationBlocked: _bool(json['listing_creation_blocked']),
        publishedListingsHidden: _bool(json['published_listings_hidden']),
      );
}

class FinancialAdvertiserAccount {
  const FinancialAdvertiserAccount({
    required this.summary,
    required this.receivables,
    required this.payouts,
    required this.deals,
  });

  final FinancialAccountSummary summary;
  final List<Map<String, dynamic>> receivables;
  final List<Map<String, dynamic>> payouts;
  final List<Map<String, dynamic>> deals;

  factory FinancialAdvertiserAccount.fromJson(Map<String, dynamic> json) =>
      FinancialAdvertiserAccount(
        summary: FinancialAccountSummary.fromJson(
            Map<String, dynamic>.from(json['summary'] as Map? ?? const {})),
        receivables: _maps(json['receivables']),
        payouts: _maps(json['payouts']),
        deals: _maps(json['deals']),
      );
}

List<Map<String, dynamic>> _maps(dynamic value) => value is List
    ? value
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false)
    : const <Map<String, dynamic>>[];
int _int(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
int? _nullableInt(dynamic value) => value == null ? null : _int(value);
double _double(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
double? _nullableDouble(dynamic value) => value == null ? null : _double(value);
bool _bool(dynamic value) => value == true || value == 1 || value == '1';
String? _text(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

DateTime? _date(dynamic value) =>
    value == null ? null : DateTime.tryParse('$value');

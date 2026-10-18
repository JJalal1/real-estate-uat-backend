class PropertySai {
  const PropertySai({
    required this.ratePercent,
    required this.payer,
    required this.payerLabel,
    required this.calculationBasis,
    required this.displayText,
    this.amountType = 'percentage',
    this.fixedAmount,
    this.currency,
  });

  final double ratePercent;
  final String payer;
  final String payerLabel;
  final String calculationBasis;
  final String displayText;
  final String amountType;
  final double? fixedAmount;
  final String? currency;

  factory PropertySai.fromJson(Map<String, dynamic> json) {
    return PropertySai(
      ratePercent: _asDouble(json['rate_percent']),
      payer: json['payer']?.toString() ?? '',
      payerLabel: json['payer_label']?.toString() ?? '',
      calculationBasis: json['calculation_basis']?.toString() ?? '',
      displayText: json['display_text']?.toString() ?? '',
      amountType: json['amount_type']?.toString() ?? 'percentage',
      fixedAmount: _asDoubleOrNull(json['fixed_amount']),
      currency: _textOrNull(json['currency']),
    );
  }
}

class PropertySaiManagement {
  const PropertySaiManagement({
    required this.configured,
    required this.advertiserType,
    this.termId,
    this.version,
    this.purpose,
    this.sourceMode,
    this.requestedBrokerRatePercent,
    this.saiRatePercent,
    this.payer,
    this.payerLabel,
    this.calculationBasis,
    this.platformSharePercent,
    this.brokerSharePercent,
    this.platformTermsStatus,
    this.requiresPlatformTermsAcceptance = false,
    this.platformTermsMessage,
    this.publicDisplayText,
    this.fixedRatePercent,
    this.brokerMaxRatePercent,
    this.professionalPlatformSharePercent,
    this.fallbackPlatformSharePercent,
    this.amountType = 'percentage',
    this.fixedAmount,
    this.fixedCurrency,
  });

  final bool configured;
  final String advertiserType;
  final int? termId;
  final int? version;
  final String? purpose;
  final String? sourceMode;
  final double? requestedBrokerRatePercent;
  final double? saiRatePercent;
  final String? payer;
  final String? payerLabel;
  final String? calculationBasis;
  final double? platformSharePercent;
  final double? brokerSharePercent;
  final String? platformTermsStatus;
  final bool requiresPlatformTermsAcceptance;
  final String? platformTermsMessage;
  final String? publicDisplayText;
  final double? fixedRatePercent;
  final double? brokerMaxRatePercent;
  final double? professionalPlatformSharePercent, fallbackPlatformSharePercent;
  final String amountType;
  final double? fixedAmount;
  final String? fixedCurrency;

  bool get isOwner => advertiserType == 'owner';
  bool get isProfessional => advertiserType == 'broker' || advertiserType == 'office';

  factory PropertySaiManagement.fromJson(Map<String, dynamic> json) {
    return PropertySaiManagement(
      configured: json['configured'] == true,
      advertiserType: json['advertiser_type']?.toString() ?? 'owner',
      termId: _asIntOrNull(json['term_id']),
      version: _asIntOrNull(json['version']),
      purpose: _textOrNull(json['purpose']),
      sourceMode: _textOrNull(json['source_mode']),
      requestedBrokerRatePercent: _asDoubleOrNull(json['requested_broker_rate_percent']),
      saiRatePercent: _asDoubleOrNull(json['sai_rate_percent']),
      payer: _textOrNull(json['payer']),
      payerLabel: _textOrNull(json['payer_label']),
      calculationBasis: _textOrNull(json['calculation_basis']),
      platformSharePercent: _asDoubleOrNull(json['platform_share_percent']),
      brokerSharePercent: _asDoubleOrNull(json['broker_share_percent']),
      platformTermsStatus: _textOrNull(json['platform_terms_status']),
      requiresPlatformTermsAcceptance: json['requires_platform_terms_acceptance'] == true,
      platformTermsMessage: _textOrNull(json['platform_terms_message']),
      publicDisplayText: _textOrNull(json['public_display_text']),
      fixedRatePercent: _asDoubleOrNull(json['fixed_rate_percent']),
      brokerMaxRatePercent: _asDoubleOrNull(json['broker_max_rate_percent']),
      professionalPlatformSharePercent: _asDoubleOrNull(json['professional_platform_share_percent']),
      fallbackPlatformSharePercent: _asDoubleOrNull(json['fallback_platform_share_percent']),
      amountType: json['sai_amount_type']?.toString() ?? 'percentage',
      fixedAmount: _asDoubleOrNull(json['fixed_sai_amount']),
      fixedCurrency: _textOrNull(json['fixed_sai_currency']),
    );
  }
}

class PropertySaiEnvelope {
  const PropertySaiEnvelope({this.sai, this.management});

  final PropertySai? sai;
  final PropertySaiManagement? management;

  factory PropertySaiEnvelope.fromResponse(Map<String, dynamic>? response) {
    final data = response?['data'];
    if (data is! Map<String, dynamic>) return const PropertySaiEnvelope();
    final publicRaw = data['sai'];
    final managementRaw = data['sai_management'];
    return PropertySaiEnvelope(
      sai: publicRaw is Map<String, dynamic> ? PropertySai.fromJson(publicRaw) : null,
      management: managementRaw is Map<String, dynamic>
          ? PropertySaiManagement.fromJson(managementRaw)
          : null,
    );
  }
}

double _asDouble(dynamic value) => _asDoubleOrNull(value) ?? 0;

double? _asDoubleOrNull(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

int? _asIntOrNull(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

String? _textOrNull(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

/// Preview only: the immutable server term and confirmed final deal determine
/// settlement. The platform percentage comes exclusively from server policy.
class PropertySaiQuote {
  const PropertySaiQuote(this.rate, this.total, this.platform, this.net, this.fallback);
  final double rate, total, platform, net;
  final bool fallback;
  double get platformPercent => total == 0 ? 0 : platform * 100 / total;
  static PropertySaiQuote? calculate(PropertySaiManagement policy, double requestedRate, double basis, {double? fixedAmount}) {
    final fixed = fixedAmount != null && !policy.isOwner;
    final amount = fixedAmount ?? 0;
    if (!basis.isFinite || basis <= 0) return null;
    if (fixed ? !amount.isFinite || amount < 0 : !requestedRate.isFinite || requestedRate < 0 || requestedRate > 100) return null;
    final fallback = policy.isOwner || (fixed ? amount == 0 : requestedRate == 0);
    final rate = fallback ? policy.fixedRatePercent : requestedRate;
    final share = fallback ? policy.fallbackPlatformSharePercent : policy.professionalPlatformSharePercent;
    if (rate == null || share == null || share < 0 || share > 100) return null;
    if (!policy.isOwner && (policy.brokerMaxRatePercent == null ||
        (fixed ? amount > (basis * policy.brokerMaxRatePercent!).round() / 100
          : requestedRate > policy.brokerMaxRatePercent!))) {
      return null;
    }
    double money(double value) => (value * 100).round() / 100;
    final total = fixed && !fallback ? money(amount) : money(basis * rate / 100);
    final platform = money(total * share / 100);
    return PropertySaiQuote(rate, total, platform, money(total - platform), fallback);
  }
}

double? parseSaiNumber(String text) {
  var value = text.trim().replaceAll('٫', '.').replaceAll('٬', '').replaceAll(',', '');
  const arabic = '٠١٢٣٤٥٦٧٨٩', persian = '۰۱۲۳۴۵۶۷۸۹';
  for (var i = 0; i < 10; i++) {
    value = value.replaceAll(arabic[i], '$i').replaceAll(persian[i], '$i');
  }
  return double.tryParse(value);
}

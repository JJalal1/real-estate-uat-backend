import '../../../core/formatters/money.dart';

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

  /// Presentation only; the authoritative payer and financial contract remain intact.
  String get presentationText {
    if (amountType == 'fixed') {
      if (fixedAmount == null) return 'لم يُحدد مبلغ السعي';
      final value = currency?.isNotEmpty == true ? moneyLabel(fixedAmount!, currency!) : formatMoneyAmount(fixedAmount!);
      return 'السعي $value';
    }
    return 'السعي ${formatMoneyAmount(ratePercent)}٪';
  }

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
  bool get hasHistoricalFixedTerms => configured && isOwner;

  double? get effectiveFixedRate => hasHistoricalFixedTerms
      ? saiRatePercent ?? fixedRatePercent
      : fixedRatePercent;

  factory PropertySaiManagement.fromJson(Map<String, dynamic> json) {
    return PropertySaiManagement(
      configured: json['configured'] == true,
      advertiserType: json['advertiser_type']?.toString() ?? 'advertiser',
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
  const PropertySaiQuote(this.rate, this.total, this.platform, this.net, this.fallback, this.platformPercent);
  final double rate, total, platform, net;
  final bool fallback;
  final double platformPercent;
  static PropertySaiQuote? calculate(PropertySaiManagement policy, double requestedRate, double basis, {double? fixedAmount, bool keepConfiguredShare = false, String? purpose}) {
    final historicalFixed = policy.hasHistoricalFixedTerms;
    final fixed = fixedAmount != null && !historicalFixed;
    final amount = fixedAmount ?? 0;
    if (!basis.isFinite || basis <= 0) return null;
    if (fixed ? !amount.isFinite || amount < 0 : !requestedRate.isFinite || requestedRate < 0 || requestedRate > 100) return null;
    final fallback = historicalFixed || (fixed ? amount == 0 : requestedRate == 0);
    final rate = fallback ? policy.effectiveFixedRate : (fixed ? 0.0 : requestedRate);
    final policyShare = fallback ? policy.fallbackPlatformSharePercent : policy.professionalPlatformSharePercent;
    final share = historicalFixed || keepConfiguredShare ? policy.platformSharePercent ?? policyShare : policyShare;
    if (rate == null || !rate.isFinite || share == null || !share.isFinite || share < 0 || share > 100) return null;
    final listingPurpose = purpose ?? policy.purpose ?? 'sale';
    final validation = validatePropertySaiInput(purpose: listingPurpose, fixed: fixed,
        value: (fixed ? amount : rate).toString(), basis: basis,
        policyMaximumPercent: policy.brokerMaxRatePercent, zeroFallbackRate: policy.effectiveFixedRate);
    if (validation != null) return null;
    double money(double value) => (value * 100).round() / 100;
    final total = fixed && !fallback ? money(amount) : money(basis * rate / 100);
    final platform = money(total * share / 100);
    return PropertySaiQuote(rate, total, platform, money(total - platform), fallback, share);
  }
}

double? maximumPropertySaiPercent(String purpose, double? policyMaximumPercent) {
  final hardLimit = switch (purpose) {'sale' => 5.0, 'rent' => 100.0, _ => null};
  if (hardLimit == null) return null;
  if (policyMaximumPercent == null) return hardLimit;
  if (!policyMaximumPercent.isFinite || policyMaximumPercent < 0) return null;
  return policyMaximumPercent < hardLimit ? policyMaximumPercent : hardLimit;
}

// Keep the decimal value as supplied, including very small scientific notation.
// Multiplication in binary floating point can push a boundary below a whole cent.
(BigInt, int) _decimalParts(double value) {
  final exponentParts = value.toString().split('e');
  final decimalParts = exponentParts.first.split('.');
  final coefficient = BigInt.parse(decimalParts.join());
  final exponent = exponentParts.length == 2 ? int.parse(exponentParts.last) : 0;
  final scale = (decimalParts.length == 2 ? decimalParts.last.length : 0) - exponent;
  return (coefficient, scale);
}

double? maximumPropertySaiAmount(String purpose, double? basis, double? policyMaximumPercent) {
  final percent = maximumPropertySaiPercent(purpose, policyMaximumPercent);
  if (percent == null || basis == null || !basis.isFinite || basis <= 0) return null;
  final (priceDigits, priceScale) = _decimalParts(basis);
  final (rateDigits, rateScale) = _decimalParts(percent);
  // Maximum in cents = floor(price × percentage), since both factors of 100 cancel.
  final product = priceDigits * rateDigits;
  final scale = priceScale + rateScale;
  final ten = BigInt.from(10);
  final cents = scale < 0 ? product * ten.pow(-scale) : product ~/ ten.pow(scale);
  final storageLimitCents = BigInt.from(99999999999999);
  return (cents < storageLimitCents ? cents : storageLimitCents).toDouble() / 100;
}

final _saiDecimalInput = RegExp(r'^(?:(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{0,2})?|\.\d{1,2})$');

String? validatePropertySaiInput({
  required String purpose,
  required bool fixed,
  required String value,
  required double? basis,
  required double? policyMaximumPercent,
  String currency = 'YER',
  double? zeroFallbackRate,
}) {
  final maximum = maximumPropertySaiPercent(purpose, policyMaximumPercent);
  if (maximum == null) return 'تعذر تحديد حد السعي لهذا الإعلان.';
  final basisName = purpose == 'rent' ? 'إيجار الشهر الأول' : 'سعر البيع';
  if (basis == null || !basis.isFinite || basis <= 0) return 'أدخل $basisName لتحديد حد السعي.';
  final normalized = _normalizeSaiNumber(value);
  final number = double.tryParse(normalized.replaceAll(',', ''));
  if (!_saiDecimalInput.hasMatch(normalized) || number == null || !number.isFinite) {
    return fixed ? 'أدخل مبلغ سعي من 0 فأكثر وبمنزلتين عشريتين على الأكثر.'
        : 'أدخل نسبة سعي من 0 فأكثر وبمنزلتين عشريتين على الأكثر.';
  }
  final pct = formatMoneyAmount(maximum, englishDigits: true);
  if (number == 0 && zeroFallbackRate != null &&
      (!zeroFallbackRate.isFinite || zeroFallbackRate < 0 || zeroFallbackRate > maximum)) {
    return 'السعي الافتراضي خارج الحد المسموح. أقصى نسبة للسعي $pct% من $basisName.';
  }
  if (!fixed) return number > maximum ? 'أقصى نسبة للسعي $pct% من $basisName.' : null;
  final amountLimit = maximumPropertySaiAmount(purpose, basis, policyMaximumPercent)!;
  if (number <= amountLimit) return null;
  final amount = formatMoneyAmount(amountLimit, englishDigits: true);
  final label = '$amount ${currencyLabel(currency)}';
  return amountLimit == 999999999999.99
      ? 'أقصى مبلغ للسعي $label.'
      : 'أقصى مبلغ للسعي $label ($pct% من $basisName).';
}

String _normalizeSaiNumber(String text) {
  var value = text.trim().replaceAll('٫', '.').replaceAll('٬', ',');
  const arabic = '٠١٢٣٤٥٦٧٨٩', persian = '۰۱۲۳۴۵۶۷۸۹';
  for (var i = 0; i < 10; i++) {
    value = value.replaceAll(arabic[i], '$i').replaceAll(persian[i], '$i');
  }
  return value;
}

double? parseSaiNumber(String text) {
  final parsed = double.tryParse(_normalizeSaiNumber(text).replaceAll(',', ''));
  return parsed != null && parsed.isFinite ? parsed : null;
}

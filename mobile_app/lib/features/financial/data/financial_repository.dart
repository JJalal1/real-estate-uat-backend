import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../account/data/auth_repository.dart';
import '../../account/data/account_request_scope.dart';
import '../domain/financial_models.dart';

final financialRevisionProvider = StateProvider<int>((ref) => 0);

final financialRepositoryProvider = Provider<FinancialRepository>((ref) {
  return FinancialRepository(
      ref.watch(dioProvider), ref.watch(authRepositoryProvider),
      requestScope: ref.watch(accountRequestScopeProvider));
});

class FinancialRepository {
  FinancialRepository(this._dio, this._auth, {AccountRequestScope? requestScope})
    : _requestScope = requestScope;
  final Dio _dio;
  final AuthRepository _auth;
  final AccountRequestScope? _requestScope;
  Future<Options> _options() => _requestScope?.options() ?? _auth.requiredAuthOptions();

  Future<FinancialDeal> receivableDeal(int receivableId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/finance/receivables/$receivableId',
      options: await _options(),
    );
    return FinancialDeal.fromJson(_data(response.data));
  }

  Future<FinancialDeal> deal(int agreementId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/finance/agreements/$agreementId',
      options: await _options(),
    );
    return FinancialDeal.fromJson(_data(response.data));
  }

  Future<List<FinancialPayment>> paymentsMine() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/finance/payments/mine',
      options: await _options(),
    );
    return _list(response.data)
        .map(FinancialPayment.fromJson)
        .toList(growable: false);
  }

  Future<FinancialAdvertiserAccount> advertiserAccount() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/finance/account',
      options: await _options(),
    );
    return FinancialAdvertiserAccount.fromJson(_data(response.data));
  }

  Future<FinancialAccountSummary> account() async =>
      (await advertiserAccount()).summary;

  Future<Map<String, dynamic>> configureListing({
    required int propertyId,
    String? priceDisplayMode,
    double? monthlyRent,
    int? rentalTermMonths,
    int? advanceMonths,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/properties/$propertyId/financial-config',
      data: <String, dynamic>{
        'price_display_mode': priceDisplayMode,
        if (monthlyRent != null) 'monthly_rent': monthlyRent,
        if (rentalTermMonths != null) 'rental_term_months': rentalTermMonths,
        if (advanceMonths != null) 'advance_months': advanceMonths,
      },
      options: await _options(),
    );
    return _data(response.data);
  }

  Future<List<Map<String, dynamic>>> pendingSaiAttestations() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/finance/sai-attestations/pending',
      options: await _options(),
    );
    return _list(response.data);
  }

  Future<FinancialPayment> createPayment({
    required int agreementId,
    required String mode,
    required int paymentMethodId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/finance/agreements/$agreementId/payments',
      data: {'mode': mode, 'payment_method_id': paymentMethodId},
      options: await _options(),
    );
    _bump();
    return FinancialPayment.fromJson(_data(response.data));
  }

  Future<FinancialPayment> createReceivablePayment({
    required int receivableId,
    required int paymentMethodId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/finance/receivables/$receivableId/payments',
      data: {'payment_method_id': paymentMethodId},
      options: await _options(),
    );
    _bump();
    return FinancialPayment.fromJson(_data(response.data));
  }

  Future<FinancialPayment> submitProof({
    required int paymentId,
    required String imagePath,
    String? senderName,
    String? senderPhone,
    String? providerReference,
  }) async {
    final form = FormData.fromMap({
      'proof': await MultipartFile.fromFile(imagePath),
      if (senderName?.trim().isNotEmpty == true)
        'sender_name': senderName!.trim(),
      if (senderPhone?.trim().isNotEmpty == true)
        'sender_phone': senderPhone!.trim(),
      if (providerReference?.trim().isNotEmpty == true)
        'provider_reference': providerReference!.trim(),
    });
    final response = await _dio.post<Map<String, dynamic>>(
      '/finance/payments/$paymentId/proof',
      data: form,
      options: await _options(),
    );
    _bump();
    return FinancialPayment.fromJson(_data(response.data));
  }

  Future<Map<String, dynamic>> confirmDirect(int agreementId,
      {String decision = 'confirmed'}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/finance/agreements/$agreementId/direct-confirmation',
      data: {'decision': decision},
      options: await _options(),
    );
    _bump();
    return _data(response.data);
  }

  Future<void> attestSai(int propertyId, {int? saiTermId}) async {
    await _dio.post<void>(
      '/properties/$propertyId/sai-attestation',
      data: <String, dynamic>{'accepted': true, if (saiTermId != null) 'sai_term_id': saiTermId},
      options: await _options(),
    );
    _bump();
  }

  Future<Map<String, dynamic>> adminSummary({
    String period = '30d',
    String? transactionType,
    String? advertiserType,
    int? governorateId,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/finance/summary',
      queryParameters: _adminFilters(period, transactionType, advertiserType, governorateId),
      options: await _options(),
    );
    return _data(response.data);
  }

  Future<Map<String, dynamic>> adminWorkspace({
    String period = '30d',
    String? transactionType,
    String? advertiserType,
    int? governorateId,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/finance/workspace',
      queryParameters: _adminFilters(period, transactionType, advertiserType, governorateId),
      options: await _options(),
    );
    return _data(response.data);
  }

  Future<List<FinancialPaymentMethod>> adminPaymentMethods() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/finance/payment-methods',
      options: await _options(),
    );
    return _list(response.data)
        .map(FinancialPaymentMethod.fromJson)
        .toList(growable: false);
  }

  Future<FinancialPaymentMethod> updatePaymentMethod(
    int id,
    Map<String, dynamic> values,
  ) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/admin/finance/payment-methods/$id',
      data: values,
      options: await _options(),
    );
    return FinancialPaymentMethod.fromJson(_data(response.data));
  }

  Future<FinancialPayment> adminPayment(
    int paymentId, {
    bool actingAsAgent = false,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/finance/payments/$paymentId',
      queryParameters: actingAsAgent ? const {'acting_as_agent': 1} : null,
      options: await _options(),
    );
    return FinancialPayment.fromJson(_data(response.data));
  }

  Future<FinancialPayment> reviewPayment(
    int paymentId,
    String decision, {
    String? note,
    bool actingAsAgent = false,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/admin/finance/payments/$paymentId/review',
      data: {
        'decision': decision,
        if (note?.trim().isNotEmpty == true) 'note': note!.trim(),
        if (actingAsAgent) 'acting_as_agent': true,
      },
      options: await _options(),
    );
    _bump();
    return FinancialPayment.fromJson(_data(response.data));
  }

  Future<Response<List<int>>> paymentProof(
    int paymentId, {
    bool actingAsAgent = false,
  }) async {
    final response = await _dio.get<List<int>>(
      '/finance/payments/$paymentId/proof',
      queryParameters: actingAsAgent ? const {'acting_as_agent': 1} : null,
      options: (await _options())
          .copyWith(responseType: ResponseType.bytes),
    );
    _requestScope?.verify();
    return response;
  }

  Map<String, dynamic> _adminFilters(
    String period,
    String? transactionType,
    String? advertiserType,
    int? governorateId,
  ) => <String, dynamic>{
        'period': period,
        if (transactionType != null) 'transaction_type': transactionType,
        if (advertiserType != null) 'advertiser_type': advertiserType,
        if (governorateId != null) 'governorate_id': governorateId,
      };

  void _bump() {
    // Screens that mutate finance invalidate their local state explicitly.
  }

  Map<String, dynamic> _data(Map<String, dynamic>? body) {
    _requestScope?.verify();
    final value = body?['data'];
    if (value is! Map) {
      throw StateError('Invalid Financial V1 response.');
    }
    return Map<String, dynamic>.from(value);
  }

  List<Map<String, dynamic>> _list(Map<String, dynamic>? body) {
    _requestScope?.verify();
    final value = body?['data'];
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }
}

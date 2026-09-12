import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../account/data/auth_repository.dart';
import '../domain/financial_models.dart';

final financialRevisionProvider = StateProvider<int>((ref) => 0);

final financialRepositoryProvider = Provider<FinancialRepository>((ref) {
  return FinancialRepository(ref.watch(dioProvider), ref.watch(authRepositoryProvider));
});

class FinancialRepository {
  FinancialRepository(this._dio, this._auth);
  final Dio _dio;
  final AuthRepository _auth;

  Future<FinancialDeal> deal(int agreementId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/finance/agreements/$agreementId',
      options: await _auth.requiredAuthOptions(),
    );
    return FinancialDeal.fromJson(_data(response.data));
  }

  Future<List<FinancialPayment>> paymentsMine() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/finance/payments/mine',
      options: await _auth.requiredAuthOptions(),
    );
    return _list(response.data).map(FinancialPayment.fromJson).toList(growable: false);
  }

  Future<FinancialAccountSummary> account() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/finance/account',
      options: await _auth.requiredAuthOptions(),
    );
    return FinancialAccountSummary.fromJson(_data(response.data));
  }

  Future<FinancialPayment> createPayment({
    required int agreementId,
    required String mode,
    required int paymentMethodId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/finance/agreements/$agreementId/payments',
      data: {'mode': mode, 'payment_method_id': paymentMethodId},
      options: await _auth.requiredAuthOptions(),
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
      options: await _auth.requiredAuthOptions(),
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
      if (senderName?.trim().isNotEmpty == true) 'sender_name': senderName!.trim(),
      if (senderPhone?.trim().isNotEmpty == true) 'sender_phone': senderPhone!.trim(),
      if (providerReference?.trim().isNotEmpty == true) 'provider_reference': providerReference!.trim(),
    });
    final response = await _dio.post<Map<String, dynamic>>(
      '/finance/payments/$paymentId/proof',
      data: form,
      options: await _auth.requiredAuthOptions(),
    );
    _bump();
    return FinancialPayment.fromJson(_data(response.data));
  }

  Future<Map<String, dynamic>> confirmDirect(int agreementId, {String decision = 'confirmed'}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/finance/agreements/$agreementId/direct-confirmation',
      data: {'decision': decision},
      options: await _auth.requiredAuthOptions(),
    );
    _bump();
    return _data(response.data);
  }

  Future<void> attestSai(int propertyId) async {
    await _dio.post<void>(
      '/properties/$propertyId/sai-attestation',
      data: const <String, dynamic>{'accepted': true},
      options: await _auth.requiredAuthOptions(),
    );
    _bump();
  }

  Future<Map<String, dynamic>> adminSummary() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/finance/summary',
      options: await _auth.requiredAuthOptions(),
    );
    return _data(response.data);
  }

  Future<FinancialPayment> reviewPayment(int paymentId, String decision, {String? note}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/admin/finance/payments/$paymentId/review',
      data: {'decision': decision, if (note?.trim().isNotEmpty == true) 'note': note!.trim()},
      options: await _auth.requiredAuthOptions(),
    );
    _bump();
    return FinancialPayment.fromJson(_data(response.data));
  }

  Future<Response<List<int>>> paymentProof(int paymentId) async {
    return _dio.get<List<int>>(
      '/finance/payments/$paymentId/proof',
      options: (await _auth.requiredAuthOptions()).copyWith(responseType: ResponseType.bytes),
    );
  }

  void _bump() {
    // Repositories do not own a Ref. Screens that mutate finance invalidate
    // their local state explicitly; provider remains available for listeners.
  }

  Map<String, dynamic> _data(Map<String, dynamic>? body) {
    final value = body?['data'];
    if (value is! Map<String, dynamic>) throw StateError('Invalid Financial V1 response.');
    return value;
  }

  List<Map<String, dynamic>> _list(Map<String, dynamic>? body) {
    final value = body?['data'];
    if (value is! List) return const <Map<String, dynamic>>[];
    return value.whereType<Map<String, dynamic>>().toList(growable: false);
  }
}

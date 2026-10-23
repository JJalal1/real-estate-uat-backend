import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../account/data/auth_repository.dart';
import '../domain/agreement_models.dart';

final agreementDataRevisionProvider = StateProvider<int>((ref) => 0);

final agreementRepositoryProvider = Provider<AgreementRepository>((ref) {
  return AgreementRepository(
    ref.watch(dioProvider),
    ref.watch(authRepositoryProvider),
  );
});

class AgreementRepository {
  AgreementRepository(this._dio, this._auth);

  final Dio _dio;
  final AuthRepository _auth;

  Future<List<PropertyAgreement>> mine() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/agreements/mine',
      options: await _auth.requiredAuthOptions(),
    );
    return _list(response.data)
        .map(PropertyAgreement.fromJson)
        .toList(growable: false);
  }

  Future<PropertyAgreement> agreement(int id) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/agreements/$id',
      options: await _auth.requiredAuthOptions(),
    );
    return PropertyAgreement.fromJson(_dataMap(response.data));
  }

  Future<PropertyAgreement> startAgreement(
    int threadId,
    Map<String, dynamic> terms,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/messages/threads/$threadId/agreement',
      data: terms,
      options: await _auth.requiredAuthOptions(),
    );
    return PropertyAgreement.fromJson(_dataMap(response.data));
  }

  Future<PropertyAgreement> reviseAgreement(
    int agreementId,
    Map<String, dynamic> terms,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/agreements/$agreementId/revisions',
      data: terms,
      options: await _auth.requiredAuthOptions(),
    );
    return PropertyAgreement.fromJson(_dataMap(response.data));
  }

  Future<PropertyAgreement> acceptAgreement(
      int agreementId, int revisionId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/agreements/$agreementId/accept',
      data: {'revision_id': revisionId},
      options: await _auth.requiredAuthOptions(),
    );
    return PropertyAgreement.fromJson(_dataMap(response.data));
  }

  Future<PropertyAgreement> cancelAgreement(
      int agreementId, String reason) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/agreements/$agreementId/cancel',
      data: {'reason': reason.trim()},
      options: await _auth.requiredAuthOptions(),
    );
    return PropertyAgreement.fromJson(_dataMap(response.data));
  }

  Future<List<RentalContract>> contractsMine() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/rental-contracts/mine',
      options: await _auth.requiredAuthOptions(),
    );
    return _list(response.data)
        .map(RentalContract.fromJson)
        .toList(growable: false);
  }

  Future<RentalContract> contract(int id) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/rental-contracts/$id',
      options: await _auth.requiredAuthOptions(),
    );
    return RentalContract.fromJson(_dataMap(response.data));
  }

  Future<RentalContract> startRentalContract(
    int agreementId,
    Map<String, dynamic> terms,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/agreements/$agreementId/rental-contract',
      data: terms,
      options: await _auth.requiredAuthOptions(),
    );
    return RentalContract.fromJson(_dataMap(response.data));
  }

  Future<RentalContract> reviseRentalContract(
    int contractId,
    Map<String, dynamic> terms,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/rental-contracts/$contractId/revisions',
      data: terms,
      options: await _auth.requiredAuthOptions(),
    );
    return RentalContract.fromJson(_dataMap(response.data));
  }

  Future<RentalContract> acceptRentalContract(
      int contractId, int revisionId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/rental-contracts/$contractId/accept',
      data: {'revision_id': revisionId},
      options: await _auth.requiredAuthOptions(),
    );
    return RentalContract.fromJson(_dataMap(response.data));
  }

  Future<RentalContract> cancelRentalContract(
      int contractId, String reason) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/rental-contracts/$contractId/cancel',
      data: {'reason': reason.trim()},
      options: await _auth.requiredAuthOptions(),
    );
    return RentalContract.fromJson(_dataMap(response.data));
  }

  Future<RentalContract> terminateRentalContract(
      int contractId, String reason) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/rental-contracts/$contractId/terminate',
      data: {'reason': reason.trim()},
      options: await _auth.requiredAuthOptions(),
    );
    return RentalContract.fromJson(_dataMap(response.data));
  }

  List<Map<String, dynamic>> _list(Map<String, dynamic>? body) {
    final rows = body?['data'] as List<dynamic>? ?? const <dynamic>[];
    return rows.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  Map<String, dynamic> _dataMap(Map<String, dynamic>? body) {
    final data = body?['data'];
    if (data is! Map<String, dynamic>) {
      throw StateError('Invalid agreement response.');
    }
    return data;
  }
}

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/broker_verification.dart';
import 'auth_repository.dart';

final brokerVerificationRepositoryProvider =
    Provider<BrokerVerificationRepository>((ref) {
  return BrokerVerificationRepository(
      ref.watch(dioProvider), ref.watch(authRepositoryProvider));
});

class BrokerVerificationRepository {
  BrokerVerificationRepository(this._dio, this._auth);
  final Dio _dio;
  final AuthRepository _auth;

  Future<BrokerVerificationApplication> status() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/broker/account-verification',
      options: await _auth.requiredAuthOptions(),
    );
    return _application(response.data?['data']);
  }

  Future<BrokerVerificationApplication> submit({
    required String idFrontPath,
    required String idBackPath,
    required String selfiePath,
  }) async {
    final form = FormData();
    form.files
        .add(MapEntry('id_front', await MultipartFile.fromFile(idFrontPath)));
    form.files
        .add(MapEntry('id_back', await MultipartFile.fromFile(idBackPath)));
    form.files
        .add(MapEntry('selfie', await MultipartFile.fromFile(selfiePath)));
    final options = (await _auth.requiredAuthOptions()).copyWith(
      sendTimeout: const Duration(minutes: 2),
      receiveTimeout: const Duration(minutes: 2),
    );
    final response = await _dio.post<Map<String, dynamic>>(
      '/broker/account-verification',
      data: form,
      options: options,
    );
    return _application(response.data?['data']);
  }

  Future<List<BrokerVerificationApplication>> queue(
      {String status = 'pending'}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/broker-account-verifications',
      queryParameters: {'status': status},
      options: await _auth.requiredAuthOptions(),
    );
    final rows = response.data?['data'];
    if (rows is! List) {
      return const [];
    }
    return rows
        .whereType<Map<String, dynamic>>()
        .map(BrokerVerificationApplication.fromJson)
        .toList(growable: false);
  }

  Future<void> approve(int userId, {String? note}) async {
    await _dio.post<void>(
      '/admin/broker-account-verifications/$userId/approve',
      data: {if (note != null && note.trim().isNotEmpty) 'note': note.trim()},
      options: await _auth.requiredAuthOptions(),
    );
  }

  Future<void> reject(int userId, String reason) async {
    await _dio.post<void>(
      '/admin/broker-account-verifications/$userId/reject',
      data: {'reason': reason.trim()},
      options: await _auth.requiredAuthOptions(),
    );
  }

  Future<Uint8List> documentBytes(int userId, String kind) async {
    final options = (await _auth.requiredAuthOptions())
        .copyWith(responseType: ResponseType.bytes);
    final response = await _dio.get<List<int>>(
      '/broker/account-verification/users/$userId/documents/$kind',
      options: options,
    );
    return Uint8List.fromList(response.data ?? const <int>[]);
  }

  BrokerVerificationApplication _application(dynamic value) {
    if (value is Map<String, dynamic>) {
      return BrokerVerificationApplication.fromJson(value);
    }
    throw StateError('Invalid broker verification response.');
  }
}

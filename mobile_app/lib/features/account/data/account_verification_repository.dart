import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/account_verification.dart';
import 'auth_repository.dart';

final accountVerificationRepositoryProvider =
    Provider<AccountVerificationRepository>((ref) {
  return AccountVerificationRepository(
    ref.watch(dioProvider),
    ref.watch(authRepositoryProvider),
  );
});

class AccountVerificationRepository {
  AccountVerificationRepository(this._dio, this._auth);

  final Dio _dio;
  final AuthRepository _auth;

  Future<AccountVerificationApplication> status() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/account-verification',
      options: await _auth.requiredAuthOptions(),
    );
    return _application(response.data?['data']);
  }

  Future<AccountVerificationApplication> submit({
    required String type,
    required String governorate,
    required String district,
    required Map<String, String> files,
    List<String> workAreas = const <String>[],
    List<String> specialties = const <String>[],
    String? officeName,
    String? commercialRegisterNumber,
    String? neighborhood,
    String? street,
    String? landmark,
    double? latitude,
    double? longitude,
    String? officePhone,
  }) async {
    final form = FormData.fromMap(<String, dynamic>{
      'type': type,
      'governorate': governorate.trim(),
      'district': district.trim(),
      if (type == 'broker') 'work_areas_json': jsonEncode(workAreas),
      if (type == 'broker') 'specialties_json': jsonEncode(specialties),
      if (officeName != null) 'office_name': officeName.trim(),
      if (commercialRegisterNumber != null)
        'commercial_register_number': commercialRegisterNumber.trim(),
      if (neighborhood != null) 'neighborhood': neighborhood.trim(),
      if (street != null) 'street': street.trim(),
      if (landmark != null) 'landmark': landmark.trim(),
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (officePhone != null) 'office_phone': officePhone.trim(),
    });
    for (final entry in files.entries) {
      if (entry.value.trim().isEmpty) continue;
      form.files.add(MapEntry(
        entry.key,
        await MultipartFile.fromFile(entry.value),
      ));
    }
    final options = (await _auth.requiredAuthOptions()).copyWith(
      sendTimeout: const Duration(minutes: 3),
      receiveTimeout: const Duration(minutes: 3),
    );
    final response = await _dio.post<Map<String, dynamic>>(
      '/account-verification',
      data: form,
      options: options,
    );
    return _application(response.data?['data']);
  }

  Future<List<AccountVerificationApplication>> adminQueue({
    String status = 'pending',
    String? type,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/account-verifications',
      queryParameters: <String, dynamic>{
        'status': status,
        if (type != null) 'type': type,
      },
      options: await _auth.requiredAuthOptions(),
    );
    final rows = response.data?['data'];
    if (rows is! List) return const <AccountVerificationApplication>[];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(AccountVerificationApplication.fromJson)
        .toList(growable: false);
  }

  Future<Uint8List> documentBytes(int userId, String kind) async {
    final options = (await _auth.requiredAuthOptions()).copyWith(
      responseType: ResponseType.bytes,
      receiveTimeout: const Duration(minutes: 2),
    );
    final response = await _dio.get<List<int>>(
      '/account-verification/users/$userId/documents/$kind',
      options: options,
    );
    return Uint8List.fromList(response.data ?? const <int>[]);
  }

  Future<void> approve(int userId, {String? note}) async {
    await _dio.post<void>(
      '/admin/account-verifications/$userId/approve',
      data: <String, dynamic>{
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
      options: await _auth.requiredAuthOptions(),
    );
  }

  Future<void> requestMoreInfo(int userId, String reason) async {
    await _dio.post<void>(
      '/admin/account-verifications/$userId/more-info',
      data: <String, dynamic>{'reason': reason.trim()},
      options: await _auth.requiredAuthOptions(),
    );
  }

  Future<void> reject(int userId, String reason) async {
    await _dio.post<void>(
      '/admin/account-verifications/$userId/reject',
      data: <String, dynamic>{'reason': reason.trim()},
      options: await _auth.requiredAuthOptions(),
    );
  }

  AccountVerificationApplication _application(dynamic value) {
    if (value is Map<String, dynamic>) {
      return AccountVerificationApplication.fromJson(value);
    }
    throw StateError('Invalid account verification response.');
  }
}

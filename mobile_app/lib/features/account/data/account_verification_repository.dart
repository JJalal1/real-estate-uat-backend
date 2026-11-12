import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'account_request_scope.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/local/stage6_secure_session_store.dart';
import '../domain/account_verification.dart';
import 'auth_repository.dart';

final accountVerificationRepositoryProvider =
    Provider<AccountVerificationRepository>((ref) {
  return AccountVerificationRepository(
    ref.watch(dioProvider),
    ref.watch(authRepositoryProvider), requestScope: ref.watch(accountRequestScopeProvider),
  );
});

class AccountVerificationRepository {
  AccountVerificationRepository(this._dio, this._auth, {AccountRequestScope? requestScope}) : _requestScope = requestScope;

  final Dio _dio;
  final AuthRepository _auth;
  final AccountRequestScope? _requestScope;
  Future<Options> _sessionOptions() async {
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    final options = await (_requestScope?.options() ?? _auth.requiredAuthOptions());
    _verifySession(epoch);
    return options;
  }

  void _verifySession(int epoch) {
    _requestScope?.verify();
    if (epoch != Stage6SecureSessionStore.instance.sessionEpoch) {
      throw StateError('ACCOUNT_CHANGED');
    }
  }

  Future<AccountVerificationApplication> status() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/account-verification',
      options: await _sessionOptions(),
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
    final options = (await _sessionOptions()).copyWith(
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

  Future<AccountVerificationPage<AccountVerificationApplication>> adminQueue({
    String status = 'pending',
    String? type,
    int? userId,
    int page = 1,
    int perPage = 40,
  }) async {
    if (page < 1 || perPage < 1 || perPage > 100 || (userId != null && userId < 1)) {
      throw ArgumentError('Invalid account verification page.');
    }
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/account-verifications',
      queryParameters: <String, dynamic>{
        'status': status,
        if (type != null) 'type': type,
        if (userId != null) 'user_id': userId,
        'page': page, 'per_page': perPage,
      },
      options: await _sessionOptions(),
    );
    _verifySession(epoch);
    return AccountVerificationPage.fromJson(response.data, page: page,
      parse: AccountVerificationApplication.fromJson);
  }

  Future<Uint8List> documentBytes(int userId, String kind) async {
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    final options = (await _sessionOptions()).copyWith(
      responseType: ResponseType.bytes,
      receiveTimeout: const Duration(minutes: 2),
    );
    final response = await _dio.get<List<int>>(
      '/account-verification/users/$userId/documents/$kind',
      options: options,
    );
    _verifySession(epoch);
    return Uint8List.fromList(response.data ?? const <int>[]);
  }

  Future<void> approve(int userId, {String? note}) async {
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    await _dio.post<void>(
      '/admin/account-verifications/$userId/approve',
      data: <String, dynamic>{
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
      options: await _sessionOptions(),
    );
    _verifySession(epoch);
  }

  Future<void> requestMoreInfo(int userId, String reason) async {
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    await _dio.post<void>(
      '/admin/account-verifications/$userId/more-info',
      data: <String, dynamic>{'reason': reason.trim()},
      options: await _sessionOptions(),
    );
    _verifySession(epoch);
  }

  Future<void> reject(int userId, String reason) async {
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    await _dio.post<void>(
      '/admin/account-verifications/$userId/reject',
      data: <String, dynamic>{'reason': reason.trim()},
      options: await _sessionOptions(),
    );
    _verifySession(epoch);
  }

  AccountVerificationApplication _application(dynamic value) {
    _requestScope?.verify();
    if (value is Map<String, dynamic>) {
      return AccountVerificationApplication.fromJson(value);
    }
    throw StateError('Invalid account verification response.');
  }
}

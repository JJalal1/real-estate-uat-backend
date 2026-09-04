import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../account/data/auth_repository.dart';

final accountVerificationSupportRepositoryProvider =
    Provider<AccountVerificationSupportRepository>((ref) {
  return AccountVerificationSupportRepository(
    ref.watch(dioProvider),
    ref.watch(authRepositoryProvider),
  );
});

class AccountVerificationSupportRepository {
  AccountVerificationSupportRepository(this._dio, this._auth);

  final Dio _dio;
  final AuthRepository _auth;

  Future<List<AccountVerificationSupportItem>> pending() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/account-verifications',
      queryParameters: const <String, dynamic>{'status': 'pending'},
      options: await _auth.requiredAuthOptions(),
    );
    dynamic rows = response.data?['data'];
    if (rows is Map<String, dynamic>) {
      rows = rows['data'] ?? rows['items'];
    }
    if (rows is! List) return const <AccountVerificationSupportItem>[];
    return rows
        .whereType<Map<dynamic, dynamic>>()
        .map((row) => AccountVerificationSupportItem.fromJson(
              row.map<String, dynamic>(
                (key, value) => MapEntry(key.toString(), value),
              ),
            ))
        .where((item) => item.userId > 0)
        .toList(growable: false);
  }

  Future<void> approve(int userId) async {
    await _dio.post<Map<String, dynamic>>(
      '/admin/account-verifications/$userId/approve',
      options: await _auth.requiredAuthOptions(),
    );
  }

  Future<Uint8List> documentBytes(int userId, String kind) async {
    final authOptions = await _auth.requiredAuthOptions();
    final response = await _dio.get<List<int>>(
      '/account-verification/users/$userId/documents/$kind',
      options: Options(
        headers: authOptions.headers,
        responseType: ResponseType.bytes,
      ),
    );
    return Uint8List.fromList(response.data ?? const <int>[]);
  }
}

class AccountVerificationSupportItem {
  const AccountVerificationSupportItem({
    required this.userId,
    required this.type,
    required this.status,
    required this.name,
    required this.phone,
    required this.details,
  });

  final int userId;
  final String type;
  final String status;
  final String name;
  final String phone;
  final Map<String, dynamic> details;

  factory AccountVerificationSupportItem.fromJson(Map<String, dynamic> json) {
    final user = _map(json['user']);
    final details = _details(json['details']);
    return AccountVerificationSupportItem(
      userId: _int(json['user_id'] ?? user['id'] ?? json['id']),
      type: _text(json['type']),
      status: _text(json['status']),
      name: _text(
        user['name'] ?? json['user_name'] ?? json['applicant_name'] ?? json['name'],
      ),
      phone: _text(user['phone'] ?? json['phone'] ?? json['user_phone']),
      details: <String, dynamic>{...json, ...details},
    );
  }

  String get typeLabel => switch (type) {
        'owner' => 'مالك',
        'broker' => 'دلال',
        'office' => 'مكتب عقارات',
        _ => type.isEmpty ? 'حساب' : type,
      };

  String detailText(String key) {
    final value = details[key];
    if (value == null) return '';
    return value.toString().trim();
  }

  static Map<String, dynamic> _map(dynamic value) {
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return const <String, dynamic>{};
  }

  static Map<String, dynamic> _details(dynamic value) {
    if (value is Map) return _map(value);
    if (value is String && value.trim().isNotEmpty) {
      try {
        return _map(jsonDecode(value));
      } catch (_) {
        return const <String, dynamic>{};
      }
    }
    return const <String, dynamic>{};
  }

  static String _text(dynamic value) => value?.toString().trim() ?? '';

  static int _int(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

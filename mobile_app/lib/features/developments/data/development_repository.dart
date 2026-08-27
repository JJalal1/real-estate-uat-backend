import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../account/data/auth_repository.dart';
import '../domain/development_models.dart';

final developmentRepositoryProvider = Provider<DevelopmentRepository>((ref) {
  return DevelopmentRepository(
      ref.watch(dioProvider), ref.watch(authRepositoryProvider));
});

class DevelopmentRepository {
  DevelopmentRepository(this._dio, this._auth);
  final Dio _dio;
  final AuthRepository _auth;

  Future<List<DevelopmentSummary>> publicProjects({String? query}) async {
    final response = await _dio.get<Map<String, dynamic>>('/developments',
        queryParameters: {
          if (query != null && query.trim().isNotEmpty) 'q': query.trim()
        });
    return _rows(response.data)
        .map(DevelopmentSummary.fromJson)
        .toList(growable: false);
  }

  Future<DevelopmentDetails> publicProject(int id) async {
    final response = await _dio.get<Map<String, dynamic>>('/developments/$id');
    return DevelopmentDetails.fromJson(_data(response.data));
  }

  Future<List<DeveloperSummary>> adminDevelopers() async {
    final response = await _dio.get<Map<String, dynamic>>(
        '/admin/developments/developers',
        options: await _auth.requiredAuthOptions());
    return _rows(response.data)
        .map(DeveloperSummary.fromJson)
        .toList(growable: false);
  }

  Future<List<DevelopmentSummary>> adminProjects() async {
    final response = await _dio.get<Map<String, dynamic>>(
        '/admin/developments/projects',
        options: await _auth.requiredAuthOptions());
    return _rows(response.data)
        .map(DevelopmentSummary.fromJson)
        .toList(growable: false);
  }

  Future<DevelopmentDetails> adminProject(int id) async {
    final response = await _dio.get<Map<String, dynamic>>(
        '/admin/developments/projects/$id',
        options: await _auth.requiredAuthOptions());
    return DevelopmentDetails.fromJson(_data(response.data));
  }

  Future<DeveloperSummary> createDeveloper(Map<String, dynamic> payload) async {
    final response = await _dio.post<Map<String, dynamic>>(
        '/admin/developments/developers',
        data: payload,
        options: await _auth.requiredAuthOptions());
    return DeveloperSummary.fromJson(_data(response.data));
  }

  Future<DevelopmentSummary> createProject(Map<String, dynamic> payload) async {
    final response = await _dio.post<Map<String, dynamic>>(
        '/admin/developments/projects',
        data: payload,
        options: await _auth.requiredAuthOptions());
    return DevelopmentSummary.fromJson(_data(response.data));
  }

  Future<DevelopmentUnitItem> createUnit(
      int projectId, Map<String, dynamic> payload) async {
    final response = await _dio.post<Map<String, dynamic>>(
        '/admin/developments/projects/$projectId/units',
        data: payload,
        options: await _auth.requiredAuthOptions());
    return DevelopmentUnitItem.fromJson(_data(response.data));
  }

  Future<void> publish(int projectId) async {
    await _dio.post<void>('/admin/developments/projects/$projectId/publish',
        options: await _auth.requiredAuthOptions());
  }

  Future<void> unpublish(int projectId) async {
    await _dio.post<void>('/admin/developments/projects/$projectId/unpublish',
        options: await _auth.requiredAuthOptions());
  }

  List<Map<String, dynamic>> _rows(Map<String, dynamic>? body) {
    final rows = body?['data'] as List<dynamic>? ?? const <dynamic>[];
    return rows.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  Map<String, dynamic> _data(Map<String, dynamic>? body) {
    final data = body?['data'];
    if (data is! Map<String, dynamic>) {
      throw StateError('Invalid developments response.');
    }
    return data;
  }
}

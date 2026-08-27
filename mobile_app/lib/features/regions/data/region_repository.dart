import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/network/api_client.dart';
import '../../account/data/auth_repository.dart';
import '../domain/region_models.dart';

final regionRepositoryProvider = Provider<RegionRepository>((ref) =>
    RegionRepository(
        ref.watch(dioProvider), ref.watch(authRepositoryProvider)));

class RegionRepository {
  RegionRepository(this._dio, this._auth);
  final Dio _dio;
  final AuthRepository _auth;

  Future<List<GovernorateModel>> governorates() async {
    final response = await _dio.get<Map<String, dynamic>>(
        '/admin/regions/governorates',
        options: await _auth.requiredAuthOptions());
    return _mapList(response.data?['data'], GovernorateModel.fromJson);
  }

  Future<List<RegionCell>> cells({int? governorateId, String? search}) async {
    final response =
        await _dio.get<Map<String, dynamic>>('/admin/regions/cells',
            queryParameters: {
              if (governorateId != null) 'governorate_id': governorateId,
              if (search != null && search.trim().isNotEmpty)
                'search': search.trim(),
            },
            options: await _auth.requiredAuthOptions());
    return _mapList(response.data?['data'], RegionCell.fromJson);
  }

  Future<List<RegionProperty>> cellProperties(int cellId,
      {String? search}) async {
    final response = await _dio.get<Map<String, dynamic>>(
        '/admin/regions/cells/$cellId/properties',
        queryParameters: {
          if (search != null && search.trim().isNotEmpty)
            'search': search.trim(),
        },
        options: await _auth.requiredAuthOptions());
    return _mapList(response.data?['data'], RegionProperty.fromJson);
  }

  Future<void> createGovernorate(
      {required String code, required String nameAr, String? nameEn}) async {
    await _dio.post<void>('/admin/regions/governorates',
        data: {'code': code, 'name_ar': nameAr, 'name_en': nameEn},
        options: await _auth.requiredAuthOptions());
  }

  Future<void> createCell(
      {required int governorateId,
      required String code,
      required String nameAr,
      String? nameEn,
      required List<LatLng> points}) async {
    await _dio.post<void>('/admin/regions/cells',
        data: {
          'governorate_id': governorateId,
          'code': code,
          'name_ar': nameAr,
          'name_en': nameEn,
          'points': points
              .map((p) => {'latitude': p.latitude, 'longitude': p.longitude})
              .toList(),
        },
        options: await _auth.requiredAuthOptions());
  }

  Future<void> updateCellBoundary(
      {required RegionCell cell, required List<LatLng> points}) async {
    await _dio.patch<void>('/admin/regions/cells/${cell.id}',
        data: {
          'points': points
              .map((p) => {'latitude': p.latitude, 'longitude': p.longitude})
              .toList()
        },
        options: await _auth.requiredAuthOptions());
  }

  Future<void> setCellActive(RegionCell cell, bool active) async {
    await _dio.patch<void>('/admin/regions/cells/${cell.id}',
        data: {'is_active': active},
        options: await _auth.requiredAuthOptions());
  }

  List<T> _mapList<T>(dynamic value, T Function(Map<String, dynamic>) convert) {
    if (value is! List) return <T>[];
    return value
        .whereType<Map<String, dynamic>>()
        .map(convert)
        .toList(growable: false);
  }
}

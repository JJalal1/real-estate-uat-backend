import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../account/data/auth_repository.dart';
import '../domain/service_models.dart';

final serviceRepositoryProvider = Provider<ServiceRepository>((ref) =>
    ServiceRepository(
        ref.watch(dioProvider), ref.watch(authRepositoryProvider)));

final freeServicesHubProvider = FutureProvider.autoDispose<FreeServicesHubModel>(
  (ref) => ref.watch(serviceRepositoryProvider).freeHub(),
);

class ServiceRepository {
  ServiceRepository(this._dio, this._auth);
  final Dio _dio;
  final AuthRepository _auth;

  Future<FreeServicesHubModel> freeHub() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/services/hub',
      options: await _auth.requiredAuthOptions(),
    );
    return FreeServicesHubModel.fromJson(_data(response.data));
  }

  Future<List<ServiceOfferingModel>> catalog() async {
    final response = await _dio.get<Map<String, dynamic>>('/services/catalog');
    return _rows(response.data)
        .map(ServiceOfferingModel.fromJson)
        .toList(growable: false);
  }

  Future<List<ServiceOrderModel>> mineOrders() async =>
      _authList('/services/orders/mine', ServiceOrderModel.fromJson);
  Future<List<ServiceEntitlementModel>> mineEntitlements() async => _authList(
      '/services/entitlements/mine', ServiceEntitlementModel.fromJson);
  Future<List<ServiceOfferingModel>> adminOffers() async =>
      _authList('/admin/services/offers', ServiceOfferingModel.fromJson);
  Future<List<ServiceOrderModel>> adminOrders() async =>
      _authList('/admin/payments/orders', ServiceOrderModel.fromJson);

  Future<List<ServiceTargetListing>> myListings() async {
    final response = await _dio.get<Map<String, dynamic>>(
        '/properties/mine/list',
        options: await _auth.requiredAuthOptions());
    return _rows(response.data)
        .map(ServiceTargetListing.fromJson)
        .where((row) => row.eligible)
        .toList(growable: false);
  }

  Future<ServiceOrderModel> createOrder(int offeringId, {int? targetId}) async {
    final response = await _dio.post<Map<String, dynamic>>('/services/orders',
        data: {
          'offering_id': offeringId,
          if (targetId != null) 'target_id': targetId
        },
        options: await _auth.requiredAuthOptions());
    return ServiceOrderModel.fromJson(_data(response.data));
  }

  Future<ServiceOrderModel> cancelOrder(int orderId) async {
    final response = await _dio.post<Map<String, dynamic>>(
        '/services/orders/$orderId/cancel',
        options: await _auth.requiredAuthOptions());
    return ServiceOrderModel.fromJson(_data(response.data));
  }

  Future<ServiceOfferingModel> updateOffer(int offerId,
      {required String priceAmount,
      required String currency,
      required int? durationDays,
      required bool isActive}) async {
    final response = await _dio.patch<Map<String, dynamic>>(
        '/admin/services/offers/$offerId',
        data: {
          'price_amount': priceAmount,
          'currency': currency,
          'duration_days': durationDays,
          'is_active': isActive
        },
        options: await _auth.requiredAuthOptions());
    return ServiceOfferingModel.fromJson(_data(response.data));
  }

  Future<ServiceOrderModel> settle(int orderId, String reference) async {
    final response = await _dio.post<Map<String, dynamic>>(
        '/admin/payments/orders/$orderId/settle',
        data: {
          'provider': 'manual_admin',
          'provider_reference': reference.trim()
        },
        options: await _auth.requiredAuthOptions());
    return ServiceOrderModel.fromJson(_data(response.data));
  }

  Future<ServiceOrderModel> refund(int orderId, String reason) async {
    final response = await _dio.post<Map<String, dynamic>>(
        '/admin/payments/orders/$orderId/refund',
        data: {'reason': reason.trim()},
        options: await _auth.requiredAuthOptions());
    return ServiceOrderModel.fromJson(_data(response.data));
  }

  Future<List<T>> _authList<T>(
      String path, T Function(Map<String, dynamic>) parse) async {
    final response = await _dio.get<Map<String, dynamic>>(path,
        options: await _auth.requiredAuthOptions());
    return _rows(response.data).map(parse).toList(growable: false);
  }

  List<Map<String, dynamic>> _rows(Map<String, dynamic>? body) =>
      (body?['data'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
  Map<String, dynamic> _data(Map<String, dynamic>? body) {
    final data = body?['data'];
    if (data is! Map<String, dynamic>) {
      throw StateError('Invalid Stage 14 service response.');
    }
    return data;
  }
}

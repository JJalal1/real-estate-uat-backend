import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../account/data/auth_repository.dart';
import '../domain/booking_models.dart';

final bookingRepositoryProvider = Provider<BookingRepository>((ref) {
  return BookingRepository(
      ref.watch(dioProvider), ref.watch(authRepositoryProvider));
});

class BookingRepository {
  BookingRepository(this._dio, this._auth);
  final Dio _dio;
  final AuthRepository _auth;

  Future<List<ViewingBooking>> mine() async => _list('/bookings/mine');
  Future<List<ViewingBooking>> managed() async => _list('/bookings/managed');

  Future<ViewingBooking> requestProperty(
      int propertyId, Map<String, dynamic> payload) async {
    final response = await _dio.post<Map<String, dynamic>>(
        '/properties/$propertyId/viewings',
        data: payload,
        options: await _auth.requiredAuthOptions());
    return ViewingBooking.fromJson(_data(response.data));
  }

  Future<ViewingBooking> requestUnit(
      int unitId, Map<String, dynamic> payload) async {
    final response = await _dio.post<Map<String, dynamic>>(
        '/development-units/$unitId/viewings',
        data: payload,
        options: await _auth.requiredAuthOptions());
    return ViewingBooking.fromJson(_data(response.data));
  }

  Future<ViewingBooking> confirm(int bookingId, {String? note}) => _action(
      bookingId,
      'confirm',
      {if (note != null && note.trim().isNotEmpty) 'note': note.trim()});
  Future<ViewingBooking> decline(int bookingId, String note) =>
      _action(bookingId, 'decline', {'note': note.trim()});
  Future<ViewingBooking> cancel(int bookingId, String reason) =>
      _action(bookingId, 'cancel', {'reason': reason.trim()});
  Future<ViewingBooking> complete(int bookingId) =>
      _action(bookingId, 'complete', const <String, dynamic>{});
  Future<ViewingBooking> reschedule(
          int bookingId, Map<String, dynamic> payload) =>
      _action(bookingId, 'reschedule', payload);

  Future<List<ViewingBooking>> _list(String path) async {
    final response = await _dio.get<Map<String, dynamic>>(path,
        options: await _auth.requiredAuthOptions());
    final rows = response.data?['data'] as List<dynamic>? ?? const <dynamic>[];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(ViewingBooking.fromJson)
        .toList(growable: false);
  }

  Future<ViewingBooking> _action(
      int id, String action, Map<String, dynamic> data) async {
    final response = await _dio.post<Map<String, dynamic>>(
        '/bookings/$id/$action',
        data: data,
        options: await _auth.requiredAuthOptions());
    return ViewingBooking.fromJson(_data(response.data));
  }

  Map<String, dynamic> _data(Map<String, dynamic>? body) {
    final data = body?['data'];
    if (data is! Map<String, dynamic>) {
      throw StateError('Invalid booking response.');
    }
    return data;
  }
}

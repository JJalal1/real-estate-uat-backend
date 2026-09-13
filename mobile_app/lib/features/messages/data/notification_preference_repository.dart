import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../account/data/auth_repository.dart';

final notificationPreferenceRepositoryProvider =
    Provider<NotificationPreferenceRepository>((ref) {
  return NotificationPreferenceRepository(
    ref.watch(dioProvider),
    ref.watch(authRepositoryProvider),
  );
});

final notificationPreferencesProvider =
    FutureProvider.autoDispose<NotificationPreferences>((ref) {
  return ref.watch(notificationPreferenceRepositoryProvider).get();
});

class NotificationPreferenceRepository {
  const NotificationPreferenceRepository(this._dio, this._auth);

  final Dio _dio;
  final AuthRepository _auth;

  Future<NotificationPreferences> get() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/notification-preferences',
      options: await _auth.requiredAuthOptions(),
    );
    return NotificationPreferences.fromJson(_data(response.data));
  }

  Future<NotificationPreferences> update(Map<String, bool> values) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/notification-preferences',
      data: values,
      options: await _auth.requiredAuthOptions(),
    );
    return NotificationPreferences.fromJson(_data(response.data));
  }

  Map<String, dynamic> _data(Map<String, dynamic>? body) {
    final data = body?['data'];
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid notification preference response.');
    }
    return data;
  }
}

class NotificationPreferences {
  const NotificationPreferences({
    required this.messages,
    required this.viewings,
    required this.agreements,
    required this.listingActivity,
    required this.discoveryAlerts,
    required this.services,
    required this.essentialAlwaysOn,
  });

  final bool messages;
  final bool viewings;
  final bool agreements;
  final bool listingActivity;
  final bool discoveryAlerts;
  final bool services;
  final bool essentialAlwaysOn;

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      messages: json['messages'] != false,
      viewings: json['viewings'] != false,
      agreements: json['agreements'] != false,
      listingActivity: json['listing_activity'] != false,
      discoveryAlerts: json['discovery_alerts'] != false,
      services: json['services'] != false,
      essentialAlwaysOn: json['essential_always_on'] != false,
    );
  }

  Map<String, bool> toApi() => {
        'messages': messages,
        'viewings': viewings,
        'agreements': agreements,
        'listing_activity': listingActivity,
        'discovery_alerts': discoveryAlerts,
        'services': services,
      };

  NotificationPreferences copyWith({
    bool? messages,
    bool? viewings,
    bool? agreements,
    bool? listingActivity,
    bool? discoveryAlerts,
    bool? services,
  }) {
    return NotificationPreferences(
      messages: messages ?? this.messages,
      viewings: viewings ?? this.viewings,
      agreements: agreements ?? this.agreements,
      listingActivity: listingActivity ?? this.listingActivity,
      discoveryAlerts: discoveryAlerts ?? this.discoveryAlerts,
      services: services ?? this.services,
      essentialAlwaysOn: essentialAlwaysOn,
    );
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/messages/data/notification_preference_repository.dart';

void main() {
  test('notification preferences default missing fields to enabled', () {
    final value = NotificationPreferences.fromJson(const <String, dynamic>{});

    expect(value.messages, isTrue);
    expect(value.viewings, isTrue);
    expect(value.agreements, isTrue);
    expect(value.listingActivity, isTrue);
    expect(value.discoveryAlerts, isTrue);
    expect(value.services, isTrue);
    expect(value.essentialAlwaysOn, isTrue);
  });

  test('notification preferences serialize only configurable categories', () {
    final value = NotificationPreferences.fromJson(const {
      'messages': false,
      'viewings': true,
      'agreements': false,
      'listing_activity': true,
      'discovery_alerts': false,
      'services': true,
      'essential_always_on': true,
    });

    expect(value.toApi(), {
      'messages': false,
      'viewings': true,
      'agreements': false,
      'listing_activity': true,
      'discovery_alerts': false,
      'services': true,
    });
    expect(value.toApi().containsKey('essential_always_on'), isFalse);
  });
}

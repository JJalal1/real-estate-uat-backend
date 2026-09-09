import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('property gallery and trust UI expose only real product capabilities', () {
    final source = File(
      'lib/features/properties/presentation/property_details_screen.dart',
    ).readAsStringSync();

    expect(source, contains('_FullscreenGallery'));
    expect(source, contains('InteractiveViewer'));
    expect(source, contains('هوية المعلن متحققة'));
    expect(source, contains("verificationFlag('identity_reviewed')"));
    expect(source, isNot(contains('مشاهدات العقار')));
  });

  test('professional workspace prioritizes real next actions', () {
    final source = File(
      'lib/features/services/presentation/professional_workspace_screen.dart',
    ).readAsStringSync();

    expect(source, contains('يحتاج إجراء الآن'));
    expect(source, contains('unreadConversations'));
    expect(source, contains('activeViewings'));
    expect(source, contains('activeAgreements'));
    expect(source, contains('corrections.length'));
    expect(source, contains('staleListings.length'));
  });

  test('discovery remembers recent searches and reports result count clearly', () {
    final mapSource = File(
      'lib/features/map/presentation/map_screen.dart',
    ).readAsStringSync();
    final historySource = File(
      'lib/features/map/data/property_discovery_history_store.dart',
    ).readAsStringSync();

    expect(mapSource, contains('بحثت مؤخراً'));
    expect(mapSource, contains('_restoreDiscoveryHistory'));
    expect(mapSource, contains(r"'${items.length} نتيجة'"));
    expect(historySource, contains('property_discovery_history_v1.json'));
    expect(historySource, contains('recent_searches'));
    expect(historySource, contains('last_filters'));
  });

  test('UAT network observability correlates slow calls without request payloads', () {
    final source = File('lib/core/network/api_client.dart').readAsStringSync();
    expect(source, contains('_RequestTimingInterceptor'));
    expect(source, contains('x-request-id'));
    expect(source, contains('duration_ms='));
    expect(source, isNot(contains('queryParameters.toString')));
  });
}

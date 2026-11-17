import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/network/api_client.dart';
import 'package:real_estate_mobile/core/offline/offline_connection.dart';
import 'package:real_estate_mobile/core/offline/offline_coordinator.dart';
import 'package:real_estate_mobile/core/offline/offline_store.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_repository.dart';
import 'support/owner_ux_fixtures.dart';

class _DelayedSnapshot extends OfflineStore {
  final started = Completer<void>();
  final saved = Completer<Map<String, dynamic>?>();
  @override
  Future<Map<String, dynamic>?> read(String space, String identity,
      {bool private = false, bool strict = false}) async {
    if (space != 'discovery') {
      return null;
    }
    if (!started.isCompleted) {
      started.complete();
    }
    return saved.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadUxFixtures);
  testWidgets(
      'delayed offline restoration cannot overwrite a governorate the user just selected',
      (tester) async {
    const channel = MethodChannel('real_estate/network');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => {'connected': false});
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final store = _DelayedSnapshot(),
        connection = OfflineConnectionController();
    final dio = Dio(BaseOptions(baseUrl: 'https://synthetic.invalid/api'));
    final scope = uxContainer(extra: [
      offlineStoreProvider.overrideWithValue(store),
      offlineConnectionProvider.overrideWith((ref) => connection),
      dioProvider.overrideWithValue(dio)
    ]);
    await pumpUx(
        tester,
        scope,
        OfflineCoordinator(
            child: Scaffold(
                body: Consumer(
                    builder: (_, ref, __) => TextButton(
                        onPressed: () =>
                            ref.read(homeLocationProvider.notifier).state =
                                const HomeLocation(
                                    governorate: 'إب',
                                    governorateCode: 'YE-IB',
                                    label: 'إب',
                                    manual: true),
                        child: const Text('اختر إب'))))));
    await store.started.future;
    await tester.tap(find.text('اختر إب'));
    await tester.pump();
    store.saved.complete({
      'location': {
        'latitude': 14.54,
        'longitude': 44.40,
        'governorate': 'ذمار',
        'governorate_code': 'YE-DH',
        'label': 'ذمار',
        'manual': true
      },
      'criteria': <String, dynamic>{}
    });
    await tester.pumpAndSettle();
    expect(scope.read(homeLocationProvider).governorateCode, 'YE-IB');
    expect(tester.takeException(), isNull);
    await closeUx(tester);
    dio.close();
  });
}

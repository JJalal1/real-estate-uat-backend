import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/network/api_client.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/messages/data/notification_preference_repository.dart';
import 'package:real_estate_mobile/features/messages/data/push_registration_repository.dart';
import 'package:real_estate_mobile/features/messages/presentation/notification_preferences_screen.dart';
import 'package:real_estate_mobile/features/properties/data/favorites_repository.dart';
import 'package:real_estate_mobile/features/properties/data/saved_search_repository.dart';
import 'package:real_estate_mobile/features/services/data/service_repository.dart';
import 'package:real_estate_mobile/features/services/presentation/property_journey_screen.dart';

AuthUser _user(int id) => AuthUser.fromJson({
  'id': id, 'name': 'Synthetic account $id', 'account_status': 'active',
  'phone_verified_at': '2026-10-25T00:00:00Z',
});

class _Auth extends AuthController {
  @override
  Future<AuthUser?> build() async => _user(1);
  void change(int? id) => state = AsyncData(id == null ? null : _user(id));
}

class _Credentials implements AuthRepository {
  int? actor = 1;
  Completer<void>? optionsGate;
  @override
  Future<Options> requiredAuthOptions() async {
    await optionsGate?.future;
    if (actor == null) throw StateError('AUTH_REQUIRED');
    return Options(headers: {'Authorization': 'Bearer synthetic-$actor'});
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}

class _Harness {
  final auth = _Auth();
  final credentials = _Credentials();
  final dio = Dio(BaseOptions(baseUrl: 'https://synthetic.invalid/api'));
  final calls = <RequestOptions>[];
  late final ProviderContainer container;
  Completer<void>? saveGate;
  bool saveFails = false;
  int favoriteCount = 1;

  Future<void> start() async {
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) async {
      calls.add(request);
      if (request.method == 'PATCH') {
        await saveGate?.future;
        if (saveFails) {
          handler.reject(DioException(requestOptions: request,
            type: DioExceptionType.badResponse,
            response: Response<void>(requestOptions: request, statusCode: 503)));
          return;
        }
      }
      final first = request.headers['Authorization'] == 'Bearer synthetic-1';
      final id = first ? 1 : 2;
      final Object data = switch (request.path) {
        '/notification-preferences' => {
          'messages': first, 'viewings': first, 'agreements': first,
          'listing_activity': first, 'discovery_alerts': first, 'services': first,
          'essential_always_on': true,
        },
        '/saved-searches' => request.method == 'GET' ? [{
          'id': id, 'name': 'query-$id', 'filters': {'type': 'land'},
          'alert_frequency': 'instant', 'is_active': true,
        }] : {'id': id, 'name': 'query-$id', 'filters': {'type': 'land'}},
        '/services/hub' => {'account_type': first ? 'broker' : 'basic'},
        '/favorites' => [for (var i = 0; i < favoriteCount; i++) {
          'property': {'id': id * 100 + i, 'title': 'Synthetic $id',
            'status': 'published', 'type': 'land', 'purpose': 'sale', 'price': 100},
        }],
        '/messages/threads' || '/agreements/mine' => <Object>[],
        _ => throw StateError('Unexpected request ${request.method} ${request.path}'),
      };
      handler.resolve(Response<Map<String, dynamic>>(requestOptions: request,
        statusCode: 200, data: {'data': data, 'meta': {'last_page': 1}}));
    }));
    container = ProviderContainer(overrides: [
      authControllerProvider.overrideWith(() => auth),
      authRepositoryProvider.overrideWithValue(credentials),
      dioProvider.overrideWithValue(dio),
      pushCapabilityProvider.overrideWith((_) async => false),
    ]);
    await container.read(authControllerProvider.future);
  }

  void change(int? id) { credentials.actor = id; auth.change(id); }
  void close() { container.dispose(); dio.close(force: true); }
}

Future<_Harness> _harness() async {
  final harness = _Harness();
  await harness.start();
  addTearDown(harness.close);
  return harness;
}

Future<void> _preferences(WidgetTester tester, _Harness h) async {
  tester.view.physicalSize = const Size(412, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(UncontrolledProviderScope(container: h.container,
    child: const MaterialApp(home: NotificationPreferencesScreen())));
  await tester.pumpAndSettle();
}

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;

  test('kept-alive saved searches reload for the new account', () async {
    final h = await _harness();
    h.container.listen(savedSearchesProvider, (_, __) {});
    expect((await h.container.read(savedSearchesProvider.future)).single.name, 'query-1');
    h.change(2);
    expect((await h.container.read(savedSearchesProvider.future)).single.name, 'query-2');
  });

  test('kept-alive notification preferences reload for the new account', () async {
    final h = await _harness();
    h.container.listen(notificationPreferencesProvider, (_, __) {});
    expect((await h.container.read(notificationPreferencesProvider.future)).messages, isTrue);
    h.change(2);
    expect((await h.container.read(notificationPreferencesProvider.future)).messages, isFalse);
  });

  test('kept-alive service capabilities reload for the new account', () async {
    final h = await _harness();
    h.container.listen(freeServicesHubProvider, (_, __) {});
    expect((await h.container.read(freeServicesHubProvider.future)).accountType, 'broker');
    h.change(2);
    expect((await h.container.read(freeServicesHubProvider.future)).accountType, 'basic');
  });

  test('journey reloads private data after account changes', () async {
    final h = await _harness();
    h.container.listen(propertyJourneyProvider, (_, __) {});
    expect((await h.container.read(propertyJourneyProvider.future)).favorites.single.id, 100);
    h.change(2);
    expect((await h.container.read(propertyJourneyProvider.future)).favorites.single.id, 200);
  });

  test('journey follows favorite mutations while it remains mounted', () async {
    final h = await _harness();
    h.container.listen(propertyJourneyProvider, (_, __) {});
    expect((await h.container.read(propertyJourneyProvider.future)).favorites.length, 1);
    h.favoriteCount = 2;
    h.container.read(favoriteDataRevisionProvider.notifier).state++;
    expect((await h.container.read(propertyJourneyProvider.future)).favorites.length, 2);
  });

  test('retained preference repository cannot save with the next account token', () async {
    final h = await _harness();
    final previous = h.container.read(notificationPreferenceRepositoryProvider);
    h.change(2);
    await expectLater(previous.update({'messages': false}), throwsStateError);
    expect(h.calls, isEmpty);
  });

  test('retained saved-search repository cannot create under the next account', () async {
    final h = await _harness();
    final previous = h.container.read(savedSearchRepositoryProvider);
    h.change(2);
    await expectLater(previous.create(name: 'Private old query', filters: {'type': 'land'}), throwsStateError);
    expect(h.calls, isEmpty);
  });

  test('account change during secure-token read rejects the mutation before HTTP', () async {
    final h = await _harness();
    h.credentials.optionsGate = Completer<void>();
    final previous = h.container.read(notificationPreferenceRepositoryProvider);
    final save = previous.update({'messages': false});
    final rejected = expectLater(save, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    h.change(2);
    h.credentials.optionsGate!.complete();
    await rejected;
    expect(h.calls, isEmpty);
  });

  testWidgets('preference draft from account A is removed when B signs in', (tester) async {
    final h = await _harness();
    await _preferences(tester, h);
    expect(tester.widgetList<SwitchListTile>(find.byType(SwitchListTile)).every((w) => w.value), isTrue);
    h.change(2);
    await tester.pumpAndSettle();
    final switches = tester.widgetList<SwitchListTile>(find.byType(SwitchListTile)).toList();
    expect(switches, isNotEmpty);
    expect(switches.every((w) => !w.value), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preference switches cannot overwrite edits during an in-flight save', (tester) async {
    final h = await _harness();
    await _preferences(tester, h);
    h.saveGate = Completer<void>();
    await tester.ensureVisible(find.text('حفظ التفضيلات'));
    await tester.tap(find.text('حفظ التفضيلات'));
    await tester.pump();
    final switches = tester.widgetList<SwitchListTile>(find.byType(SwitchListTile)).toList();
    expect(switches, isNotEmpty);
    expect(switches.every((w) => w.onChanged == null), isTrue);
    h.saveGate!.complete();
    await tester.pumpAndSettle();
    expect(tester.widgetList<SwitchListTile>(find.byType(SwitchListTile)).every((w) => w.onChanged != null), isTrue);
  });
}

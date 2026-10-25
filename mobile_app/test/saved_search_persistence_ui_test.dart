import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/network/api_client.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/properties/data/saved_search_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/saved_property_search.dart';
import 'package:real_estate_mobile/features/properties/presentation/saved_search_builder_screen.dart';

class _Auth extends AuthController {
  @override
  Future<AuthUser?> build() async => AuthUser.fromJson({
    'id': 1, 'name': 'Synthetic search owner', 'account_status': 'active',
    'phone_verified_at': '2026-10-25T00:00:00Z',
  });
}

class _Credentials implements AuthRepository {
  @override
  Future<Options> requiredAuthOptions() async =>
    Options(headers: {'Authorization': 'Bearer synthetic-search-owner'});
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}

class _Server {
  final dio = Dio(BaseOptions(baseUrl: 'https://synthetic.invalid/api'));
  final calls = <RequestOptions>[];
  int createStatus = 200;
  bool rejectUpdate = false;
  Completer<void>? gate;
  final saved = <String, dynamic>{
    'id': 37, 'name': 'Original private name', 'filters': {'type': 'land'},
    'alert_frequency': 'off', 'is_active': true, 'matching_count': 0,
  };
  late final ProviderContainer container;

  Future<void> start() async {
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) async {
      calls.add(request);
      await gate?.future;
      if (request.method == 'PATCH' && rejectUpdate) {
        handler.reject(DioException(requestOptions: request,
          type: DioExceptionType.badResponse,
          response: Response<Map<String, dynamic>>(requestOptions: request, statusCode: 422,
            data: {'message': 'هذه الشروط محفوظة في بحث آخر.',
              'errors': {'filters': ['هذه الشروط محفوظة في بحث آخر.']}})));
        return;
      }
      if (request.method == 'PATCH' || createStatus == 201) {
        saved.addAll(Map<String, dynamic>.from(request.data as Map));
      }
      handler.resolve(Response<Map<String, dynamic>>(requestOptions: request,
        statusCode: request.method == 'POST' ? createStatus : 200,
        data: {'data': Map<String, dynamic>.from(saved)}));
    }));
    container = ProviderContainer(overrides: [
      authControllerProvider.overrideWith(_Auth.new),
      authRepositoryProvider.overrideWithValue(_Credentials()),
      dioProvider.overrideWithValue(dio),
    ]);
    await container.read(authControllerProvider.future);
  }

  void close() {
    if (gate != null && !gate!.isCompleted) gate!.complete();
    container.dispose();
    dio.close(force: true);
  }
}

Future<_Server> _server() async {
  final server = _Server();
  await server.start();
  addTearDown(server.close);
  return server;
}

Future<void> _open(WidgetTester tester, _Server server,
  {SavedPropertySearch? existing, required ValueChanged<bool?> onResult}) async {
  tester.view.physicalSize = const Size(412, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(UncontrolledProviderScope(container: server.container,
    child: MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () async => onResult(await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => SavedSearchBuilderScreen(
          existingSearch: existing, initialFilters: const {'type': 'land'}, fixedFilters: true)))),
      child: const Text('Open saved search')))))));
  await tester.tap(find.text('Open saved search'));
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester, String label) async {
  final button = find.text(label);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;

  test('duplicate POST is distinguished from creation without an implicit edit', () async {
    final server = await _server();
    final repository = server.container.read(savedSearchRepositoryProvider);
    final existing = await repository.create(name: 'Requested name', filters: {'type': 'land'});
    expect(existing.alreadySaved, isTrue);
    expect(existing.name, 'Original private name');
    expect(existing.alertFrequency, 'off');
    expect(server.calls.map((r) => r.method), ['POST']);
    server.createStatus = 201;
    final created = await repository.create(name: 'New name', filters: {'type': 'villa'});
    expect(created.alreadySaved, isFalse);
    expect(created.name, 'New name');
    final updated = await repository.update(created.id, name: 'Confirmed edit');
    expect(updated.alreadySaved, isFalse);
    expect(updated.name, 'Confirmed edit');
  });

  testWidgets('duplicate save keeps requested input and requires an explicit edit', (tester) async {
    final server = await _server();
    bool returned = false;
    bool? result;
    await _open(tester, server, onResult: (value) { returned = true; result = value; });
    await tester.enterText(find.byType(TextField), 'Requested private name');
    await _save(tester, 'حفظ البحث');
    expect(returned, isFalse);
    expect(server.saved['name'], 'Original private name');
    expect(server.saved['alert_frequency'], 'off');
    expect(server.calls.map((r) => r.method), ['POST']);
    expect(find.textContaining('هذا البحث محفوظ مسبقًا.'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Requested private name');
    expect(tester.widget<RadioListTile<String>>(find.byType(RadioListTile<String>).first).groupValue, 'instant');
    await _save(tester, 'حفظ التعديلات');
    expect(returned, isTrue);
    expect(result, isTrue);
    expect(server.calls.map((r) => r.method), ['POST', 'PATCH']);
    expect(server.calls.last.path, '/saved-searches/37');
    expect(server.saved['name'], 'Requested private name');
    expect(server.saved['alert_frequency'], 'instant');
    expect(tester.takeException(), isNull);
  });

  testWidgets('validation conflict keeps the edit available for a successful retry', (tester) async {
    final server = await _server();
    server.rejectUpdate = true;
    bool returned = false;
    await _open(tester, server, existing: SavedPropertySearch.fromJson(server.saved),
      onResult: (_) => returned = true);
    await tester.enterText(find.byType(TextField), 'Retained correction');
    await _save(tester, 'حفظ التعديلات');
    expect(returned, isFalse);
    expect(server.saved['name'], 'Original private name');
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Retained correction');
    expect(find.textContaining('هذه الشروط محفوظة في بحث آخر.'), findsOneWidget);
    server.rejectUpdate = false;
    await _save(tester, 'حفظ التعديلات');
    expect(returned, isTrue);
    expect(server.saved['name'], 'Retained correction');
    expect(server.calls.length, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a pending save blocks further edits and duplicate submissions', (tester) async {
    final server = await _server();
    server.createStatus = 201;
    server.gate = Completer<void>();
    await _open(tester, server, onResult: (_) {});
    await tester.enterText(find.byType(TextField), 'Only submitted input');
    await tester.ensureVisible(find.text('حفظ البحث'));
    await tester.tap(find.text('حفظ البحث'));
    await tester.pump();
    // Let the asynchronous secure-token/options chain reach Dio while its
    // receipt stays held. pumpAndSettle cannot finish with a loading spinner.
    for (var attempt = 0; attempt < 10 && server.calls.isEmpty; attempt++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(server.calls.length, 1);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(tester.widgetList<RadioListTile<String>>(find.byType(RadioListTile<String>))
      .every((radio) => radio.onChanged == null), isTrue);
    server.gate!.complete();
    await tester.pumpAndSettle();
    expect(server.calls.length, 1);
    expect(server.saved['name'], 'Only submitted input');
    expect(tester.takeException(), isNull);
  });
}

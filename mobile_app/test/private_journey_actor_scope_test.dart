import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/network/api_client.dart';
import 'package:real_estate_mobile/features/account/data/account_safety_repository.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/agreements/data/agreement_repository.dart';
import 'package:real_estate_mobile/features/agreements/presentation/agreement_detail_screen.dart';
import 'package:real_estate_mobile/features/agreements/presentation/rental_contract_detail_screen.dart';
import 'package:real_estate_mobile/features/messages/data/message_repository.dart';
import 'package:real_estate_mobile/features/messages/presentation/conversation_screen.dart';
import 'package:real_estate_mobile/features/properties/data/favorites_repository.dart';

AuthUser _user(int id) => AuthUser.fromJson({'id': id, 'name': 'Synthetic actor $id',
  'account_status': 'active', 'phone_verified_at': '2026-10-25T00:00:00Z'});
class _Auth extends AuthController {
  @override
  Future<AuthUser?> build() async => _user(1);
  void change(int? id) => state = AsyncData(id == null ? null : _user(id));
}
class _Credentials implements AuthRepository {
  int? actor = 1;
  Completer<void>? gate;
  @override
  Future<Options> requiredAuthOptions() async {
    await gate?.future;
    return Options(headers: {'Authorization': 'Bearer synthetic-$actor'});
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}
class _Operations {
  const _Operations(this.write, this.read);
  final Future<dynamic> Function() write;
  final Future<dynamic> Function() read;
}
class _Harness {
  final auth = _Auth();
  final credentials = _Credentials();
  final dio = Dio(BaseOptions(baseUrl: 'https://synthetic.invalid/api'));
  final calls = <RequestOptions>[];
  late final ProviderContainer container;
  Completer<void>? receiptGate;
  final agreement = <String, dynamic>{'id': 37, 'reference': 'Synthetic agreement A',
    'property_id': 41, 'message_thread_id': 10, 'status': 'draft', 'can_revise': true,
    'current_revision': {'id': 3, 'agreed_amount': 100, 'currency': 'YER',
      'rent_amount': 100,
      'start_date': DateTime.now().add(const Duration(days: 7)).toIso8601String().substring(0, 10),
      'end_date': DateTime.now().add(const Duration(days: 372)).toIso8601String().substring(0, 10),
      'conditions': 'Private account A terms', 'additional_terms': 'Private account A terms'}};

  Future<void> start() async {
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) async {
      calls.add(request);
      await receiptGate?.future;
      if (request.headers['Authorization'] != 'Bearer synthetic-1' &&
          (request.path == '/agreements/37' || request.path == '/rental-contracts/37')) {
        handler.reject(DioException(requestOptions: request, type: DioExceptionType.badResponse,
          response: Response<void>(requestOptions: request, statusCode: 404)));
        return;
      }
      final Object data = switch (request.path) {
        '/favorites/ids' => {'property_ids': [41]},
        '/messages/threads' || '/agreements/mine' => <Object>[],
        '/account/deletion-request' => {'status': 'none'},
        '/users/41/messaging-block' => {'user_id': 41, 'blocked_by_me': true},
        '/messages/threads/10/messages' => {'id': 1, 'body': 'Private pending message'},
        '/messages/threads/10/agreement' || '/agreements/37' || '/rental-contracts/37' => agreement,
        '/messages/threads/10' => {'thread': {'id': 10, 'other_user': {'id': 41, 'name': 'Synthetic peer'}}, 'messages': <Object>[]},
        '/properties/41/favorite' => <String, dynamic>{},
        _ => throw StateError('Unexpected request ${request.method} ${request.path}'),
      };
      handler.resolve(Response<Map<String, dynamic>>(requestOptions: request, statusCode: 200, data: {'data': data}));
    }));
    container = ProviderContainer(overrides: [
      authControllerProvider.overrideWith(() => auth),
      authRepositoryProvider.overrideWithValue(credentials), dioProvider.overrideWithValue(dio),
    ]);
    await container.read(authControllerProvider.future);
  }
  _Operations operations(String kind) {
    switch (kind) {
      case 'favorite':
        container.listen(favoritesRepositoryProvider, (_, __) {});
        final repo = container.read(favoritesRepositoryProvider);
        return _Operations(() => repo.add(41), repo.favoriteIds);
      case 'message':
        container.listen(messageRepositoryProvider, (_, __) {});
        final repo = container.read(messageRepositoryProvider);
        return _Operations(() => repo.send(10, 'Private pending message'), repo.threads);
      case 'agreement':
        container.listen(agreementRepositoryProvider, (_, __) {});
        final repo = container.read(agreementRepositoryProvider);
        return _Operations(() => repo.startAgreement(10, {'agreed_amount': 100, 'currency': 'YER'}), repo.mine);
      default:
        container.listen(accountSafetyRepositoryProvider, (_, __) {});
        final repo = container.read(accountSafetyRepositoryProvider);
        return _Operations(() => repo.setBlocked(41, true), repo.deletionStatus);
    }
  }
  void change(int? id) { credentials.actor = id; auth.change(id); }
  void close() {
    if (receiptGate != null && !receiptGate!.isCompleted) receiptGate!.complete();
    if (credentials.gate != null && !credentials.gate!.isCompleted) credentials.gate!.complete();
    container.dispose(); dio.close(force: true);
  }
}
Future<_Harness> _harness() async {
  final h = _Harness(); await h.start(); addTearDown(h.close); return h;
}

Future<void> _page(WidgetTester tester, _Harness h, String kind) async {
  tester.view.physicalSize = const Size(412, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
  final screen = switch (kind) {
    'agreement' => const AgreementDetailScreen(agreementId: 37),
    'contract' => const RentalContractDetailScreen(contractId: 37),
    _ => const ConversationScreen(threadId: 10),
  };
  await tester.pumpWidget(UncontrolledProviderScope(container: h.container, child: MaterialApp(home: screen)));
  await tester.pumpAndSettle();
  if (kind == 'report') {
    await tester.tap(find.byTooltip('بلاغ'));
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
      'Private account A report');
  } else {
    final action = find.text(kind == 'agreement' ? 'اقتراح شروط جديدة' : 'اقتراح بنود جديدة');
    await tester.scrollUntilVisible(action, 300, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(action); await tester.tap(action); await tester.pumpAndSettle();
  }
}

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;
  for (final kind in ['favorite', 'message', 'agreement', 'safety']) {
    test('$kind retained mutation cannot use the next account token', () async {
      final h = await _harness(); final op = h.operations(kind); h.change(2);
      await expectLater(op.write(), throwsStateError); expect(h.calls, isEmpty);
    });
    test('$kind retained mutation expires across same-frame logout and same-ID login', () async {
      final h = await _harness(); final op = h.operations(kind); h.change(null); h.change(1);
      await expectLater(op.write(), throwsStateError); expect(h.calls, isEmpty);
    });
    test('$kind mutation rejects an account change during token lookup', () async {
      final h = await _harness(); final op = h.operations(kind);
      h.credentials.gate = Completer<void>();
      final rejected = expectLater(op.write(), throwsStateError);
      await Future<void>.delayed(Duration.zero); h.change(2); h.credentials.gate!.complete();
      await rejected; expect(h.calls, isEmpty);
    });
    test('$kind late private receipt is rejected after account change', () async {
      final h = await _harness(); final op = h.operations(kind); h.receiptGate = Completer<void>();
      final rejected = expectLater(op.read(), throwsStateError);
      for (var attempt = 0; attempt < 10 && h.calls.isEmpty; attempt++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(h.calls.length, 1); expect(h.calls.single.headers['Authorization'], 'Bearer synthetic-1');
      h.change(2); h.receiptGate!.complete(); await rejected;
    });
  }
  for (final kind in ['agreement', 'contract', 'report']) {
    for (final sameActor in [false, true]) {
      testWidgets('$kind private overlay is removed across account change (same actor=$sameActor)', (tester) async {
        final h = await _harness(); await _page(tester, h, kind);
        final text = kind == 'report' ? 'Private account A report' : 'Private account A terms';
        expect(find.text(text), findsWidgets);
        if (sameActor) h.change(null);
        h.change(sameActor ? 1 : 2); await tester.pumpAndSettle();
        expect(find.text(text), findsNothing);
        expect(find.text('تغيّر الحساب'), findsWidgets);
        expect(h.calls.where((r) => r.method != 'GET'), isEmpty);
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final kind in ['agreement', 'contract']) {
    testWidgets('$kind late date selection cannot update an expired form', (tester) async {
      final h = await _harness(); await _page(tester, h, kind);
      final start = find.descendant(of: find.byType(BottomSheet), matching:
        find.textContaining(kind == 'agreement' ? 'بداية الإيجار المقترحة' : 'بداية الإيجار:'));
      await tester.ensureVisible(start); await tester.tap(start); await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      h.change(2); await tester.pumpAndSettle();
      expect(find.text('Private account A terms'), findsNothing);
      await tester.tap(find.text('OK')); await tester.pumpAndSettle();
      expect(find.text('تغيّر الحساب'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}

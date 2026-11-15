import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:real_estate_mobile/core/local/stage6_secure_session_store.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/account/presentation/actor_scoped_page.dart';

import 'support/phase23_widget_tools.dart';

class _Auth extends AuthController {
  @override
  Future<AuthUser?> build() async => _user();
  void replaceSession() {
    Stage6SecureSessionStore.instance.beginSessionChange();
    state = AsyncData(_user());
  }
  AuthUser _user() => AuthUser.fromJson({'id': 6, 'name': 'Synthetic account', 'roles': ['user']});
}

class _DelayedAuth extends _Auth {
  final initial = Completer<AuthUser?>();
  @override
  Future<AuthUser?> build() => initial.future;
  void metadataRefresh() => state = AsyncData(_user());
}

void main() {
  phase23WidgetTest('unbound page binds epoch with the first resolved actor after auth bootstrap', (tester) async {
    final auth = _DelayedAuth();
    final container = ProviderContainer(overrides: [authControllerProvider.overrideWith(() => auth)]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
      child: MaterialApp(home: ActorBoundPage(title: 'Private page',
        builder: (_) => const Text('Resolved private content')))));
    expect(find.text('Resolved private content'), findsNothing);
    Stage6SecureSessionStore.instance.beginSessionChange();
    auth.initial.complete(auth._user());
    await tester.pumpAndSettle();
    expect(find.text('Resolved private content'), findsOneWidget);
    auth.metadataRefresh();
    await tester.pumpAndSettle();
    expect(find.text('Resolved private content'), findsOneWidget);
    expect(find.text('تغيّر الحساب'), findsNothing);
    auth.replaceSession();
    await tester.pumpAndSettle();
    expect(find.text('Resolved private content'), findsNothing);
    expect(find.text('تغيّر الحساب'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final origin in ['actor', 'epoch', 'both']) {
    phase23WidgetTest('explicit $origin origin stays pinned while initial auth resolves', (tester) async {
      final auth = _DelayedAuth();
      final container = ProviderContainer(overrides: [authControllerProvider.overrideWith(() => auth)]);
      addTearDown(container.dispose);
      final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
      await tester.pumpWidget(UncontrolledProviderScope(container: container,
        child: MaterialApp(home: ActorBoundPage(title: 'Private origin',
          actorId: origin == 'epoch' ? null : 6,
          sessionEpoch: origin == 'actor' ? null : epoch,
          builder: (_) => const Text('Preloaded private content')))));
      Stage6SecureSessionStore.instance.beginSessionChange();
      auth.initial.complete(auth._user());
      await tester.pumpAndSettle();
      expect(find.text('Preloaded private content'), findsNothing);
      expect(find.text('تغيّر الحساب'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final sheet in [false, true]) {
    final surface = sheet ? 'sheet' : 'dialog';
    for (final beforeFirstFrame in [false, true]) {
      phase23WidgetTest('$surface fences session change ${beforeFirstFrame ? 'before first frame' : 'after closing with a value'}', (tester) async {
        final container = ProviderContainer(overrides: [authControllerProvider.overrideWith(_Auth.new)]);
        await container.read(authControllerProvider.future);
        addTearDown(container.dispose);
        String? result = 'not finished';
        final auth = container.read(authControllerProvider.notifier) as _Auth;
        await tester.pumpWidget(UncontrolledProviderScope(container: container,
          child: MaterialApp(home: Consumer(builder: (context, ref, _) => Scaffold(
            body: TextButton(onPressed: () async {
              Widget content(BuildContext dialog) => TextButton(
                onPressed: () {
                  Navigator.pop(dialog, 'private result');
                  if (!beforeFirstFrame) auth.replaceSession();
                }, child: const Text('Private session action'));
              final future = sheet ? showActorModalBottomSheet<String>(
                context: context, ref: ref, builder: content)
                : showActorDialog<String>(context: context, ref: ref,
                    builder: (dialog) => AlertDialog(content: content(dialog)));
              if (beforeFirstFrame) auth.replaceSession();
              result = await future;
            }, child: const Text('Open')))))));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        if (beforeFirstFrame) {
          expect(find.text('Private session action'), findsNothing);
          expect(find.text('تغيّر الحساب'), findsOneWidget);
          await tester.tap(find.text('إغلاق'));
        } else {
          await tester.tap(find.text('Private session action'));
        }
        await tester.pumpAndSettle();
        expect(result, isNull);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

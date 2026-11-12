import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/local/stage6_secure_session_store.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/discovery/data/ai_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_search_session.dart';
import 'package:real_estate_mobile/features/discovery/data/smart_search_session.dart';
import 'package:real_estate_mobile/features/discovery/domain/smart_search_filters.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';

import 'support/wave3_fakes.dart';

AuthUser _actor(int id) => AuthUser.fromJson({
      'id': id,
      'name': 'Synthetic account $id',
      'account_status': 'active',
    });

class _SwitchingAuth extends AuthController {
  @override
  Future<AuthUser?> build() async => _actor(1);

  void replace(AuthUser? actor, {bool newSession = true}) {
    if (newSession) Stage6SecureSessionStore.instance.beginSessionChange();
    state = AsyncData(actor);
  }
}

class _UncancelableResults extends Wave3PropertiesFake {
  final pending = Completer<(List<PropertySummary>, bool)>();
  CancelToken? oldTransfer;

  @override
  Future<(List<PropertySummary>, bool)> searchListings(
      Map<String, dynamic> filters,
      {int page = 1,
      CancelToken? cancelToken,
      bool refresh = false}) {
    if (filters['search'] == 'old account query') {
      oldTransfer = cancelToken;
      // A completed transport/decoder may ignore cancellation. The session
      // must independently reject its result after the account boundary.
      return pending.future;
    }
    return Future.value(([wave3Property(22)], false));
  }
}

Future<ProviderContainer> _scope(
    _SwitchingAuth auth, Wave3AiFake ai, PropertyRepository properties) async {
  final scope = ProviderContainer(overrides: [
    authControllerProvider.overrideWith(() => auth),
    aiRepositoryProvider.overrideWithValue(ai),
    propertyRepositoryProvider.overrideWithValue(properties),
  ]);
  addTearDown(scope.dispose);
  await scope.read(authControllerProvider.future);
  return scope;
}

void main() {
  test('late AI delivery cannot set filters or request results for another account',
      () async {
    final release = Completer<Map<String, dynamic>>();
    final ai = Wave3AiFake()..onRefine = (_, __, ___) => release.future;
    final properties = Wave3PropertiesFake();
    final auth = _SwitchingAuth();
    final scope = await _scope(auth, ai, properties);
    final old = scope.read(smartSearchSessionProvider.notifier);
    final pending = old.interpret('old account input');
    final oldRevision = ai.requests.single.revision;

    auth.replace(_actor(2));
    final current = scope.read(smartSearchSessionProvider.notifier);
    current.setDraftText('new account input');
    release.complete({
      'revision': oldRevision,
      'filters': {'search': 'old account result', 'type': 'apartment'},
    });
    await pending;

    expect(scope.read(smartSearchSessionProvider).draftText, 'new account input');
    expect(scope.read(smartSearchSessionProvider).lastRequest, isEmpty);
    expect(scope.read(smartSearchSessionProvider).filters.values, isEmpty);
    expect(scope.read(smartSearchSessionProvider).rows, isEmpty);
    expect(properties.queries, isEmpty);
  });

  test('an old AI error cannot become the next account error', () async {
    final release = Completer<Map<String, dynamic>>();
    final ai = Wave3AiFake()..onRefine = (_, __, ___) => release.future;
    final auth = _SwitchingAuth();
    final scope = await _scope(auth, ai, Wave3PropertiesFake());
    final pending = scope.read(smartSearchSessionProvider.notifier)
        .interpret('old account input');
    auth.replace(_actor(2));
    scope.read(smartSearchSessionProvider);
    release.completeError(StateError('Old request failed'));
    await pending;
    expect(scope.read(smartSearchSessionProvider).aiError, isNull);
    expect(scope.read(smartSearchSessionProvider).lastRequest, isEmpty);
  });

  for (final (name, provider) in [
    ('assistant', smartSearchSessionProvider),
    ('home', homeSearchResultsProvider),
    ('map', marketplaceMapResultsProvider),
  ]) {
    test('old results are discarded after a replacement session for $name',
        () async {
      final auth = _SwitchingAuth();
      final properties = _UncancelableResults();
      final scope = await _scope(auth, Wave3AiFake(), properties);
      final old = scope.read(provider.notifier);
      final pending = old.replaceManually(
          SmartSearchFilters.fromMap({'search': 'old account query'}));
      auth.replace(_actor(2));
      final current = scope.read(provider.notifier);
      expect(properties.oldTransfer?.isCancelled, isTrue);
      await current.replaceManually(
          SmartSearchFilters.fromMap({'search': 'new account query'}));
      properties.pending.complete(([wave3Property(11)], false));
      await pending;

      expect(scope.read(provider).filters.values['search'], 'new account query');
      expect(scope.read(provider).rows.map((row) => row.id), [22]);
    });

    test('same actor renewed session clears old search state for $name',
        () async {
      final auth = _SwitchingAuth();
      final scope = await _scope(auth, Wave3AiFake(), Wave3PropertiesFake());
      final old = scope.read(provider.notifier);
      old.setDraftText('previous session input');
      await old.replaceManually(
          SmartSearchFilters.fromMap({'search': 'previous session query'}));
      auth.replace(_actor(1));

      expect(scope.read(provider).draftText, isEmpty);
      expect(scope.read(provider).filters.values, isEmpty);
      expect(scope.read(provider).rows, isEmpty);
    });

    test('same actor metadata refresh retains current search for $name',
        () async {
      final auth = _SwitchingAuth();
      final scope = await _scope(auth, Wave3AiFake(), Wave3PropertiesFake());
      final session = scope.read(provider.notifier);
      session.setDraftText('retained input');
      await session.replaceManually(
          SmartSearchFilters.fromMap({'search': 'retained query'}));
      auth.replace(_actor(1), newSession: false);

      expect(scope.read(provider).draftText, 'retained input');
      expect(scope.read(provider).filters.values['search'], 'retained query');
      expect(scope.read(provider).rows.map((row) => row.id), [11]);
    });
  }

  for (final fails in [false, true]) {
    test('epoch-only AI ${fails ? 'error' : 'success'} leaves unchanged actor UI retryable',
        () async {
      final release = Completer<Map<String, dynamic>>();
      final ai = Wave3AiFake()..onRefine = (_, __, ___) => release.future;
      final properties = Wave3PropertiesFake();
      final session = SmartSearchSession(ai, properties);
      addTearDown(session.dispose);
      session.setDraftText('retained input');
      final pending = session.interpret('retained input');
      expect(session.snapshot.interpreting, isTrue);
      Stage6SecureSessionStore.instance.beginSessionChange();
      if (fails) {
        release.completeError(StateError('obsolete AI error'));
      } else {
        release.complete({'revision': 0, 'filters': {'search': 'obsolete result'}});
      }
      await pending;
      expect(session.snapshot.interpreting, isFalse);
      expect(session.snapshot.aiError, isNull);
      expect(session.snapshot.draftText, 'retained input');
      expect(session.snapshot.filters.values, isEmpty);
      expect(properties.queries, isEmpty);

      // The UI enables Send from interpreting=false; do not reset/replace the
      // session as a workaround before issuing its next normal interpretation.
      ai.onRefine = (_, __, revision) async => {
        'revision': revision, 'filters': {'search': 'fresh result'},
      };
      await session.interpret('fresh input');
      expect(session.snapshot.interpreting, isFalse);
      expect(session.snapshot.filters.values['search'], 'fresh result');
      expect(session.snapshot.rows.map((row) => row.id), [11]);
    });

    test('epoch-only results ${fails ? 'error' : 'success'} allow the normal Retry action',
        () async {
      final release = Completer<(List<PropertySummary>, bool)>();
      var calls = 0;
      final properties = Wave3PropertiesFake()
        ..onSearch = (_, __) => ++calls == 1
            ? release.future : Future.value(([wave3Property(22)], false));
      final session = SmartSearchSession(Wave3AiFake(), properties);
      addTearDown(session.dispose);
      final pending = session.search();
      expect(session.snapshot.loading, isTrue);
      Stage6SecureSessionStore.instance.beginSessionChange();
      if (fails) {
        release.completeError(StateError('obsolete results error'));
      } else {
        release.complete(([wave3Property(11)], false));
      }
      await pending;
      expect(session.snapshot.loading, isFalse);
      expect(session.snapshot.resultsError, isNull);
      expect(session.snapshot.rows, isEmpty);

      await session.retryResults();
      expect(calls, 2);
      expect(session.snapshot.loading, isFalse);
      expect(session.snapshot.rows.map((row) => row.id), [22]);
    });

    test('obsolete AI ${fails ? 'error' : 'success'} cannot clear a newer request busy state',
        () async {
      final oldReply = Completer<Map<String, dynamic>>();
      final newReply = Completer<Map<String, dynamic>>();
      final ai = Wave3AiFake()
        ..onRefine = (text, _, __) =>
            text == 'old input' ? oldReply.future : newReply.future;
      final session = SmartSearchSession(ai, Wave3PropertiesFake());
      addTearDown(session.dispose);
      final old = session.interpret('old input');
      Stage6SecureSessionStore.instance.beginSessionChange();
      final current = session.interpret('new input');
      if (fails) {
        oldReply.completeError(StateError('obsolete AI error'));
      } else {
        oldReply.complete({'revision': 0, 'filters': {'search': 'obsolete'}});
      }
      await old;
      expect(session.snapshot.interpreting, isTrue);
      expect(session.snapshot.aiError, isNull);
      expect(session.snapshot.filters.values, isEmpty);
      newReply.complete({'revision': 0, 'filters': {'search': 'fresh'}});
      await current;
      expect(session.snapshot.interpreting, isFalse);
      expect(session.snapshot.filters.values['search'], 'fresh');
    });

    test('obsolete results ${fails ? 'error' : 'success'} cannot clear a newer request busy state',
        () async {
      final oldReply = Completer<(List<PropertySummary>, bool)>();
      final newReply = Completer<(List<PropertySummary>, bool)>();
      var calls = 0;
      final properties = Wave3PropertiesFake()
        ..onSearch = (_, __) => ++calls == 1 ? oldReply.future : newReply.future;
      final session = SmartSearchSession(Wave3AiFake(), properties);
      addTearDown(session.dispose);
      final old = session.search();
      Stage6SecureSessionStore.instance.beginSessionChange();
      final current = session.search();
      if (fails) {
        oldReply.completeError(StateError('obsolete results error'));
      } else {
        oldReply.complete(([wave3Property(11)], false));
      }
      await old;
      expect(session.snapshot.loading, isTrue);
      expect(session.snapshot.resultsError, isNull);
      expect(session.snapshot.rows, isEmpty);
      newReply.complete(([wave3Property(22)], false));
      await current;
      expect(session.snapshot.loading, isFalse);
      expect(session.snapshot.rows.map((row) => row.id), [22]);
    });
  }
}

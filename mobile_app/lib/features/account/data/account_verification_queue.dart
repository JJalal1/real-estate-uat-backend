import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/local/stage6_secure_session_store.dart';
import '../../../core/network/api_error_message.dart';
import '../domain/account_verification.dart';
import 'auth_controller.dart';

// Both verification entry points share the same page/session rules while
// retaining their existing models, filters and review permissions.
VerificationQueue<T> createVerificationQueue<T>(Ref ref, {
  required Future<AccountVerificationPage<T>> Function(int) load,
  required int Function(T) idOf,
  required void Function() invalidate,
}) {
  final session = ref.watch(authControllerProvider.select((state) => (
    state.asData?.value?.id, Stage6SecureSessionStore.instance.sessionEpoch)));
  var alive = true;
  ref.onDispose(() => alive = false);
  ref.listen(authControllerProvider, (_, next) {
    if (session == (next.asData?.value?.id, Stage6SecureSessionStore.instance.sessionEpoch)) return;
    alive = false;
    invalidate();
  });
  return VerificationQueue<T>(load: load, idOf: idOf,
    signedIn: session.$1 != null,
    isCurrent: () => alive && session == (
      ref.read(authControllerProvider).asData?.value?.id,
      Stage6SecureSessionStore.instance.sessionEpoch),
    invalidate: invalidate);
}

class VerificationQueueState<T> {
  const VerificationQueueState({this.page, this.loading = false,
    this.loadingMore = false, this.error, this.pageError});
  final AccountVerificationPage<T>? page;
  final bool loading;
  final bool loadingMore;
  final Object? error;
  final Object? pageError;
  List<T> get items => page?.items ?? const [];
}

class VerificationQueue<T> extends StateNotifier<VerificationQueueState<T>> {
  VerificationQueue({required Future<AccountVerificationPage<T>> Function(int) load,
    required int Function(T) idOf, required bool signedIn,
    required bool Function() isCurrent, required void Function() invalidate})
      : _load = load, _idOf = idOf, _isCurrent = isCurrent, _invalidate = invalidate,
        super(VerificationQueueState<T>(loading: signedIn)) {
    if (signedIn) unawaited(refresh());
  }
  final Future<AccountVerificationPage<T>> Function(int) _load;
  final int Function(T) _idOf;
  final bool Function() _isCurrent;
  final void Function() _invalidate;
  int _request = 0;

  void _resetSession() {
    state = VerificationQueueState<T>(loading: true);
    _invalidate();
  }

  Future<void> refresh() => _fetch(1);

  Future<void> loadMore() async {
    if (!mounted) return;
    if (!_isCurrent()) { _resetSession(); return; }
    if (state.loading || state.loadingMore || state.error != null ||
        !(state.page?.hasMore ?? false)) { return; }
    await _fetch(state.page!.currentPage + 1, append: true);
  }

  Future<void> _fetch(int page, {bool append = false}) async {
    if (!mounted) return;
    if (!_isCurrent()) { _resetSession(); return; }
    final request = ++_request;
    final previous = state.page;
    state = VerificationQueueState<T>(page: previous, loading: !append, loadingMore: append);
    bool current() {
      if (!mounted || request != _request) return false;
      if (_isCurrent()) return true;
      _resetSession();
      return false;
    }
    try {
      final result = await _load(page);
      if (!current()) return;
      final items = <int, T>{
        if (append && previous != null)
          for (final item in previous.items) _idOf(item): item,
        for (final item in result.items) _idOf(item): item,
      }.values.toList(growable: false);
      state = VerificationQueueState<T>(page: AccountVerificationPage<T>(items: items,
        currentPage: result.currentPage, lastPage: result.lastPage, total: result.total));
    } catch (error) {
      if (!current()) return;
      final retained = isTransientApiFailure(error) ? previous : null;
      state = VerificationQueueState<T>(page: retained,
        error: append && retained != null ? null : error,
        pageError: append && retained != null ? error : null);
    }
  }
}

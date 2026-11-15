import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/local/stage6_secure_session_store.dart';
import '../../../core/network/api_error_message.dart';
import 'auth_controller.dart';

class PrivateCollectionPage<T> {
  const PrivateCollectionPage({required this.items, required this.currentPage,
    required this.lastPage, this.total});
  final List<T> items;
  final int currentPage, lastPage;
  final int? total;
  bool get hasMore => currentPage < lastPage;

  factory PrivateCollectionPage.parse(Map<String, dynamic> body,
      {required int requestedPage, required T Function(Map<String, dynamic>) parse}) {
    final data = body['data'], meta = body['meta'];
    if (data is! List || meta is! Map<String, dynamic> ||
        meta['current_page'] is! int || meta['current_page'] != requestedPage ||
        meta['last_page'] is! int || (meta['last_page'] as int) < 1 ||
        (meta['last_page'] as int) < requestedPage ||
        data.any((row) => row is! Map<String, dynamic>)) {
      throw StateError('INVALID_PRIVATE_PAGE');
    }
    return PrivateCollectionPage(items: List<T>.unmodifiable(
      data.cast<Map<String, dynamic>>().map(parse)), currentPage: requestedPage,
      lastPage: meta['last_page'] as int,
      total: meta['total'] is int ? meta['total'] as int : null);
  }
}

class PrivateCollectionState<T> {
  const PrivateCollectionState({this.page, this.loading = false,
    this.loadingMore = false, this.error, this.pageError});
  final PrivateCollectionPage<T>? page;
  final bool loading, loadingMore;
  final Object? error, pageError;
  List<T> get items => page?.items ?? const [];
}

PrivateCollectionController<T> accountCollection<T>(Ref ref, {
  required Future<PrivateCollectionPage<T>> Function(int) load,
  required int Function(T) idOf,
}) {
  final session = ref.watch(authControllerProvider.select((state) => (
    state.asData?.value?.id, Stage6SecureSessionStore.instance.sessionEpoch,
  )));
  var alive = true;
  ref.onDispose(() => alive = false);
  ref.listen(authControllerProvider, (_, next) {
    if (session == (next.asData?.value?.id,
        Stage6SecureSessionStore.instance.sessionEpoch)) { return; }
    alive = false;
    ref.invalidateSelf();
  });
  return PrivateCollectionController(load: load, idOf: idOf,
    signedIn: session.$1 != null,
    isCurrent: () => alive && session.$2 == Stage6SecureSessionStore.instance.sessionEpoch,
    onSessionChange: ref.invalidateSelf);
}

class PrivateCollectionController<T> extends StateNotifier<PrivateCollectionState<T>> {
  PrivateCollectionController({required Future<PrivateCollectionPage<T>> Function(int) load,
    required int Function(T) idOf, bool signedIn = true,
    bool Function()? isCurrent, void Function()? onSessionChange})
    : _load = load, _idOf = idOf, _isCurrent = isCurrent ?? (() => true),
      _onSessionChange = onSessionChange ?? (() {}),
      super(signedIn ? PrivateCollectionState<T>(loading: true)
        : PrivateCollectionState<T>(error: StateError('AUTH_REQUIRED'))) {
    if (signedIn) { unawaited(refresh()); }
  }
  final Future<PrivateCollectionPage<T>> Function(int) _load;
  final int Function(T) _idOf;
  final bool Function() _isCurrent;
  final void Function() _onSessionChange;
  int _generation = 0;

  Future<void> refresh() => _fetch(1);
  Future<void> loadMore() async {
    if (!mounted) { return; }
    if (!_isCurrent()) { _reset(); return; }
    if (state.loading || state.loadingMore || state.error != null ||
        !(state.page?.hasMore ?? false)) { return; }
    await _fetch(state.page!.currentPage + 1, append: true);
  }
  void _reset() {
    _generation++;
    state = PrivateCollectionState<T>(error: StateError('ACCOUNT_CHANGED'));
    _onSessionChange();
  }
  Future<void> _fetch(int page, {bool append = false}) async {
    if (!mounted) { return; }
    if (!_isCurrent()) { _reset(); return; }
    final generation = ++_generation, previous = state.page;
    state = PrivateCollectionState(page: previous, loading: !append, loadingMore: append);
    bool current() {
      if (!mounted || generation != _generation) { return false; }
      if (_isCurrent()) { return true; }
      _reset(); return false;
    }
    try {
      final result = await _load(page);
      if (!current()) { return; }
      final items = <int, T>{
        if (append && previous != null) for (final item in previous.items) _idOf(item): item,
        for (final item in result.items) _idOf(item): item,
      }.values.toList(growable: false);
      state = PrivateCollectionState(page: PrivateCollectionPage(items: items,
        currentPage: result.currentPage, lastPage: result.lastPage, total: result.total));
    } catch (error) {
      if (!current()) { return; }
      final retained = isTransientApiFailure(error) ? previous : null;
      state = PrivateCollectionState(page: retained,
        error: append && retained != null ? null : error,
        pageError: append && retained != null ? error : null);
    }
  }
}

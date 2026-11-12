import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/local/stage6_secure_session_store.dart';
import '../../../core/network/api_error_message.dart';
import '../../account/data/auth_controller.dart';
import '../../account/data/account_request_scope.dart';
import '../domain/my_listings_page.dart';
import '../domain/property_details.dart';
import 'property_repository.dart';

final myListingsPagesProvider = StateNotifierProvider.autoDispose<
    MyListingsPagesController, MyListingsPagesState>((ref) {
  ref.watch(propertyDataRevisionProvider);
  final session = ref.watch(authControllerProvider.select((state) => (
    state.asData?.value?.id, Stage6SecureSessionStore.instance.sessionEpoch,
  )));
  var alive = true;
  ref.onDispose(() => alive = false);
  ref.listen(authControllerProvider, (_, next) {
    if (session == (next.asData?.value?.id,
        Stage6SecureSessionStore.instance.sessionEpoch)) return;
    alive = false;
    ref.invalidateSelf();
  });
  final repository = ref.watch(propertyRepositoryProvider);
  final requestScope = ref.watch(accountRequestScopeProvider);
  return MyListingsPagesController(
    load: (page) => repository.myListingsPage(page: page, requestScope: requestScope),
    signedIn: session.$1 != null,
    isCurrent: () => alive && session == (
      ref.read(authControllerProvider).asData?.value?.id,
      Stage6SecureSessionStore.instance.sessionEpoch,
    ),
    onSessionChange: ref.invalidateSelf,
  );
});

class MyListingsPagesState {
  const MyListingsPagesState({this.page, this.loading = false,
    this.loadingMore = false, this.error, this.pageError});

  final MyListingsPage? page;
  final bool loading;
  final bool loadingMore;
  final Object? error;
  final Object? pageError;
  List<PropertyDetails> get items => page?.items ?? const [];
}

class MyListingsPagesController extends StateNotifier<MyListingsPagesState> {
  MyListingsPagesController({required Future<MyListingsPage> Function(int) load,
    required bool signedIn, required bool Function() isCurrent,
    required void Function() onSessionChange})
      : _load = load, _isCurrent = isCurrent,
        _onSessionChange = onSessionChange,
        super(signedIn ? const MyListingsPagesState(loading: true)
          : MyListingsPagesState(error: StateError('AUTH_REQUIRED'))) {
    if (signedIn) unawaited(refresh());
  }

  final Future<MyListingsPage> Function(int) _load;
  final bool Function() _isCurrent;
  final void Function() _onSessionChange;
  int _request = 0;

  Future<void> refresh() => _fetchPage(1);

  Future<void> loadMore() async {
    if (!mounted) return;
    if (!_isCurrent()) { _resetSession(); return; }
    if (state.loading || state.loadingMore || state.error != null ||
        !(state.page?.hasMore ?? false)) return;
    await _fetchPage(state.page!.currentPage + 1, append: true);
  }

  void _resetSession() {
    ++_request;
    state = const MyListingsPagesState(loading: true);
    _onSessionChange();
  }

  Future<void> _fetchPage(int page, {bool append = false}) async {
    if (!mounted) return;
    if (!_isCurrent()) { _resetSession(); return; }
    final request = ++_request;
    final previous = state.page;
    state = MyListingsPagesState(page: previous, loading: !append, loadingMore: append);
    bool current() {
      if (!mounted || request != _request) return false;
      if (_isCurrent()) return true;
      _resetSession();
      return false;
    }
    try {
      final result = await _load(page);
      if (!current()) return;
      final items = <int, PropertyDetails>{
        if (append && previous != null)
          for (final item in previous.items) item.id: item,
        for (final item in result.items) item.id: item,
      }.values.toList(growable: false);
      state = MyListingsPagesState(page: MyListingsPage(items: items,
        currentPage: result.currentPage, lastPage: result.lastPage, total: result.total));
    } catch (error) {
      if (!current()) return;
      final retained = isTransientApiFailure(error) ? previous : null;
      state = MyListingsPagesState(page: retained,
        error: append && retained != null ? null : error,
        pageError: append && retained != null ? error : null);
    }
  }
}

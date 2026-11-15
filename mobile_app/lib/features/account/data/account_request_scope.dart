import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';
import 'auth_repository.dart';

/// A retained repository must never acquire the next account's bearer token.
final accountRequestScopeProvider = Provider<AccountRequestScope>(createAccountRequestScope);

// Nested scopes that replace authentication can reuse the same real fence.
AccountRequestScope createAccountRequestScope(Ref ref) {
  final actor = ref.watch(authControllerProvider.select((s) => s.asData?.value?.id));
  var alive = true;
  ref.listen(authControllerProvider.select((s) => s.asData?.value?.id), (_, next) {
    if (next != actor) alive = false;
  });
  ref.onDispose(() => alive = false);
  return AccountRequestScope(ref.watch(authRepositoryProvider),
    // The listener revokes this snapshot synchronously. A retained repository
    // must not read through a Ref whose dependency is awaiting a rebuild.
    isCurrent: () => alive && actor != null);
}

class AccountRequestScope {
  const AccountRequestScope(this._auth, {required bool Function() isCurrent})
    : _isCurrent = isCurrent;
  final AuthRepository _auth;
  final bool Function() _isCurrent;
  bool get isCurrent => _isCurrent();

  void verify() {
    if (!isCurrent) throw StateError('ACCOUNT_CHANGED');
  }

  Future<Options> options() async {
    verify();
    final options = await _auth.requiredAuthOptions();
    // Secure storage is asynchronous; the session may change while it is read.
    verify();
    return options;
  }
}

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';
import 'auth_repository.dart';

/// A retained repository must never acquire the next account's bearer token.
final accountRequestScopeProvider = Provider<AccountRequestScope>((ref) {
  final actor = ref.watch(authControllerProvider.select((s) => s.asData?.value?.id));
  var alive = true;
  ref.onDispose(() => alive = false);
  return AccountRequestScope(ref.watch(authRepositoryProvider),
    isCurrent: () => alive && actor != null &&
      ref.read(authControllerProvider).asData?.value?.id == actor);
});

class AccountRequestScope {
  const AccountRequestScope(this._auth, {required bool Function() isCurrent})
    : _isCurrent = isCurrent;
  final AuthRepository _auth;
  final bool Function() _isCurrent;

  void verify() {
    if (!_isCurrent()) throw StateError('ACCOUNT_CHANGED');
  }

  Future<Options> options() async {
    verify();
    final options = await _auth.requiredAuthOptions();
    // Secure storage is asynchronous; the session may change while it is read.
    verify();
    return options;
  }
}

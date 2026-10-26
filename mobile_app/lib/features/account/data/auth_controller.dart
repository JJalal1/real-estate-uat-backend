import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/auth_user.dart';
import 'auth_repository.dart';
import '../../messages/data/push_registration_repository.dart';
import '../../../core/local/stage6_secure_session_store.dart';

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthUser?>(AuthController.new);

final whatsAppAuthPendingProvider =
    StateProvider<WhatsAppAuthPending?>((ref) => null);

class AuthController extends AsyncNotifier<AuthUser?> {
  AuthRepository get _repository => ref.read(authRepositoryProvider);
  int _revision = 0;
  Future<void>? _logoutOperation;

  int _beginChange() {
    if (_logoutOperation != null) throw StateError('SESSION_CHANGE_IN_PROGRESS');
    return ++_revision;
  }

  void _requireCurrent(int revision) {
    if (revision != _revision) throw StateError('ACCOUNT_CHANGED');
  }

  @override
  Future<AuthUser?> build() async {
    ref.onDispose(() => _revision++);
    final revision = _revision;
    AuthUser? user;
    try {
      user = await _repository.restoreSession();
    } catch (_) {
      if (revision != _revision) return state.asData?.value;
      rethrow;
    }
    if (revision != _revision) return state.asData?.value;
    if (user != null) _syncPushIfGranted();
    return user;
  }

  void _syncPushIfGranted() {
    unawaited(() async {
      try {
        await ref.read(pushRegistrationRepositoryProvider).syncIfGranted();
      } catch (_) {
        // Push registration is best-effort and must not block authentication.
      }
    }());
  }

  Future<WhatsAppAuthPending> startWhatsApp({required String phone, String? name}) async {
    final revision = _beginChange();
    final pending = await _repository.startWhatsApp(phone: phone, name: name);
    _requireCurrent(revision);
    ref.read(whatsAppAuthPendingProvider.notifier).state = pending;
    return pending;
  }

  Future<WhatsAppAuthPending> startEmail({required String email, String? name}) async {
    final revision = _beginChange();
    final pending = await _repository.startEmail(email: email, name: name);
    _requireCurrent(revision);
    ref.read(whatsAppAuthPendingProvider.notifier).state = pending;
    return pending;
  }

  Future<void> requestEmailVerification() async {
    final revision = _revision;
    await _repository.requestEmailVerification();
    _requireCurrent(revision);
  }
  Future<void> verifyEmail(String code) async {
    final revision = _beginChange();
    final user = await _repository.verifyEmail(code);
    _requireCurrent(revision);
    state = AsyncData(user);
    _syncPushIfGranted();
  }

  Future<AuthResult> verifyWhatsApp(String code) async {
    final revision = _beginChange();
    final pending = ref.read(whatsAppAuthPendingProvider);
    if (pending == null) throw StateError('WHATSAPP_AUTH_NOT_STARTED');
    final result = await _repository.verifyWhatsApp(pending, code);
    _requireCurrent(revision);
    ref.read(whatsAppAuthPendingProvider.notifier).state = null;
    state = AsyncData(result.user);
    _syncPushIfGranted();
    return result;
  }

  Future<AuthResult> register({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    final revision = _beginChange();
    final result = await _repository.register(
      name: name,
      email: email,
      phone: phone,
      password: password,
    );
    _requireCurrent(revision);
    state = AsyncData(result.user);
    _syncPushIfGranted();
    return result;
  }

  Future<AuthResult> login({
    required String login,
    required String password,
  }) async {
    final revision = _beginChange();
    final result = await _repository.login(login: login, password: password);
    _requireCurrent(revision);
    state = AsyncData(result.user);
    _syncPushIfGranted();
    return result;
  }

  Future<void> logout() {
    final running = _logoutOperation;
    if (running != null) return running;
    final operation = _performLogout().whenComplete(() => _logoutOperation = null);
    _logoutOperation = operation;
    return operation;
  }

  Future<void> _performLogout() async {
    final revision = ++_revision;
    Stage6SecureSessionStore.instance.beginSessionChange();
    try {
      try {
        await ref.read(pushRegistrationRepositoryProvider).unregister();
      } catch (_) {
        // Push cleanup cannot block logout.
      }
      _requireCurrent(revision);
      await _repository.logout();
    } finally {
      // The repository clears the local token even when the server is offline.
      // Keep the visible session and pending login state consistent with it.
      if (revision == _revision) {
        ref.read(whatsAppAuthPendingProvider.notifier).state = null;
        state = const AsyncData(null);
      }
    }
  }

  Future<String?> requestPhoneVerification() async {
    final revision = _revision;
    final code = await _repository.requestPhoneVerification();
    _requireCurrent(revision);
    return code;
  }

  Future<void> verifyPhone(String code) async {
    final revision = _beginChange();
    final user = await _repository.verifyPhone(code);
    _requireCurrent(revision);
    state = AsyncData(user);
  }

  Future<void> completeProfile(String name) async {
    final revision = _beginChange();
    final user = await _repository.completeProfile(name);
    _requireCurrent(revision);
    state = AsyncData(user);
  }

  Future<void> updateProfile({
    required String name,
    required String phone,
    String? email,
  }) async {
    final revision = _beginChange();
    final user = await _repository.updateProfile(name: name, phone: phone, email: email);
    _requireCurrent(revision);
    state = AsyncData(user);
  }

  Future<String?> requestPasswordReset(String login) =>
      _repository.requestPasswordReset(login);

  Future<void> resetPassword({
    required String login,
    required String code,
    required String password,
  }) async {
    final revision = _beginChange();
    await _repository.resetPassword(
      login: login,
      code: code,
      password: password,
    );
    _requireCurrent(revision);
    ref.read(whatsAppAuthPendingProvider.notifier).state = null;
    state = const AsyncData(null);
  }

  Future<void> refresh() async {
    if (_logoutOperation != null) return;
    final revision = _beginChange();
    AuthUser? user;
    try {
      user = await _repository.restoreSession();
    } catch (_) {
      if (revision != _revision) return;
      rethrow;
    }
    if (revision != _revision) return;
    state = AsyncData(user);
    if (state.asData?.value != null) _syncPushIfGranted();
  }
}


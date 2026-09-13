import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/auth_user.dart';
import 'auth_repository.dart';

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthUser?>(AuthController.new);

final whatsAppAuthPendingProvider =
    StateProvider<WhatsAppAuthPending?>((ref) => null);

class AuthController extends AsyncNotifier<AuthUser?> {
  AuthRepository get _repository => ref.read(authRepositoryProvider);

  @override
  Future<AuthUser?> build() => _repository.restoreSession();

  Future<WhatsAppAuthPending> startWhatsApp({required String phone}) async {
    final pending = await _repository.startWhatsApp(phone: phone);
    ref.read(whatsAppAuthPendingProvider.notifier).state = pending;
    return pending;
  }

  Future<AuthResult> verifyWhatsApp(String code) async {
    final pending = ref.read(whatsAppAuthPendingProvider);
    if (pending == null) throw StateError('WHATSAPP_AUTH_NOT_STARTED');
    final result = await _repository.verifyWhatsApp(pending, code);
    ref.read(whatsAppAuthPendingProvider.notifier).state = null;
    state = AsyncData(result.user);
    return result;
  }

  Future<AuthResult> register({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    final result = await _repository.register(
      name: name,
      email: email,
      phone: phone,
      password: password,
    );
    state = AsyncData(result.user);
    return result;
  }

  Future<AuthResult> login({
    required String login,
    required String password,
  }) async {
    final result = await _repository.login(login: login, password: password);
    state = AsyncData(result.user);
    return result;
  }

  Future<void> logout() async {
    try {
      await _repository.logout();
    } finally {
      // The repository clears the local token even when the server is offline.
      // Keep the visible session and pending login state consistent with it.
      ref.read(whatsAppAuthPendingProvider.notifier).state = null;
      state = const AsyncData(null);
    }
  }

  Future<String?> requestPhoneVerification() =>
      _repository.requestPhoneVerification();

  Future<void> verifyPhone(String code) async {
    state = AsyncData(await _repository.verifyPhone(code));
  }

  Future<void> completeProfile(String name) async {
    state = AsyncData(await _repository.completeProfile(name));
  }

  Future<void> updateProfile({
    required String name,
    required String phone,
  }) async {
    state = AsyncData(
      await _repository.updateProfile(name: name, phone: phone),
    );
  }

  Future<String?> requestPasswordReset(String login) =>
      _repository.requestPasswordReset(login);

  Future<void> resetPassword({
    required String login,
    required String code,
    required String password,
  }) async {
    await _repository.resetPassword(
      login: login,
      code: code,
      password: password,
    );
    state = const AsyncData(null);
  }

  Future<void> refresh() async {
    state = AsyncData(await _repository.restoreSession());
  }
}

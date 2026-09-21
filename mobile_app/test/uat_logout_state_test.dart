import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';

class _LogoutRepository implements AuthRepository {
  Object? failure;

  @override
  Future<AuthUser?> restoreSession() async => AuthUser.fromJson({
        'id': 1,
        'name': 'UAT test user',
        'account_status': 'active',
      });

  @override
  Future<void> logout() async {
    if (failure != null) throw failure!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final offline in [false, true]) {
    test('logout clears visible session and pending login (offline=$offline)',
        () async {
      final repository = _LogoutRepository();
      if (offline) {
        repository.failure = DioException(
          requestOptions: RequestOptions(path: '/auth/logout'),
          type: DioExceptionType.connectionError,
        );
      }
      final container = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(repository),
      ]);
      addTearDown(container.dispose);
      expect(await container.read(authControllerProvider.future), isNotNull);
      container.read(whatsAppAuthPendingProvider.notifier).state =
          const WhatsAppAuthPending(phone: 'test-only', isNewAccount: false);

      final logout = container.read(authControllerProvider.notifier).logout();
      if (offline) {
        await expectLater(logout, throwsA(isA<DioException>()));
      } else {
        await logout;
      }
      expect(container.read(authControllerProvider).requireValue, isNull);
      expect(container.read(whatsAppAuthPendingProvider), isNull);
    });
  }
}

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/local/stage6_secure_session_store.dart';
import '../../../core/network/api_client.dart';
import '../../account/data/account_request_scope.dart';

final messageTypingRepositoryProvider =
    Provider<MessageTypingRepository>((ref) {
  return MessageTypingRepository(
    ref.watch(dioProvider),
    ref.watch(accountRequestScopeProvider),
  );
});

class MessageTypingRepository {
  MessageTypingRepository(this._dio, this._scope);

  final Dio _dio;
  final AccountRequestScope _scope;

  Future<bool> read(int threadId) => _request(threadId);

  Future<void> setTyping(int threadId, bool typing) async {
    await _request(threadId, typing: typing);
  }

  Future<bool> _request(int threadId, {bool? typing}) async {
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    final options = await _scope.options();
    _scope.verify();
    if (epoch != Stage6SecureSessionStore.instance.sessionEpoch) {
      throw StateError('ACCOUNT_CHANGED');
    }
    final response = await _dio.request<Map<String, dynamic>>(
      '/messages/threads/$threadId/typing',
      data: typing == null ? null : {'typing': typing},
      options: options.copyWith(method: typing == null ? 'GET' : 'POST'),
    );
    _scope.verify();
    if (epoch != Stage6SecureSessionStore.instance.sessionEpoch) {
      throw StateError('ACCOUNT_CHANGED');
    }
    final data = response.data?['data'];
    return data is Map && data['other_typing'] == true;
  }
}

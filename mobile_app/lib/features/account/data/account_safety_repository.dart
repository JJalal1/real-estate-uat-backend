import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import 'auth_controller.dart';
import 'auth_repository.dart';
import 'account_request_scope.dart';

final accountSafetyRepositoryProvider = Provider.autoDispose<AccountSafetyRepository>((ref) {
  final actor = ref.watch(authControllerProvider.select((s) => s.asData?.value?.id));
  return AccountSafetyRepository(ref.watch(dioProvider), ref.watch(authRepositoryProvider),
    requestScope: ref.watch(accountRequestScopeProvider), actorId: actor, currentActor: () => ref.read(authControllerProvider).asData?.value?.id);
});

class BlockedAccount {
  const BlockedAccount(this.id, this.name);
  final int id;
  final String name;
}
class BlockedAccountPage {
  const BlockedAccountPage(this.accounts, this.hasMore);
  final List<BlockedAccount> accounts;
  final bool hasMore;
}
class DeletionRequestStatus {
  const DeletionRequestStatus({required this.status, this.reference, this.caseId});
  final String status;
  final String? reference;
  final int? caseId;
  bool get hasRequest => caseId != null && reference != null;
  String get label => switch (status) {
    'open' => 'وصل الطلب للمراجعة',
    'in_progress' => 'قيد المراجعة',
    'waiting_requester' => 'الدعم ينتظر ردك',
    'resolved' => 'تمت مراجعة الطلب',
    'dismissed' => 'أُغلق الطلب',
    _ => 'لم يُرسل طلب',
  };
}
class AccountSafetyRepository {
  AccountSafetyRepository(this._dio, this._auth, {required this.actorId, required this.currentActor, AccountRequestScope? requestScope})
    : _requestScope = requestScope;
  final Dio _dio;
  final AuthRepository _auth;
  final AccountRequestScope? _requestScope;
  final int? actorId;
  final int? Function() currentActor;
  Future<Options> _options() async {
    _requestScope?.verify();
    if (actorId == null || currentActor() != actorId) throw StateError('ACCOUNT_CHANGED');
    final options = await (_requestScope?.options() ?? _auth.requiredAuthOptions());
    _requestScope?.verify();
    if (currentActor() != actorId) throw StateError('ACCOUNT_CHANGED');
    return options;
  }
  Future<BlockedAccountPage> blocked({int page = 1}) async {
    final response = await _dio.get<Map<String, dynamic>>('/account/blocked-users',
      queryParameters: {'page': page}, options: await _options());
    _requestScope?.verify();
    final rows = response.data?['data'];
    final meta = response.data?['meta'];
    if (rows is! List || meta is! Map) throw StateError('Invalid blocked users response');
    return BlockedAccountPage(rows.whereType<Map>().map((row) => BlockedAccount(
      (row['id'] as num).toInt(), row['name']?.toString() ?? 'مستخدم')).toList(growable: false),
      (meta['current_page'] as num) < (meta['last_page'] as num));
  }
  Future<void> setBlocked(int userId, bool blocked) async {
    final options = await _options();
    final response = blocked
      ? await _dio.put<Map<String, dynamic>>('/users/$userId/messaging-block', options: options)
      : await _dio.delete<Map<String, dynamic>>('/users/$userId/messaging-block', options: options);
    _requestScope?.verify();
    final data = response.data?['data'];
    if (data is! Map || data['user_id'] != userId || data['blocked_by_me'] != blocked) {
      throw StateError('Invalid block confirmation');
    }
  }
  Future<DeletionRequestStatus> deletionStatus() async {
    final response = await _dio.get<Map<String, dynamic>>('/account/deletion-request', options: await _options());
    return _deletion(response.data);
  }
  Future<DeletionRequestStatus> requestDeletion() async {
    final response = await _dio.post<Map<String, dynamic>>('/account/deletion-request',
      data: {'confirmed': true}, options: await _options());
    final status = _deletion(response.data);
    if (!status.hasRequest) throw StateError('Missing request receipt');
    return status;
  }
  Future<void> eraseAccount() async {
    final response = await _dio.delete<Map<String, dynamic>>(
      '/account',
      data: {'confirm_phrase': 'حذف حسابي نهائيًا'},
      options: await _options(),
    );
    _requestScope?.verify();
    final data = response.data?['data'];
    if (data is! Map ||
        data['account_deleted'] != true ||
        data['access_revoked'] != true ||
        data['personal_identity_erased'] != true) {
      throw StateError('Invalid account deletion confirmation');
    }
  }
  DeletionRequestStatus _deletion(Map<String, dynamic>? body) {
    _requestScope?.verify();
    final data = body?['data'];
    if (data is! Map || data['status'] is! String) throw StateError('Invalid deletion request response');
    return DeletionRequestStatus(status: data['status'] as String,
      reference: data['reference']?.toString(), caseId: (data['case_id'] as num?)?.toInt());
  }
}

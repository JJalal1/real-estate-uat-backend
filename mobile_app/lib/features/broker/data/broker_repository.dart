import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/local/stage6_secure_session_store.dart';
import '../../account/data/account_request_scope.dart';
import '../../account/data/private_collection.dart';
import '../../account/data/auth_repository.dart';
import '../../account/data/auth_controller.dart';
import '../domain/broker_models.dart';

final brokerRepositoryProvider = Provider<BrokerRepository>((ref) => BrokerRepository(ref.watch(dioProvider), ref.watch(authRepositoryProvider), requestScope: ref.watch(accountRequestScopeProvider)));
final brokerGovernorateProvider = StateProvider<String?>((ref) => 'أمانة العاصمة');
final brokerDirectoryProvider = FutureProvider.autoDispose<List<BrokerProfile>>((ref) async =>
  (await ref.watch(brokerRepositoryProvider).directory(governorate: ref.watch(brokerGovernorateProvider), perPage: 5)).items);
final brokerProfileProvider = FutureProvider.autoDispose.family<BrokerProfile, int>((ref, id) => ref.watch(brokerRepositoryProvider).profile(id));
final brokerWorkspaceProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
  ref.watch(authControllerProvider.select((state) => state.asData?.value?.id));
  return ref.watch(brokerRepositoryProvider).workspace();
});
final brokerAvailabilityProvider = FutureProvider.autoDispose<List<BrokerAvailability>>((ref) {
  ref.watch(authControllerProvider.select((state) => state.asData?.value?.id));
  return ref.watch(brokerRepositoryProvider).availability();
});
final brokerAvailabilityPagesProvider = StateNotifierProvider.autoDispose.family<
    PrivateCollectionController<BrokerAvailability>, PrivateCollectionState<BrokerAvailability>, bool>((ref, onlyDue) {
  final repository = ref.watch(brokerRepositoryProvider);
  return accountCollection(ref, load: (page) => repository.availabilityPage(page: page, onlyDue: onlyDue),
    idOf: (BrokerAvailability item) => item.id);
});
final brokerFinanceProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
  ref.watch(authControllerProvider.select((state) => state.asData?.value?.id));
  return ref.watch(brokerRepositoryProvider).finance();
});
final brokerDealProvider = FutureProvider.autoDispose.family<BrokerDeal, int>((ref, id) {
  ref.watch(authControllerProvider.select((state) => state.asData?.value?.id));
  return ref.watch(brokerRepositoryProvider).deal(id);
});
final brokerThreadDealProvider = FutureProvider.autoDispose.family<BrokerDeal?, int>((ref, id) async {
  ref.watch(authControllerProvider.select((state) => state.asData?.value?.id));
  final rows = await ref.watch(brokerRepositoryProvider).activity(threadId: id);
  return rows.items.isEmpty ? null : rows.items.first;
});

class BrokerRepository {
  BrokerRepository(this._dio, this._auth, {AccountRequestScope? requestScope}) : _requestScope = requestScope;
  final Dio _dio;
  final AuthRepository _auth;
  final AccountRequestScope? _requestScope;
  Future<Map<String, dynamic>> _get(String path, {Map<String, dynamic>? query, bool public = false}) async {
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    void verify() {
      if (public) { return; }
      _requestScope?.verify();
      if (epoch != Stage6SecureSessionStore.instance.sessionEpoch) { throw StateError('ACCOUNT_CHANGED'); }
    }
    verify();
    final options = public ? await _auth.optionalAuthOptions()
      : await (_requestScope?.options() ?? _auth.requiredAuthOptions());
    verify();
    final r = await _dio.get<Map<String, dynamic>>(path, queryParameters: query, options: options);
    verify();
    return r.data ?? const {};
  }
  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> data) async =>
    (await _dio.post<Map<String, dynamic>>(path, data: data, options: await _auth.requiredAuthOptions())).data ?? const {};
  BrokerPage<T> _page<T>(Map<String, dynamic> body, T Function(Map<String, dynamic>) parse) {
    final meta = brokerMap(body['meta']);
    return BrokerPage(items: brokerRows(body['data']).map(parse).toList(), page: brokerInt(meta['current_page']) == 0 ? 1 : brokerInt(meta['current_page']),
      lastPage: brokerInt(meta['last_page']) == 0 ? 1 : brokerInt(meta['last_page']));
  }
  Future<BrokerPage<BrokerProfile>> directory({String? governorate, int page = 1, int perPage = 15, bool regionOnly = false, String? search, String? specialty, String? accountType, double? minRating}) async =>
    _page(await _get('/brokers', public: true, query: {'page': page, 'per_page': perPage, if (governorate != null) 'governorate': governorate, if (regionOnly) 'region_only': 1,
      if (search?.trim().isNotEmpty == true) 'search': search!.trim(), if (specialty?.isNotEmpty == true) 'specialty': specialty,
      if (accountType != null) 'account_type': accountType, if (minRating != null) 'min_rating': minRating}), BrokerProfile.fromJson);
  Future<BrokerProfile> profile(int id) async => BrokerProfile.fromJson(brokerMap((await _get('/advertisers/$id/profile', public: true))['data']));
  Future<Map<String, dynamic>> workspace() async => brokerMap((await _get('/broker/workspace'))['data']);
  Future<BrokerPage<BrokerCustomer>> customers({String? stage, int? propertyId, int page = 1, String? filter}) async =>
    _page(await _get('/broker/customers', query: {'page': page, if (stage != null) 'stage': stage, if (propertyId != null) 'property_id': propertyId,
      if (filter != null && filter != 'all') 'filter': filter}), BrokerCustomer.fromJson);
  Future<Map<String, dynamic>> followup(int threadId) async => brokerMap((await _get('/broker/customers/$threadId/followup'))['data']);
  Future<void> saveFollowup(int threadId, {required String note, DateTime? remindAt}) async {
    await _dio.patch<void>('/broker/customers/$threadId/followup', data: {'private_note': note.trim(), 'remind_at': remindAt?.toUtc().toIso8601String()},
      options: await _auth.requiredAuthOptions());
  }
  Future<void> updateCustomer(int threadId, String stage) async {
    await _dio.patch<void>('/broker/customers/$threadId/stage', data: {'stage': stage}, options: await _auth.requiredAuthOptions());
  }
  Future<List<BrokerAvailability>> availability() async => brokerRows((await _get('/broker/listings/availability'))['data']).map(BrokerAvailability.fromJson).toList();
  Future<PrivateCollectionPage<BrokerAvailability>> availabilityPage({int page = 1, bool onlyDue = false}) async {
    if (page < 1) throw ArgumentError.value(page, 'page');
    return PrivateCollectionPage.parse(await _get('/broker/listings/availability',
      query: {'page': page, 'per_page': 50, 'only_due': onlyDue ? 1 : 0}),
      requestedPage: page, parse: BrokerAvailability.fromJson);
  }
  Future<void> updateAvailability(List<int> ids, String state) async {
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    final options = await (_requestScope?.options() ?? _auth.requiredAuthOptions());
    void verify() {
      _requestScope?.verify();
      if (epoch != Stage6SecureSessionStore.instance.sessionEpoch) { throw StateError('ACCOUNT_CHANGED'); }
    }
    verify();
    await _dio.post<void>('/broker/listings/availability', data: {'property_ids': ids, 'state': state}, options: options);
    verify();
  }
  Future<BrokerDeal> reportDeal(int threadId, {double? amount}) async => BrokerDeal.fromJson(brokerMap((await _post('/broker/customers/$threadId/completed-deal', {if (amount != null) 'basis_amount': amount}))['data']));
  Future<BrokerPage<BrokerDeal>> activity({int? threadId, int page = 1}) async =>
    _page(await _get('/broker/activity', query: {'page': page, if (threadId != null) 'thread_id': threadId}), BrokerDeal.fromJson);
  Future<BrokerDeal> deal(int id) async => BrokerDeal.fromJson(brokerMap((await _get('/broker/deals/$id'))['data']));
  Future<BrokerDeal> decide(int id, bool confirmed) async => BrokerDeal.fromJson(brokerMap((await _post('/broker/deals/$id/decision', {'confirmed': confirmed}))['data']));
  Future<Map<String, dynamic>> finance() async => brokerMap((await _get('/broker/finance'))['data']);
  Future<void> updateBio(String bio) async { await _dio.patch<void>('/broker/profile', data: {'bio': bio}, options: await _auth.requiredAuthOptions()); }
  Future<void> uploadPhoto(String path) async {
    await _dio.post<void>('/broker/profile/photo', data: FormData.fromMap({'photo': await MultipartFile.fromFile(path)}), options: await _auth.requiredAuthOptions());
  }
  Future<void> resolveSupport(int taskId, String decision, String note, {bool actingAsAgent = false}) async {
    await _post('/broker/support/tasks/$taskId/resolution', {'decision': decision, 'note': note, 'acting_as_agent': actingAsAgent});
  }
}

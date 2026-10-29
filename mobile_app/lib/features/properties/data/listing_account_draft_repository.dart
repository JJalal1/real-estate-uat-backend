import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../account/data/auth_repository.dart';
import '../../account/data/auth_controller.dart';
import '../domain/listing_account_draft.dart';

final listingAccountDraftRepositoryProvider = Provider<ListingAccountDraftRepository>((ref) {
  ref.watch(authControllerProvider.select((state) => state.asData?.value?.id));
  return ListingAccountDraftRepository(ref.watch(dioProvider), ref.watch(authRepositoryProvider));
});

class ListingAccountDraftRepository {
  ListingAccountDraftRepository(this._dio, AuthRepository auth) : _options = auth.requiredAuthOptions();
  final Dio _dio;
  // Capture the originating session, so queued saves cannot move to another account.
  final Future<Options> _options;
  static const _base = '/listing-editor-drafts';
  bool supportsSafeRecovery = false;
  ListingAccountDraft _draft(Response<dynamic> response) => ListingAccountDraft.fromJson(Map<String, dynamic>.from(response.data['data'] as Map));
  Future<List<ListingAccountDraft>> list() async {
    final rows = <ListingAccountDraft>[]; var page = 1;
    while (true) {
      final r = await _dio.get<dynamic>(_base, queryParameters: {'page': page}, options: await _options);
      if (page == 1) supportsSafeRecovery = (r.data['meta'] as Map?)?['recovery_contract'] == 1;
      rows.addAll((r.data['data'] as List).map((e) => ListingAccountDraft.fromJson(Map<String, dynamic>.from(e as Map))));
      if (page >= ((r.data['meta'] as Map?)?['last_page'] as num? ?? 1)) break;
      page++;
    }
    return rows;
  }
  Future<ListingAccountDraft> get(String key) async => _draft(await _dio.get<dynamic>('$_base/$key', options: await _options));
  Future<ListingAccountDraft> save(String key, Map<String, dynamic> payload, int revision, {int? propertyId}) async =>
    _draft(await _dio.put<dynamic>('$_base/$key', data: {'payload': payload, 'expected_revision': revision,
      if (propertyId != null) 'property_id': propertyId}, options: await _options));
  Future<ListingAccountDraft> upload(String key, String imageKey, String path, int revision,
      {CancelToken? cancelToken, ProgressCallback? onSendProgress}) async {
    final token = cancelToken ?? CancelToken();
    final request = _dio.post<dynamic>('$_base/$key/images/$imageKey', data: FormData.fromMap({
      'expected_revision': revision, 'image': await MultipartFile.fromFile(path)}),
      options: (await _options).copyWith(sendTimeout: const Duration(seconds:60), receiveTimeout: const Duration(seconds:90)),
      cancelToken:token, onSendProgress:onSendProgress);
    return _draft(await request.timeout(const Duration(minutes:2),onTimeout:() {
      token.cancel('Upload deadline'); throw TimeoutException('تعذر إكمال رفع الصورة. أعد محاولة هذه الصورة فقط.');
    }));
  }
  Future<ListingAccountDraft> removeImage(String key, String imageKey, int revision) async =>
    _draft(await _dio.delete<dynamic>('$_base/$key/images/$imageKey', data: {'expected_revision': revision}, options: await _options));
  Future<void> delete(String key) async { await _dio.delete<dynamic>('$_base/$key', options: await _options); }
  Future<void> retireRecovery(String key, int revision) async {
    if (!supportsSafeRecovery) throw StateError('يلزم تحديث خدمة حفظ المسودات قبل حذف التقدم المؤقت. بياناتك محفوظة.');
    await _dio.delete<dynamic>('$_base/$key', data: {'recovery_only': true, 'expected_revision': revision}, options: await _options);
  }
  Future<Uint8List> photo(String url, {CancelToken? cancelToken}) async {
    final target=Uri.parse(url), base=Uri.parse(_dio.options.baseUrl);
    if (target.origin != base.origin || !(target.path.startsWith('${base.path}/listing-editor-drafts/') ||
        RegExp('^${RegExp.escape(base.path)}/property-media/[0-9]+\$').hasMatch(target.path))) {
      throw StateError('Invalid private image location');
    }
    final token=cancelToken ?? CancelToken();
    final r = await _dio.get<List<int>>(url, options: (await _options).copyWith(responseType: ResponseType.bytes),cancelToken:token)
      .timeout(const Duration(seconds:25),onTimeout:() { token.cancel('Image deadline'); throw TimeoutException('تعذر تحميل الصورة.'); });
    return Uint8List.fromList(r.data ?? const []);
  }
}

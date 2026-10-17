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
  ListingAccountDraft _draft(Response<dynamic> response) => ListingAccountDraft.fromJson(Map<String, dynamic>.from(response.data['data'] as Map));
  Future<List<ListingAccountDraft>> list() async {
    final rows = <ListingAccountDraft>[]; var page = 1;
    while (true) {
      final r = await _dio.get<dynamic>(_base, queryParameters: {'page': page}, options: await _options);
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
  Future<ListingAccountDraft> upload(String key, String imageKey, String path, int revision) async =>
    _draft(await _dio.post<dynamic>('$_base/$key/images/$imageKey', data: FormData.fromMap({
      'expected_revision': revision, 'image': await MultipartFile.fromFile(path)}), options: await _options));
  Future<ListingAccountDraft> removeImage(String key, String imageKey, int revision) async =>
    _draft(await _dio.delete<dynamic>('$_base/$key/images/$imageKey', data: {'expected_revision': revision}, options: await _options));
  Future<void> delete(String key) async { await _dio.delete<dynamic>('$_base/$key', options: await _options); }
  Future<Uint8List> photo(String url) async {
    final r = await _dio.get<List<int>>(url, options: (await _options).copyWith(responseType: ResponseType.bytes));
    return Uint8List.fromList(r.data ?? const []);
  }
}

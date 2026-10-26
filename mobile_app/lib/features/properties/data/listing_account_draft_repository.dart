import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'private_tus_image_uploader.dart';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/local/stage6_secure_session_store.dart';
import '../../account/data/auth_repository.dart';
import '../../account/data/auth_controller.dart';
import '../domain/listing_account_draft.dart';

final listingAccountDraftRepositoryProvider = Provider<ListingAccountDraftRepository>((ref) {
  final actor=ref.watch(authControllerProvider.select((state) => state.asData?.value?.id));
  return ListingAccountDraftRepository(ref.watch(dioProvider), ref.watch(authRepositoryProvider),actorId:actor);
});

class ListingAccountDraftRepository {
  ListingAccountDraftRepository(this._dio, AuthRepository auth,{int? actorId})
      : _capturedOptions = auth.requiredAuthOptions(), _actorId=actorId,
        _epoch=Stage6SecureSessionStore.instance.sessionEpoch;
  final Dio _dio;
  // Capture the originating session, so queued saves cannot move to another account.
  final Future<Options> _capturedOptions;
  final int? _actorId;
  final int _epoch;
  void _verify() {
    if (_epoch!=Stage6SecureSessionStore.instance.sessionEpoch) throw StateError('ACCOUNT_CHANGED');
  }
  Future<Options> get _options async {
    _verify(); final options=await _capturedOptions; _verify(); return options;
  }
  static const _base = '/listing-editor-drafts';
  ListingAccountDraft _draft(Response<dynamic> response) {
    _verify();
    return ListingAccountDraft.fromJson(Map<String, dynamic>.from(response.data['data'] as Map));
  }
  Future<List<ListingAccountDraft>> list() async {
    final rows = <ListingAccountDraft>[]; var page = 1;
    while (true) {
      final r = await _dio.get<dynamic>(_base, queryParameters: {'page': page}, options: await _options);
      _verify();
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
  /// Staged TUS path is an explicit UAT build flag and never a silent production switch.
  static const resumableBuildEnabled = bool.fromEnvironment('AQER_IMAGE_TUS_ENABLED',defaultValue:false);

  Future<ListingAccountDraft> uploadResumable(String key,String imageKey,String path,int revision,
      {CancelToken? cancelToken,ProgressCallback? onSendProgress}) async {
    final token=cancelToken??CancelToken();
    if (!resumableBuildEnabled) {
      return upload(key,imageKey,path,revision,cancelToken:token,onSendProgress:onSendProgress);
    }
    _verify();
    if ((_actorId ?? 0) <= 0) throw StateError('AUTH_REQUIRED');
    final file=File(path),length=await file.length();
    if(length<=0 || length>8*1024*1024) throw StateError('حجم الصورة غير مقبول');
    final bytes=await file.readAsBytes();
    final hash=sha256.convert(bytes).toString();
    if (bytes.length!=length) throw StateError('تغير ملف الصورة أثناء التجهيز');
    final mime=bytes.length>=3 && bytes[0]==0xff && bytes[1]==0xd8 && bytes[2]==0xff
      ? 'image/jpeg' : bytes.length>=8 && bytes[0]==0x89 && bytes[1]==0x50 && bytes[2]==0x4e && bytes[3]==0x47
      ? 'image/png' : bytes.length>=12 && String.fromCharCodes(bytes.sublist(0,4))=='RIFF' &&
        String.fromCharCodes(bytes.sublist(8,12))=='WEBP' ? 'image/webp' : null;
    if(mime==null) throw StateError('نوع الصورة غير مدعوم');
    final options=await _options;
    final ticket=await _dio.post<dynamic>('$_base/$key/images/$imageKey/resumable-ticket',
      data:{'expected_revision':revision,'sha256':hash,'byte_length':length,'mime':mime},options:options,cancelToken:token);
    final data=Map<String,dynamic>.from(ticket.data['data'] as Map);
    _verify();
    final signature=data['signature'] as String;
    // A new session of the same account can resume. Other accounts have a
    // different opaque scope and must first pass Laravel draft ownership.
    final scope=sha256.convert(utf8.encode('$_actorId|$key|$imageKey|$hash')).toString();
    final transport = Dio(BaseOptions(connectTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 90), receiveTimeout: const Duration(seconds: 90)));
    final uploader = PrivateTusImageUploader(transport);
    try {
    await uploader.upload(source:path,scope:scope,
      endpoint:data['endpoint'] as String,bucket:data['bucket'] as String,
      objectName:data['object_name'] as String,signature:signature,publishableKey:data['publishable_key'] as String,mime:mime,
      cancelToken:token,progress:onSendProgress);
    _verify();
    final finished=await _dio.post<dynamic>('$_base/$key/images/$imageKey/resumable-finalize',
      data:{'expected_revision':revision},options:options,cancelToken:token);
    _verify(); await uploader.forget(scope);
    return _draft(finished);
    } finally { transport.close(force: true); }
  }

  Future<ListingAccountDraft> removeImage(String key, String imageKey, int revision) async =>
    _draft(await _dio.delete<dynamic>('$_base/$key/images/$imageKey', data: {'expected_revision': revision}, options: await _options));
  Future<void> delete(String key) async { await _dio.delete<dynamic>('$_base/$key', options: await _options); }
  Future<Uint8List> photo(String url, {CancelToken? cancelToken}) async {
    final target=Uri.parse(url), base=Uri.parse(_dio.options.baseUrl);
    if (target.origin != base.origin || !(target.path.startsWith('${base.path}/listing-editor-drafts/') ||
        RegExp('^${RegExp.escape(base.path)}/property-media/[0-9]+\$').hasMatch(target.path))) {
      throw StateError('Invalid private image location');
    }
    final token=cancelToken ?? CancelToken();
    final r = await _dio.get<List<int>>(url, options: (await _options).copyWith(responseType: ResponseType.bytes),cancelToken:token)
      .timeout(const Duration(seconds:25),onTimeout:() { token.cancel('Image deadline'); throw TimeoutException('تعذر تحميل الصورة.'); });
    _verify();
    return Uint8List.fromList(r.data ?? const []);
  }
}

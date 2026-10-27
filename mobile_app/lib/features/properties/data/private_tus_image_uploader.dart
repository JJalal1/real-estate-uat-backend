import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/local/stage6_secure_session_store.dart';

/// Private Supabase TUS transport. No service key or signed token is stored.
/// The source file is retained by the editor's local recovery mechanism.
class PrivateTusImageUploader {
  PrivateTusImageUploader(this.dio, {Future<Directory> Function()? directory})
      : _directory = directory, _epoch=Stage6SecureSessionStore.instance.sessionEpoch;
  final Dio dio;
  final Future<Directory> Function()? _directory;
  final int _epoch;
  static final Set<String> _activeScopes={};
  static const chunkSize = 6 * 1024 * 1024;

  Future<Directory> _folder() async {
    final base = await (_directory?.call() ?? getApplicationSupportDirectory());
    final target = Platform.isAndroid && _directory == null
        ? Directory('${base.parent.path}/no_backup/aqer_tus') : Directory('${base.path}/aqer_tus');
    await target.create(recursive: true);
    return target;
  }

  Future<File> _session(String scope) async {
    final folder = await _folder();
    return File('${folder.path}/${sha256.convert(utf8.encode(scope))}.json');
  }

  static Uri _trusted(Uri endpoint, String location) {
    if (endpoint.scheme != 'https' || endpoint.userInfo.isNotEmpty || endpoint.hasQuery || endpoint.hasFragment) {
      throw StateError('Invalid storage endpoint');
    }
    final resolved = endpoint.resolve(location);
    if (resolved.scheme != 'https' || resolved.origin != endpoint.origin ||
        resolved.userInfo.isNotEmpty || resolved.hasQuery || resolved.hasFragment ||
        !resolved.path.startsWith('/storage/v1/upload/resumable/')) {
      throw StateError('Storage upload location changed origin or route');
    }
    return resolved;
  }

  Future<void> upload({
    required String source,
    required String scope,
    required String endpoint,
    required String bucket,
    required String objectName,
    required String signature,
    required String publishableKey,
    required String mime,
    required CancelToken cancelToken,
    ProgressCallback? progress,
  }) async {
    void verify() {
      if (_epoch!=Stage6SecureSessionStore.instance.sessionEpoch) {
        cancelToken.cancel('Account changed');
        throw StateError('ACCOUNT_CHANGED');
      }
      if (cancelToken.isCancelled) throw StateError('Upload canceled');
    }
    verify();
    if (!_activeScopes.add(scope)) throw StateError('UPLOAD_BUSY');
    try {
    if (dio.options.headers.keys.any((key)=>['authorization','cookie','proxy-authorization'].contains(key.toLowerCase()))) {
      throw StateError('Authenticated API headers cannot be used for storage');
    }
    final target = Uri.parse(endpoint);
    if (target.scheme != 'https' || target.path != '/storage/v1/upload/resumable/sign' ||
        target.userInfo.isNotEmpty || target.hasQuery || target.hasFragment) {
      throw StateError('Invalid resumable endpoint');
    }
    final file = File(source);
    final length = await file.length();
    if (length <= 0 || length > 8 * 1024 * 1024) throw StateError('Image exceeds upload limit');
    final sessionFile = await _session(scope);
    Uri? session;
    if (await sessionFile.exists()) {
      try {
        final record = jsonDecode(await sessionFile.readAsString());
        if (record is Map && record['endpoint'] == endpoint &&
            record['bucket'] == bucket && record['objectName'] == objectName &&
            record['length'] == length && record['url'] is String) {
          session = _trusted(target, record['url'] as String);
        }
      } catch (_) { /* Old or tampered session: start clean. */ }
    }
    var publicKey=RegExp(r'^sb_publishable_[A-Za-z0-9_-]{1,200}$').hasMatch(publishableKey);
    if (!publicKey && publishableKey.length<=4096 && publishableKey.split('.').length==3) {
      try {
        final claims=jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(publishableKey.split('.')[1]))));
        publicKey=claims is Map && claims['role']=='anon';
      } catch (_) { publicKey=false; }
    }
    if (!publicKey) {
      throw StateError('Unsupported public storage key');
    }
    verify();
    final headers = <String, dynamic>{'Tus-Resumable':'1.0.0', 'x-signature':signature, 'apikey':publishableKey};
    int offset = 0;
    if (session != null) {
      try {
        final head = await dio.head<dynamic>(session.toString(),
          options: Options(headers:headers, followRedirects:false),
          cancelToken:cancelToken);
        verify();
        offset = int.parse(head.headers.value('upload-offset') ?? '-1');
        if (offset < 0 || offset > length) throw StateError('Invalid server offset');
      } on DioException catch (e) {
        if (e.response?.statusCode != 404 && e.response?.statusCode != 410) rethrow;
        session = null;
      }
    }
    if (session == null) {
      verify();
      final metadata = <String, String>{
        'bucketName':bucket,'objectName':objectName,'contentType':mime,'cacheControl':'3600'
      };
      final encoded = metadata.entries.map((e)=>'${e.key} ${base64Encode(utf8.encode(e.value))}').join(',');
      final response = await dio.post<dynamic>(endpoint,
        data: const <int>[],
        options: Options(headers:{...headers,'Upload-Length':length,
          'Upload-Metadata':encoded,'Content-Type':'application/offset+octet-stream'},
          followRedirects:false), cancelToken:cancelToken);
      final location = response.headers.value('location');
      verify();
      if (location == null) throw StateError('Storage did not return upload location');
      session = _trusted(target, location);
      final temporary=File('${sessionFile.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp');
      try {
        await temporary.writeAsString(jsonEncode({'url':session.toString(),
          'endpoint':endpoint,'bucket':bucket,'objectName':objectName,'length':length}),flush:true);
        verify(); await temporary.rename(sessionFile.path);
      } finally { if(await temporary.exists()) await temporary.delete(); }
    }
    final handle = await file.open();
    try {
      while (offset < length) {
        verify();
        await handle.setPosition(offset);
        final data = await handle.read(length - offset > chunkSize ? chunkSize : length - offset);
        verify();
        if (data.isEmpty) throw StateError('Source truncated during upload');
        final response = await dio.patch<dynamic>(session.toString(),
          data:data,
          options:Options(headers:{...headers,'Upload-Offset':offset,
            'Content-Type':'application/offset+octet-stream'},followRedirects:false),
          cancelToken:cancelToken);
        verify();
        final acknowledged = int.parse(response.headers.value('upload-offset') ?? '-1');
        if (acknowledged != offset + data.length) throw StateError('Incorrect storage offset');
        offset = acknowledged;
        progress?.call(offset,length);
      }
    } finally { await handle.close(); }
    // Retain even a complete session until Laravel confirms finalization.
    // A lost finalize response must not force a conflicting second POST.
    } finally { _activeScopes.remove(scope); }
  }

  Future<void> forget(String scope) async {
    final file = await _session(scope);
    if (await file.exists()) await file.delete();
  }
}

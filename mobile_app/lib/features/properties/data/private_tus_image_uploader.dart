import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

/// Private Supabase TUS transport. No service key or signed token is stored.
/// The source file is retained by the editor's local recovery mechanism.
class PrivateTusImageUploader {
  PrivateTusImageUploader(this.dio, {Future<Directory> Function()? directory})
      : _directory = directory;
  final Dio dio;
  final Future<Directory> Function()? _directory;
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
    if (!publishableKey.startsWith('sb_publishable_') && !publishableKey.startsWith('eyJ')) {
      throw StateError('Unsupported public storage key');
    }
    final headers = <String, dynamic>{'Tus-Resumable':'1.0.0', 'x-signature':signature, 'apikey':publishableKey};
    int offset = 0;
    if (session != null) {
      try {
        final head = await dio.head<dynamic>(session.toString(),
          options: Options(headers:headers, followRedirects:false),
          cancelToken:cancelToken);
        offset = int.parse(head.headers.value('upload-offset') ?? '-1');
        if (offset < 0 || offset > length) throw StateError('Invalid server offset');
      } on DioException catch (e) {
        if (e.response?.statusCode != 404 && e.response?.statusCode != 410) rethrow;
        session = null;
      }
    }
    if (session == null) {
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
      if (location == null) throw StateError('Storage did not return upload location');
      session = _trusted(target, location);
      await sessionFile.writeAsString(jsonEncode({'url':session.toString(),
        'endpoint':endpoint,'bucket':bucket,'objectName':objectName,'length':length}),flush:true);
    }
    final handle = await file.open();
    try {
      while (offset < length) {
        if (cancelToken.isCancelled) throw StateError('Upload canceled');
        await handle.setPosition(offset);
        final data = await handle.read(length - offset > chunkSize ? chunkSize : length - offset);
        if (data.isEmpty) throw StateError('Source truncated during upload');
        final response = await dio.patch<dynamic>(session.toString(),
          data:data,
          options:Options(headers:{...headers,'Upload-Offset':offset,
            'Content-Type':'application/offset+octet-stream'},followRedirects:false),
          cancelToken:cancelToken);
        final acknowledged = int.parse(response.headers.value('upload-offset') ?? '-1');
        if (acknowledged != offset + data.length) throw StateError('Incorrect storage offset');
        offset = acknowledged;
        progress?.call(offset,length);
      }
    } finally { await handle.close(); }
    if (await sessionFile.exists()) await sessionFile.delete();
  }
}

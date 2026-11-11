import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'public_photo_disk_cache.dart';

class PublicPhotoTransfer {
  const PublicPhotoTransfer(this.bytes, {this.downloadedBytes = 0, this.notModified = false});
  final Uint8List bytes;
  final int downloadedBytes;
  final bool notModified;
}

class PublicPhotoLoader {
  const PublicPhotoLoader(this.dio, this.disk);
  final Dio dio;
  final PublicPhotoDiskCache disk;

  Future<PublicPhotoTransfer> load(String url, {required CancelToken cancelToken,
    int? backgroundByteLimit, bool Function()? foregroundAttached,
    void Function(int)? onReceivedBytes, bool requirePublicResponse = false}) async {
    final epoch = disk.epoch;
    final cached = await disk.read(url).timeout(const Duration(milliseconds: 300), onTimeout: () => null);
    if (cancelToken.isCancelled) throw cancelToken.cancelError!;
    final response = await dio.get<List<int>>(url, options: Options(responseType: ResponseType.bytes,
      headers: {if (cached != null) 'If-None-Match': cached.etag}, followRedirects: false,
      validateStatus: (status) => status == 200 || (status == 304 && cached != null) || const [401,403,404].contains(status)),
      cancelToken: cancelToken, onReceiveProgress: (received, total) {
        onReceivedBytes?.call(received);
        if (backgroundByteLimit != null && (received > backgroundByteLimit || total > backgroundByteLimit) &&
            foregroundAttached?.call() != true) cancelToken.cancel('Conditional prefetch byte limit');
      }).timeout(const Duration(seconds: 25), onTimeout: () {
        cancelToken.cancel('Image deadline'); throw TimeoutException('Image unavailable');
      });
    if (cancelToken.isCancelled) throw cancelToken.cancelError!;
    if (const [401,403,404].contains(response.statusCode)) {
      await disk.forget(url);
      throw DioException.badResponse(statusCode: response.statusCode!, requestOptions: response.requestOptions, response: response);
    }
    if (!disk.accepts(response.headers)) unawaited(disk.forget(url));
    if (requirePublicResponse && !disk.accepts(response.headers) && foregroundAttached?.call() != true) {
      throw StateError('Speculative image response is not publicly cacheable');
    }
    // Disk bytes are never displayed before the server has revalidated public
    // visibility. Unpublication/authorization failure wins over a cached ETag.
    if (response.statusCode == 304 && cached != null) {
      return PublicPhotoTransfer(cached.bytes, notModified: true);
    }
    final bytes = Uint8List.fromList(response.data ?? const []);
    if (bytes.isEmpty || bytes.lengthInBytes > 8 * 1024 * 1024) throw StateError('Invalid display image size');
    unawaited(disk.put(url, bytes, response.headers, expectedEpoch: epoch));
    return PublicPhotoTransfer(bytes, downloadedBytes: bytes.lengthInBytes);
  }
}
